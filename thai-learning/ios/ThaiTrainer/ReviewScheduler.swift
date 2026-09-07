import Foundation

struct PracticeQueueItem: Equatable, Identifiable, Sendable {
    let key: PhraseProgressKey
    let lessonDay: Int
    let lessonTheme: String
    let sentence: LessonSentence
    let audio: PracticeSentenceAudio

    var id: String { key.id }

    static func items(for package: LessonPackage) throws -> [PracticeQueueItem] {
        let audio = try PracticeAudioPackageLoader(
            resourceRoot: package.resourceRootURL
        ).load(for: package.lesson)
        let audioByID = Dictionary(uniqueKeysWithValues: audio.map { ($0.id, $0) })
        return try package.lesson.sentences.map { sentence in
            guard let sentenceAudio = audioByID[sentence.id] else {
                throw PracticeAudioLoadingError.missingClip(sentence.id)
            }
            return PracticeQueueItem(
                key: PhraseProgressKey(
                    lessonID: package.lesson.lessonID,
                    revision: package.lesson.revision,
                    contentSHA256: package.contentSHA256,
                    sentenceID: sentence.id
                ),
                lessonDay: package.lesson.day,
                lessonTheme: package.lesson.theme,
                sentence: sentence,
                audio: sentenceAudio
            )
        }
    }
}

struct ReviewScheduler: Sendable {
    static let defaultIntervals = [1, 3, 7, 14, 30]
    static let defaultDailyLimit = 6

    let intervals: [Int]
    let againDelay: TimeInterval
    private let calendar: Calendar

    init(
        timeZone: TimeZone = TimeZone(identifier: "Asia/Bangkok")!,
        intervals: [Int] = Self.defaultIntervals,
        againDelay: TimeInterval = 10 * 60
    ) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        self.calendar = calendar
        self.intervals = intervals.isEmpty ? Self.defaultIntervals : intervals
        self.againDelay = max(60, againDelay)
    }

    func startOfDay(_ date: Date, addingDays days: Int = 0) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }

    func progress(
        for key: PhraseProgressKey,
        events: [ReviewEvent]
    ) -> SentenceProgress? {
        let matching = events
            .filter { $0.phrase == key }
            .sorted {
                if $0.reviewedAt == $1.reviewedAt {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.reviewedAt < $1.reviewedAt
            }
        guard !matching.isEmpty else { return nil }

        var easyStreak = 0
        var againCount = 0
        var nextReviewAt = matching[0].reviewedAt
        for event in matching {
            switch event.rating {
            case .again:
                easyStreak = 0
                againCount += 1
                nextReviewAt = event.reviewedAt.addingTimeInterval(againDelay)
            case .easy:
                let interval = intervals[min(easyStreak, intervals.count - 1)]
                easyStreak = min(easyStreak + 1, intervals.count)
                nextReviewAt = startOfDay(event.reviewedAt, addingDays: interval)
            }
        }
        let latest = matching[matching.count - 1]
        return SentenceProgress(
            key: key,
            reviewCount: matching.count,
            easyStreak: easyStreak,
            againCount: againCount,
            lastRating: latest.rating,
            lastReviewedAt: latest.reviewedAt,
            nextReviewAt: nextReviewAt
        )
    }

    func sessionQueue(
        catalog: [PracticeQueueItem],
        events: [ReviewEvent],
        at date: Date = Date(),
        limit: Int = Self.defaultDailyLimit
    ) -> [PracticeQueueItem] {
        Array(scheduledEntries(catalog: catalog, events: events, at: date).prefix(max(0, limit)))
            .map(\.item)
    }

    func dueReviewCount(
        catalog: [PracticeQueueItem],
        events: [ReviewEvent],
        at date: Date = Date()
    ) -> Int {
        uniqueCatalog(catalog).filter { item in
            guard let progress = progress(for: item.key, events: events) else { return false }
            return progress.nextReviewAt <= date
        }.count
    }

    func threeDayDrafts(
        catalog: [PracticeQueueItem],
        events: [ReviewEvent],
        startingAt start: Date = Date(),
        dailyLimit: Int = Self.defaultDailyLimit
    ) -> [DailyPracticeDraft] {
        var simulatedEvents = events
        return (0..<3).map { offset in
            let day = offset == 0
                ? start
                : startOfDay(start, addingDays: offset).addingTimeInterval(12 * 60 * 60)
            let selected = Array(
                scheduledEntries(catalog: catalog, events: simulatedEvents, at: day)
                    .prefix(max(0, dailyLimit))
            )
            let planned = selected.map { entry in
                PlannedPracticeItem(
                    key: entry.item.key,
                    lessonDay: entry.item.lessonDay,
                    sentence: entry.item.sentence,
                    kind: entry.kind
                )
            }
            for (index, entry) in selected.enumerated() {
                simulatedEvents.append(
                    ReviewEvent(
                        id: forecastEventID(dayOffset: offset, itemOffset: index),
                        phrase: entry.item.key,
                        rating: .easy,
                        reviewedAt: day.addingTimeInterval(Double(index))
                    )
                )
            }
            return DailyPracticeDraft(date: startOfDay(day), items: planned)
        }
    }

    func weeklySummary(
        catalog: [PracticeQueueItem],
        events: [ReviewEvent],
        at date: Date = Date()
    ) -> WeeklySummary {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: startOfDay(date), duration: 7 * 86_400)
        let weeklyEvents = events.filter {
            $0.reviewedAt >= interval.start && $0.reviewedAt < interval.end
        }
        let easyCount = weeklyEvents.filter { $0.rating == .easy }.count
        let againCount = weeklyEvents.filter { $0.rating == .again }.count
        let uniqueDays = Set(weeklyEvents.map { startOfDay($0.reviewedAt) })
        let reviewedKeys = Set(events.map(\.phrase))
        let catalog = uniqueCatalog(catalog)
        return WeeklySummary(
            weekStart: interval.start,
            weekEnd: interval.end,
            reviewCount: weeklyEvents.count,
            easyCount: easyCount,
            againCount: againCount,
            uniquePhraseCount: Set(weeklyEvents.map(\.phrase)).count,
            practiceDayCount: uniqueDays.count,
            easyRate: weeklyEvents.isEmpty
                ? 0
                : Double(easyCount) / Double(weeklyEvents.count),
            dueReviewCount: dueReviewCount(catalog: catalog, events: events, at: date),
            newPhraseCount: catalog.filter { !reviewedKeys.contains($0.key) }.count
        )
    }

    private struct ScheduledEntry {
        let item: PracticeQueueItem
        let kind: PlannedPhraseKind
        let progress: SentenceProgress?
    }

    private func scheduledEntries(
        catalog: [PracticeQueueItem],
        events: [ReviewEvent],
        at date: Date
    ) -> [ScheduledEntry] {
        let entries = uniqueCatalog(catalog).map { item in
            ScheduledEntry(
                item: item,
                kind: progress(for: item.key, events: events) == nil ? .new : .review,
                progress: progress(for: item.key, events: events)
            )
        }
        let due = entries
            .filter { entry in
                guard let progress = entry.progress else { return false }
                return progress.nextReviewAt <= date
            }
            .sorted { lhs, rhs in
                let lhsAgain = lhs.progress?.lastRating == .again
                let rhsAgain = rhs.progress?.lastRating == .again
                if lhsAgain != rhsAgain { return lhsAgain }
                if lhs.progress?.nextReviewAt != rhs.progress?.nextReviewAt {
                    return (lhs.progress?.nextReviewAt ?? .distantFuture)
                        < (rhs.progress?.nextReviewAt ?? .distantFuture)
                }
                return catalogOrder(lhs.item, rhs.item)
            }
        let unseen = entries
            .filter { $0.progress == nil }
            .sorted { catalogOrder($0.item, $1.item) }
        return due + unseen
    }

    private func uniqueCatalog(_ catalog: [PracticeQueueItem]) -> [PracticeQueueItem] {
        var seen = Set<PhraseProgressKey>()
        return catalog.filter { seen.insert($0.key).inserted }
    }

    private func catalogOrder(_ lhs: PracticeQueueItem, _ rhs: PracticeQueueItem) -> Bool {
        if lhs.lessonDay != rhs.lessonDay { return lhs.lessonDay < rhs.lessonDay }
        return lhs.sentence.id < rhs.sentence.id
    }

    private func forecastEventID(dayOffset: Int, itemOffset: Int) -> UUID {
        let tail = String(format: "%012x", dayOffset * 1_000 + itemOffset + 1)
        return UUID(uuidString: "00000000-0000-0000-0000-\(tail)") ?? UUID()
    }
}
