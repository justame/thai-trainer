import AVFoundation
import Foundation
import XCTest
@testable import ThaiTrainer

final class ThaiTrainerTests: XCTestCase {
    private let fixtureContentSHA256 = "23fe57fb79ad049e9732b63f37c255c0a1d9f3c4e90d9203240ab4c85b604970"

    func testEveryReleasedSentenceHasACompleteWordLearningBreakdown() throws {
        let packages = try LessonPackageLoader(bundle: .main).loadAll()
        let sentences = packages.flatMap(\.lesson.sentences)

        XCTAssertEqual(packages.map(\.lesson.day), [1, 2, 3, 4, 5])
        XCTAssertEqual(sentences.count, 100)
        XCTAssertEqual(VocabularyCatalog.wordsBySentenceID.count, 100)
        for sentence in sentences {
            let words = sentence.learningVocabulary
            XCTAssertFalse(words.isEmpty, sentence.id)
            XCTAssertTrue(words.allSatisfy {
                !$0.thai.isEmpty && !$0.romanization.isEmpty && !$0.meaningHebrew.isEmpty
            }, sentence.id)
            XCTAssertEqual(
                words.map(\.thai).joined().replacingOccurrences(of: " ", with: ""),
                sentence.thai.replacingOccurrences(of: " ", with: ""),
                sentence.id
            )
        }
    }

    func testEasyUsesIntervalLadderAndAgainResetsIt() throws {
        let scheduler = ReviewScheduler(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok")))
        let key = phraseKey(sentenceID: "d001-s01")
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-06T04:00:00Z"))
        var events: [ReviewEvent] = []

        events.append(ReviewEvent(phrase: key, rating: .easy, reviewedAt: start))
        var progress = try XCTUnwrap(scheduler.progress(for: key, events: events))
        XCTAssertEqual(progress.easyStreak, 1)
        XCTAssertEqual(progress.nextReviewAt, scheduler.startOfDay(start, addingDays: 1))

        let secondReview = progress.nextReviewAt.addingTimeInterval(60)
        events.append(ReviewEvent(phrase: key, rating: .easy, reviewedAt: secondReview))
        progress = try XCTUnwrap(scheduler.progress(for: key, events: events))
        XCTAssertEqual(progress.easyStreak, 2)
        XCTAssertEqual(progress.nextReviewAt, scheduler.startOfDay(secondReview, addingDays: 3))

        let againAt = progress.nextReviewAt
        events.append(ReviewEvent(phrase: key, rating: .again, reviewedAt: againAt))
        progress = try XCTUnwrap(scheduler.progress(for: key, events: events))
        XCTAssertEqual(progress.easyStreak, 0)
        XCTAssertEqual(progress.againCount, 1)
        XCTAssertEqual(progress.nextReviewAt, againAt.addingTimeInterval(10 * 60))
    }

    func testProgressIdentityIsolatedByRevisionAndContentHash() throws {
        let scheduler = ReviewScheduler()
        let original = phraseKey(sentenceID: "d001-s01")
        let revised = PhraseProgressKey(
            lessonID: original.lessonID,
            revision: original.revision + 1,
            contentSHA256: String(repeating: "b", count: 64),
            sentenceID: original.sentenceID
        )
        let now = Date(timeIntervalSince1970: 1_788_600_000)
        let events = [ReviewEvent(phrase: original, rating: .easy, reviewedAt: now)]

        XCTAssertNotNil(scheduler.progress(for: original, events: events))
        XCTAssertNil(scheduler.progress(for: revised, events: events))
    }

    @MainActor
    func testLearningProgressPersistsImmutableEventsAndFailsSafeOnCorruption() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ThaiEchoProgressTests-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("learning-progress.json")
        defer { try? fileManager.removeItem(at: root) }

        let store = LearningProgressStore(fileURL: file)
        let eventID = UUID()
        let event = try store.record(
            .again,
            for: phraseKey(sentenceID: "d001-s02"),
            at: Date(timeIntervalSince1970: 1_788_600_000),
            id: eventID
        )
        _ = try store.record(
            .again,
            for: event.phrase,
            at: event.reviewedAt,
            id: eventID
        )
        XCTAssertEqual(store.events, [event], "Retrying the same immutable event is idempotent")

        let reloaded = LearningProgressStore(fileURL: file)
        XCTAssertEqual(reloaded.events, [event])
        XCTAssertNil(reloaded.persistenceError)

        try Data("not json".utf8).write(to: file, options: .atomic)
        let corrupted = LearningProgressStore(fileURL: file)
        XCTAssertTrue(corrupted.events.isEmpty)
        XCTAssertNotNil(corrupted.persistenceError)
    }

    func testDueQueuePrioritizesOverdueAcrossLessonsBeforeNewPhrases() throws {
        let scheduler = ReviewScheduler()
        let now = Date(timeIntervalSince1970: 1_788_600_000)
        let dayOne = practiceItem(day: 1, sentenceID: "d001-s01")
        let dayTwo = practiceItem(day: 2, sentenceID: "d002-s01")
        let newDayTwo = practiceItem(day: 2, sentenceID: "d002-s02")
        let events = [
            ReviewEvent(
                phrase: dayTwo.key,
                rating: .again,
                reviewedAt: now.addingTimeInterval(-86_400)
            ),
            ReviewEvent(
                phrase: dayOne.key,
                rating: .easy,
                reviewedAt: now.addingTimeInterval(-4 * 86_400)
            ),
        ]

        let queue = scheduler.sessionQueue(
            catalog: [newDayTwo, dayOne, dayTwo],
            events: events,
            at: now,
            limit: 3
        )

        XCTAssertEqual(queue.map(\.key), [dayTwo.key, dayOne.key, newDayTwo.key])
        XCTAssertEqual(Set(queue.map(\.lessonDay)), [1, 2])
    }

    func testThreeDayDraftIsPureAndSeparatesReviewsFromNewMaterial() throws {
        let scheduler = ReviewScheduler()
        let start = Date(timeIntervalSince1970: 1_788_600_000)
        let catalog = (1...8).map {
            practiceItem(day: $0 <= 4 ? 1 : 2, sentenceID: String(format: "fixture-s%02d", $0))
        }
        let events: [ReviewEvent] = []

        let drafts = scheduler.threeDayDrafts(
            catalog: catalog,
            events: events,
            startingAt: start,
            dailyLimit: 2
        )

        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts.map(\.items.count), [2, 2, 2])
        XCTAssertTrue(drafts[0].items.allSatisfy { $0.kind == .new })
        XCTAssertTrue(drafts[1].items.allSatisfy { $0.kind == .review })
        XCTAssertTrue(drafts[2].items.allSatisfy { $0.kind == .new })
        XCTAssertTrue(events.isEmpty, "Forecasting must never mutate real progress")
    }

    func testWeeklySummaryIsDerivedFromEventsAndCurrentBacklog() throws {
        let scheduler = ReviewScheduler(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Bangkok")))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-06T05:00:00Z"))
        let first = practiceItem(day: 1, sentenceID: "d001-s01")
        let second = practiceItem(day: 2, sentenceID: "d002-s01")
        let unseen = practiceItem(day: 2, sentenceID: "d002-s02")
        let events = [
            ReviewEvent(phrase: first.key, rating: .easy, reviewedAt: now.addingTimeInterval(-2 * 86_400)),
            ReviewEvent(phrase: first.key, rating: .again, reviewedAt: now.addingTimeInterval(-86_400)),
            ReviewEvent(phrase: second.key, rating: .easy, reviewedAt: now),
        ]

        let summary = scheduler.weeklySummary(
            catalog: [first, second, unseen],
            events: events,
            at: now
        )

        XCTAssertEqual(summary.reviewCount, 3)
        XCTAssertEqual(summary.easyCount, 2)
        XCTAssertEqual(summary.againCount, 1)
        XCTAssertEqual(summary.uniquePhraseCount, 2)
        XCTAssertEqual(summary.practiceDayCount, 3)
        XCTAssertEqual(summary.easyRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(summary.newPhraseCount, 1)
        XCTAssertGreaterThanOrEqual(summary.dueReviewCount, 1)
    }

    @MainActor
    func testPracticePlayerAcceptsOneReviewQueueAcrossLessonPackages() {
        let defaultsName = "ThaiTrainerCrossDayQueue-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let player = PracticeSessionPlayer(userDefaults: defaults, resourceRoot: nil)
        let queue = [
            practiceItem(day: 1, sentenceID: "d001-s01"),
            practiceItem(day: 2, sentenceID: "d002-s01"),
        ]

        player.configure(reviewQueue: queue)

        XCTAssertTrue(player.isReviewSession)
        XCTAssertTrue(player.isReady)
        XCTAssertEqual(player.currentQueueItem?.lessonDay, 1)
        player.moveSentence(by: 1)
        XCTAssertEqual(player.currentQueueItem?.lessonDay, 2)
    }

    func testApprovedPracticeBundleContainsExactCoreAndVariationPairsForEverySentence() throws {
        let package = try LessonPackageLoader(bundle: .main).load()
        let clips = try PracticeAudioPackageLoader().load(for: package.lesson)

        XCTAssertEqual(clips.map(\.sentenceID), package.lesson.sentences.map(\.id))
        XCTAssertEqual(clips.count, 20)
        XCTAssertTrue(clips.allSatisfy {
            FileManager.default.fileExists(atPath: $0.hebrewURL.path)
                && FileManager.default.fileExists(atPath: $0.thaiURL.path)
                && $0.variations.count == 1
                && FileManager.default.fileExists(atPath: $0.variations[0].hebrewURL.path)
                && FileManager.default.fileExists(atPath: $0.variations[0].thaiURL.path)
        })
    }

    func testSequenceBuilderUsesConfiguredHebrewDelayRepeatsGapsAndRates() throws {
        let package = try LessonPackageLoader(bundle: .main).load()
        let clip = try XCTUnwrap(
            PracticeAudioPackageLoader().load(for: package.lesson).first
        )
        let configuration = PracticeConfiguration(
            speaksHebrew: true,
            hebrewToThaiDelay: 4.5,
            thaiRepetitions: 2,
            gapBetweenRepetitions: 0.8,
            gapBeforeNextSentence: 3,
            firstThaiRate: 0.82,
            laterThaiRate: 1,
            autoAdvance: true,
            loopsSession: false,
            order: .sequential,
            playsVariations: false
        )

        let steps = PracticeSequenceBuilder.steps(
            for: clip,
            configuration: configuration
        )
        XCTAssertEqual(steps.count, 5)
        XCTAssertEqual(steps[0], .speech(url: clip.hebrewURL, rate: 1, language: .hebrew))
        XCTAssertEqual(steps[1], .pause(seconds: 4.5, kind: .hebrewToThai))
        XCTAssertEqual(
            steps[2],
            .speech(url: clip.thaiURL, rate: 0.82, language: .thai(repetition: 1, total: 2))
        )
        XCTAssertEqual(steps[3], .pause(seconds: 0.8, kind: .betweenRepetitions))
        XCTAssertEqual(
            steps[4],
            .speech(url: clip.thaiURL, rate: 1, language: .thai(repetition: 2, total: 2))
        )
    }

    func testSequencePlaysRelatedVariationAfterCoreWithItsOwnHebrewCue() throws {
        let package = try LessonPackageLoader(bundle: .main).load()
        let clip = try XCTUnwrap(
            PracticeAudioPackageLoader().load(for: package.lesson).first
        )
        let variation = try XCTUnwrap(clip.variations.first)
        let configuration = PracticeConfiguration(
            speaksHebrew: true,
            hebrewToThaiDelay: 2,
            thaiRepetitions: 1,
            gapBetweenRepetitions: 0,
            gapBeforeNextSentence: 3,
            firstThaiRate: 0.82,
            laterThaiRate: 1,
            autoAdvance: true,
            loopsSession: false,
            order: .sequential,
            playsVariations: true,
            gapBeforeVariation: 1.5
        )

        let steps = PracticeSequenceBuilder.steps(
            for: clip,
            configuration: configuration
        )

        XCTAssertEqual(steps.count, 7)
        XCTAssertEqual(steps[2], .speech(
            url: clip.thaiURL,
            rate: 0.82,
            language: .thai(repetition: 1, total: 1)
        ))
        XCTAssertEqual(steps[3], .pause(seconds: 1.5, kind: .beforeVariation))
        XCTAssertEqual(steps[4], .speech(
            url: variation.hebrewURL,
            rate: 1,
            language: .variationHebrew(index: 1, total: 1)
        ))
        XCTAssertEqual(steps[5], .pause(seconds: 2, kind: .variationHebrewToThai))
        XCTAssertEqual(steps[6], .speech(
            url: variation.thaiURL,
            rate: 1,
            language: .variationThai(index: 1, total: 1)
        ))
    }

    func testConfiguredPauseProducesPlayableBackgroundSilence() throws {
        let data = try PracticeSilenceAudio.wavData(duration: 1.25)

        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data.dropFirst(8).prefix(4), as: UTF8.self), "WAVE")
        XCTAssertEqual(data.count, 44 + (24_000 * 2 * 5 / 4))
        XCTAssertTrue(data.dropFirst(44).allSatisfy { $0 == 0 })

        let player = try AVAudioPlayer(
            data: data,
            fileTypeHint: AVFileType.wav.rawValue
        )
        XCTAssertTrue(player.prepareToPlay())
        XCTAssertEqual(player.duration, 1.25, accuracy: 0.01)
        XCTAssertEqual(player.format.sampleRate, 24_000)
        XCTAssertEqual(player.format.channelCount, 1)
    }

    func testAppDeclaresBackgroundAudioMode() throws {
        let modes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        )
        XCTAssertTrue(modes.contains("audio"))
    }

    func testNowPlayingPresentationUsesPhraseModePhaseAndQueuePosition() throws {
        let package = try LessonPackageLoader(bundle: .main).load()
        let sentence = try XCTUnwrap(package.lesson.sentences.first)
        let presentation = NowPlayingPresentation.practice(
            sentence: sentence,
            day: package.lesson.day,
            mode: .listening,
            phase: .waitingForThai,
            sentenceIndex: 2,
            sentenceCount: package.lesson.sentences.count,
            elapsedTime: 1.25,
            duration: 4,
            isPlaying: true
        )

        XCTAssertEqual(presentation.title, sentence.thai)
        XCTAssertEqual(presentation.artist, "Thai Echo · Day 1 · Listening")
        XCTAssertEqual(presentation.album, "Your turn · Phrase 3 of 20")
        XCTAssertEqual(presentation.queueIndex, 2)
        XCTAssertEqual(presentation.queueCount, 20)
        XCTAssertEqual(presentation.elapsedTime, 1.25)
        XCTAssertEqual(presentation.duration, 4)
        XCTAssertTrue(presentation.isPlaying)
    }

    @MainActor
    func testPracticeSettingsPersistSeparatelyPerModeAndClampUnsafeValues() {
        let suiteName = "ThaiTrainerTests-PracticeSettings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let player = PracticeSessionPlayer(
            userDefaults: defaults,
            resourceRoot: Bundle.main.resourceURL
        )
        player.update(\.hebrewToThaiDelay, to: 7.5)
        player.selectTrack(.recall)
        player.update(\.hebrewToThaiDelay, to: 99)

        XCTAssertEqual(player.configuration.hebrewToThaiDelay, 10)
        player.selectTrack(.listening)
        XCTAssertEqual(player.configuration.hebrewToThaiDelay, 7.5)

        let reloaded = PracticeSessionPlayer(
            userDefaults: defaults,
            resourceRoot: Bundle.main.resourceURL
        )
        XCTAssertEqual(reloaded.configuration.hebrewToThaiDelay, 7.5)
        reloaded.selectTrack(.recall)
        XCTAssertEqual(reloaded.configuration.hebrewToThaiDelay, 10)
    }

    @MainActor
    func testExistingSavedPresetMigratesToVariationDefaults() throws {
        let suiteName = "ThaiTrainerTests-PracticeMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy: [String: Any] = [
            "listening": [
                "speaksHebrew": true,
                "hebrewToThaiDelay": 6.5,
                "thaiRepetitions": 2,
                "gapBetweenRepetitions": 1.2,
                "gapBeforeNextSentence": 2.8,
                "firstThaiRate": 0.82,
                "laterThaiRate": 1.0,
                "autoAdvance": true,
                "loopsSession": false,
                "order": "sequential",
            ],
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: legacy),
            forKey: "thai-trainer.practice-configurations.v1"
        )

        let player = PracticeSessionPlayer(
            userDefaults: defaults,
            resourceRoot: Bundle.main.resourceURL
        )

        XCTAssertEqual(player.configuration.hebrewToThaiDelay, 6.5)
        XCTAssertTrue(player.configuration.playsVariations)
        XCTAssertEqual(player.configuration.gapBeforeVariation, 1.5)
    }

    func testBundledDayOneLoadsTwentyRealItemsWithGeneratedAudio() throws {
        let package = try LessonPackageLoader(bundle: .main).load()

        XCTAssertEqual(package.lesson.lessonID, "day-001")
        XCTAssertEqual(package.lesson.revision, 5)
        XCTAssertEqual(package.lesson.sentences.count, 20)
        XCTAssertEqual(Set(package.lesson.sentences.map(\.id)).count, 20)
        XCTAssertTrue(package.lesson.sentences.allSatisfy {
            !$0.id.isEmpty
                && !$0.promptHebrew.isEmpty
                && !$0.thai.isEmpty
                && !$0.romanization.isEmpty
        })
        XCTAssertEqual(package.lesson.sentences.first?.id, "d001-s01")
        XCTAssertEqual(package.lesson.sentences.last?.id, "d001-s20")
        XCTAssertEqual(package.lesson.sentences.first?.thai, "ช่วยพูดอีกทีได้ไหมครับ")

        let bundledLessonURL = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent(LessonPackageLoader.lessonRelativePath)
        XCTAssertEqual(
            try PublisherContentIntegrity.sha256(
                forLessonData: Data(contentsOf: bundledLessonURL)
            ),
            "2ee17250cd9ca59e8218e62fcb1b8c6b3e80aed406aa7ddfe58a83100df1138c"
        )

        guard case let .ready(tracks) = package.audioState else {
            return XCTFail("The bundled approved Day 1 pack must include all four generated tracks.")
        }
        XCTAssertEqual(tracks.map(\.id), PracticeTrack.allCases.map(\.id))
        XCTAssertTrue(tracks.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
    }

    func testRemotePackDownloadsConfigurablePracticeAudioIntoItsOwnLessonRoot() async throws {
        let fileManager = FileManager.default
        let cacheRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ThaiTrainerPracticeRemoteTests-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: cacheRoot) }

        let resourceRoot = try XCTUnwrap(Bundle.main.resourceURL)
        let lessonData = try Data(
            contentsOf: resourceRoot.appendingPathComponent("days/day-001.json")
        )
        let lesson = try JSONDecoder().decode(Lesson.self, from: lessonData)
        let contentSHA256 = try PublisherContentIntegrity.sha256(forLessonData: lessonData)
        let generatedDirectory = resourceRoot
            .appendingPathComponent("generated/day-001/r5", isDirectory: true)
        let audioManifestData = try Data(
            contentsOf: generatedDirectory.appendingPathComponent("audio-manifest.json")
        )
        let audioManifest = try JSONDecoder().decode(AudioManifest.self, from: audioManifestData)
        let practiceDirectory = resourceRoot
            .appendingPathComponent("practice/day-001/r5", isDirectory: true)
        let practiceManifestData = try Data(
            contentsOf: practiceDirectory.appendingPathComponent("practice-manifest.json")
        )
        let practiceManifest = try JSONDecoder().decode(
            PracticeAudioManifest.self,
            from: practiceManifestData
        )

        let packBase = "/thai/packs/day-001/r5"
        var responses: [String: Data] = [
            "/thai/latest.json": try encodedJSON([
                "schema_version": 1,
                "lesson_id": "day-001",
                "revision": 5,
                "content_sha256": contentSHA256,
                "lesson_path": "packs/day-001/r5/lesson.json",
                "audio_manifest_path": "packs/day-001/r5/audio-manifest.json",
                "practice_manifest_path": "packs/day-001/r5/practice/practice-manifest.json",
            ]),
            "\(packBase)/lesson.json": lessonData,
            "\(packBase)/audio-manifest.json": audioManifestData,
            "\(packBase)/practice/practice-manifest.json": practiceManifestData,
        ]
        for track in audioManifest.tracks {
            responses["\(packBase)/\(track.file)"] = try Data(
                contentsOf: generatedDirectory.appendingPathComponent(track.file)
            )
        }
        let practiceClips = practiceManifest.sentences.flatMap { sentence in
            [sentence.core.hebrew, sentence.core.thai]
                + sentence.variations.flatMap { [$0.hebrew, $0.thai] }
        }
        for clip in practiceClips {
            responses["\(packBase)/practice/\(clip.file)"] = try Data(
                contentsOf: practiceDirectory.appendingPathComponent(clip.file)
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        StubURLProtocol.configure(responses: responses)
        let repository = RemoteContentRepository(session: session, cacheRoot: cacheRoot)

        let package = try await repository.refresh(from: "https://content.example/thai")
        let downloadedPractice = try PracticeAudioPackageLoader(
            resourceRoot: package.resourceRootURL
        ).load(for: lesson)

        XCTAssertEqual(downloadedPractice.count, 20)
        XCTAssertTrue(downloadedPractice.allSatisfy { $0.variations.count == 1 })
        XCTAssertEqual(
            StubURLProtocol.recordedRequests().filter { $0.url?.pathExtension == "wav" }.count,
            80
        )
    }

    func testPublisherContentHashMatchesCanonicalPythonFixture() throws {
        let lessonData = try encodedJSON(makeLessonObject())

        XCTAssertEqual(
            try PublisherContentIntegrity.sha256(forLessonData: lessonData),
            fixtureContentSHA256
        )
        XCTAssertTrue(PublisherContentIntegrity.isValidSHA256(fixtureContentSHA256))
        XCTAssertFalse(PublisherContentIntegrity.isValidSHA256(fixtureContentSHA256.uppercased()))
        XCTAssertFalse(PublisherContentIntegrity.isValidSHA256("fixture"))
    }

    @MainActor
    func testFirstLoadKeepsBundledLessonAndAttemptsDefaultRefreshOnce() async throws {
        XCTAssertEqual(
            RemoteContentRepository.defaultBaseURLString,
            "https://justame.github.io/thai-trainer/"
        )

        let fileManager = FileManager.default
        let cacheRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ThaiTrainerStartupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: cacheRoot) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = RemoteContentRepository(session: session, cacheRoot: cacheRoot)
        let latestPath = "/thai-trainer/latest.json"
        StubURLProtocol.configure(
            responses: [latestPath: Data("Not Found".utf8)],
            statusCodes: [latestPath: 404]
        )
        let defaultsName = "ThaiTrainerStartupDefaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let store = LessonStore(
            loader: LessonPackageLoader(bundle: .main),
            remoteRepository: repository,
            userDefaults: defaults
        )
        store.loadIfNeeded()

        XCTAssertEqual(store.contentSource, .bundled)
        guard case let .loaded(initialPackage) = store.state else {
            return XCTFail("Bundled content must be visible before the network refresh starts.")
        }
        XCTAssertEqual(initialPackage.lesson.lessonID, "day-005")

        await store.refreshAutomaticallyIfNeeded()

        guard case let .loaded(packageAfterRefresh) = store.state else {
            return XCTFail("A missing published index must not hide bundled content.")
        }
        XCTAssertEqual(packageAfterRefresh.lesson.lessonID, "day-005")
        XCTAssertEqual(store.contentSource, .bundled)
        XCTAssertEqual(store.refreshState, .unavailable("No published update yet."))
        XCTAssertEqual(
            StubURLProtocol.recordedRequests().map(\.url?.absoluteString),
            ["https://justame.github.io/thai-trainer/latest.json"]
        )

        await store.refreshAutomaticallyIfNeeded()
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 1)

        await store.refresh()
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 2)
        guard case .loaded = store.state else {
            return XCTFail("A failed manual refresh must also keep the bundled lesson visible.")
        }
    }

    func testRemoteIntegrityCacheAtomicityAndFallback() async throws {
        let fileManager = FileManager.default
        let cacheRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ThaiTrainerRemoteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: cacheRoot) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = RemoteContentRepository(session: session, cacheRoot: cacheRoot)

        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let staleStagingURL = cacheRoot.appendingPathComponent(".staging-stale", isDirectory: true)
        let stagingLinkTarget = cacheRoot.appendingPathComponent("keep-staging-link-target", isDirectory: true)
        let stagingLinkURL = cacheRoot.appendingPathComponent(".staging-link", isDirectory: true)
        try fileManager.createDirectory(at: staleStagingURL, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: stagingLinkTarget, withIntermediateDirectories: false)
        try fileManager.createSymbolicLink(at: stagingLinkURL, withDestinationURL: stagingLinkTarget)

        let trackData = Dictionary(uniqueKeysWithValues: PracticeTrack.allCases.map { track in
            (track.rawValue, Data("repository-fixture-\(track.rawValue)".utf8))
        })
        let validResponses = try makeResponses(trackData: trackData)
        StubURLProtocol.configure(responses: validResponses)

        let firstPackage = try await repository.refresh(from: "https://content.example/thai")
        XCTAssertEqual(firstPackage.lesson.lessonID, "day-001")
        XCTAssertEqual(firstPackage.lesson.revision, 2)
        XCTAssertEqual(firstPackage.lesson.sentences.count, 20)
        XCTAssertEqual(
            firstPackage.audioState.playableTracks.map(\.id),
            PracticeTrack.allCases.map(\.rawValue)
        )
        XCTAssertTrue(firstPackage.audioState.playableTracks.allSatisfy {
            fileManager.fileExists(atPath: $0.fileURL.path) && $0.fileURL.path.hasPrefix(cacheRoot.path)
        })
        XCTAssertFalse(fileManager.fileExists(atPath: staleStagingURL.path))
        XCTAssertEqual(
            try fileManager.destinationOfSymbolicLink(atPath: stagingLinkURL.path),
            stagingLinkTarget.path
        )

        let latestRequests = StubURLProtocol.recordedRequests().filter {
            $0.url?.lastPathComponent == "latest.json"
        }
        XCTAssertEqual(latestRequests.count, 1)
        XCTAssertEqual(latestRequests.first?.cachePolicy, .reloadIgnoringLocalCacheData)

        let packsURL = cacheRoot.appendingPathComponent("packs", isDirectory: true)
        let firstPackDirectories = try packDirectoryNames(at: packsURL)
        XCTAssertEqual(firstPackDirectories.count, 1)

        StubURLProtocol.configure(responses: validResponses)
        let secondPackage = try await repository.refresh(from: "https://content.example/thai")
        XCTAssertEqual(secondPackage.audioState.playableTracks.count, 4)
        let secondPackDirectories = try packDirectoryNames(at: packsURL)
        XCTAssertEqual(secondPackDirectories.count, 1)
        XCTAssertEqual(secondPackDirectories, firstPackDirectories)

        var dayTwoObject = makeLessonObject()
        dayTwoObject["lesson_id"] = "day-002"
        dayTwoObject["revision"] = 1
        dayTwoObject["day"] = 2
        dayTwoObject["theme"] = "Getting around Bangkok"
        let dayTwoResponses = try makeResponses(
            trackData: trackData,
            lessonObject: dayTwoObject
        )
        StubURLProtocol.configure(responses: dayTwoResponses)
        let dayTwoPackage = try await repository.refresh(from: "https://content.example/thai")
        XCTAssertEqual(dayTwoPackage.lesson.lessonID, "day-002")
        XCTAssertEqual(Set(repository.loadCachedPackages().map(\.lesson.lessonID)), ["day-001", "day-002"])
        XCTAssertEqual(try packDirectoryNames(at: packsURL).count, 2)

        let defaultsName = "ThaiTrainerLibraryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        await MainActor.run {
            let store = LessonStore(
                loader: LessonPackageLoader(bundle: .main),
                remoteRepository: repository,
                userDefaults: defaults
            )
            store.loadIfNeeded()
            XCTAssertEqual(store.library.map(\.package.lesson.day), [1, 2, 3, 4, 5])
            XCTAssertEqual(store.selectedLessonID, "day-005")
            store.selectLesson(id: "day-001")
            XCTAssertEqual(store.selectedLessonID, "day-001")

            let restoredStore = LessonStore(
                loader: LessonPackageLoader(bundle: .main),
                remoteRepository: repository,
                userDefaults: defaults
            )
            restoredStore.loadIfNeeded()
            XCTAssertEqual(restoredStore.selectedLessonID, "day-001")
        }

        let pointerURL = cacheRoot.appendingPathComponent("current.json", isDirectory: false)
        let currentPointer = try Data(contentsOf: pointerURL)
        let currentPackDirectories = try packDirectoryNames(at: packsURL)

        typealias Corruption = (label: String, mutate: (inout [String: Data]) throws -> Void)
        let corruptions: [Corruption] = [
            ("latest missing required hash", { responses in
                try self.mutateJSON(in: &responses, path: "/thai/latest.json") {
                    $0.removeValue(forKey: "content_sha256")
                }
            }),
            ("latest hash has invalid format", { responses in
                try self.mutateJSON(in: &responses, path: "/thai/latest.json") {
                    $0["content_sha256"] = self.fixtureContentSHA256.uppercased()
                }
            }),
            ("latest hash does not match lesson", { responses in
                try self.mutateJSON(in: &responses, path: "/thai/latest.json") {
                    $0["content_sha256"] = String(repeating: "0", count: 64)
                }
            }),
            ("manifest missing required hash", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) {
                    $0.removeValue(forKey: "content_sha256")
                }
            }),
            ("manifest hash mismatch", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) {
                    $0["content_sha256"] = String(repeating: "0", count: 64)
                }
            }),
            ("track missing required hash", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) { object in
                    var tracks = object["tracks"] as! [[String: Any]]
                    tracks[0].removeValue(forKey: "content_sha256")
                    object["tracks"] = tracks
                }
            }),
            ("track hash mismatch", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) { object in
                    var tracks = object["tracks"] as! [[String: Any]]
                    tracks[0]["content_sha256"] = String(repeating: "0", count: 64)
                    object["tracks"] = tracks
                }
            }),
            ("sentence romanization is empty", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/lesson.json"
                ) { object in
                    var sentences = object["sentences"] as! [[String: Any]]
                    sentences[0]["romanization"] = "  "
                    object["sentences"] = sentences
                }
            }),
            ("track byte count mismatch", { responses in
                responses["/thai/packs/day-001/r2/scenario.mp3"] = Data("wrong-size".utf8)
            }),
        ]

        for corruption in corruptions {
            var responses = validResponses
            try corruption.mutate(&responses)
            StubURLProtocol.configure(responses: responses)

            do {
                _ = try await repository.refresh(from: "https://content.example/thai")
                XCTFail("\(corruption.label) must be rejected")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty, corruption.label)
            }

            XCTAssertEqual(try Data(contentsOf: pointerURL), currentPointer, corruption.label)
            XCTAssertEqual(
                try packDirectoryNames(at: packsURL),
                currentPackDirectories,
                corruption.label
            )
            XCTAssertEqual(
                try repository.loadCachedPackage().audioState.playableTracks.count,
                4,
                corruption.label
            )
        }

        let cachedPackage = try repository.loadCachedPackage()
        let cachedTrack = try XCTUnwrap(cachedPackage.audioState.playableTracks.first)
        let revisionDirectory = cachedTrack.fileURL.deletingLastPathComponent()
        let manifestURL = revisionDirectory.appendingPathComponent(
            LessonPackageLoader.manifestFilename,
            isDirectory: false
        )
        let savedManifest = try Data(contentsOf: manifestURL)

        try fileManager.removeItem(at: manifestURL)
        XCTAssertThrowsError(try repository.loadCachedPackage())
        try savedManifest.write(to: manifestURL, options: .atomic)

        try fileManager.removeItem(at: cachedTrack.fileURL)
        XCTAssertThrowsError(try repository.loadCachedPackage())

        await MainActor.run {
            let store = LessonStore(
                loader: LessonPackageLoader(bundle: .main),
                remoteRepository: repository,
                userDefaults: defaults
            )
            store.loadIfNeeded()
            XCTAssertEqual(store.contentSource, .bundled)
            guard case let .loaded(package) = store.state else {
                return XCTFail("An invalid cache must fall back to the bundled lesson.")
            }
            XCTAssertEqual(package.lesson.lessonID, "day-001")
            XCTAssertEqual(package.lesson.sentences.count, 20)
        }
    }

    private func makeResponses(
        trackData: [String: Data],
        lessonObject: [String: Any]? = nil
    ) throws -> [String: Data] {
        let lessonObject = lessonObject ?? makeLessonObject()
        let lessonID = try XCTUnwrap(lessonObject["lesson_id"] as? String)
        let revision = try XCTUnwrap(lessonObject["revision"] as? Int)
        let lessonData = try encodedJSON(lessonObject)
        let contentSHA256 = try PublisherContentIntegrity.sha256(forLessonData: lessonData)
        let manifestTracks: [[String: Any]] = PracticeTrack.allCases.map { track in
            [
                "lesson_id": lessonID,
                "revision": revision,
                "track_id": track.rawValue,
                "file": "\(track.rawValue).mp3",
                "bytes": trackData[track.rawValue]!.count,
                "content_sha256": contentSHA256,
            ]
        }
        let manifest: [String: Any] = [
            "schema_version": 1,
            "lesson_id": lessonID,
            "revision": revision,
            "content_sha256": contentSHA256,
            "tracks": manifestTracks,
        ]
        let packBase = "packs/\(lessonID)/r\(revision)"
        let latest: [String: Any] = [
            "schema_version": 1,
            "lesson_id": lessonID,
            "revision": revision,
            "content_sha256": contentSHA256,
            "lesson_path": "\(packBase)/lesson.json",
            "audio_manifest_path": "\(packBase)/audio-manifest.json",
        ]

        var responses: [String: Data] = [
            "/thai/latest.json": try encodedJSON(latest),
            "/thai/\(packBase)/lesson.json": lessonData,
            "/thai/\(packBase)/audio-manifest.json": try encodedJSON(manifest),
        ]
        for (trackID, data) in trackData {
            responses["/thai/\(packBase)/\(trackID).mp3"] = data
        }
        return responses
    }

    private func makeLessonObject() -> [String: Any] {
        let sentenceIDs = (1...20).map { String(format: "fixture-s%02d", $0) }
        let sentences: [[String: Any]] = sentenceIDs.enumerated().map { offset, sentenceID in
            [
                "id": sentenceID,
                "prompt_he": "Prompt \(offset + 1)",
                "thai": "ไทย \(offset + 1)",
                "romanization": "thai \(offset + 1)",
                "variation": [
                    "prompt_he": "Related prompt \(offset + 1)",
                    "thai": "ไทยแบบอื่น \(offset + 1)",
                ],
                "review_status": "approved",
            ]
        }
        let tracks: [[String: Any]] = PracticeTrack.allCases.map { track in
            ["id": track.rawValue, "sequence": sentenceIDs]
        }
        return [
            "schema_version": 1,
            "lesson_id": "day-001",
            "revision": 2,
            "day": 1,
            "theme": "Remote fixture",
            "status": "approved",
            "voices": [
                "provider": "azure_speech",
                "thai": "th-TH-PremwadeeNeural",
                "hebrew": "he-IL-HilaNeural",
            ],
            "sentences": sentences,
            "audio_program": [
                "normal_speed_only": true,
                "tracks": tracks,
            ],
        ]
    }

    private func encodedJSON(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func mutateJSON(
        in responses: inout [String: Data],
        path: String,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        let data = try XCTUnwrap(responses[path])
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        mutation(&object)
        responses[path] = try encodedJSON(object)
    }

    private func packDirectoryNames(at packsURL: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: packsURL.path))
    }

    private func phraseKey(sentenceID: String) -> PhraseProgressKey {
        PhraseProgressKey(
            lessonID: "day-001",
            revision: 5,
            contentSHA256: String(repeating: "a", count: 64),
            sentenceID: sentenceID
        )
    }

    private func practiceItem(day: Int, sentenceID: String) -> PracticeQueueItem {
        let lessonID = String(format: "day-%03d", day)
        let revision = 1
        let key = PhraseProgressKey(
            lessonID: lessonID,
            revision: revision,
            contentSHA256: String(repeating: Character(String(day % 10)), count: 64),
            sentenceID: sentenceID
        )
        let sentence = LessonSentence(
            id: sentenceID,
            promptHebrew: "Prompt \(sentenceID)",
            thai: "ไทย \(sentenceID)",
            romanization: "thai \(sentenceID)",
            variation: LessonSentenceVariation(
                promptHebrew: "Related \(sentenceID)",
                thai: "ไทยอีกแบบ \(sentenceID)"
            ),
            reviewStatus: "approved"
        )
        let base = FileManager.default.temporaryDirectory
        return PracticeQueueItem(
            key: key,
            lessonDay: day,
            lessonTheme: "Day \(day)",
            sentence: sentence,
            audio: PracticeSentenceAudio(
                sentenceID: sentenceID,
                core: PracticeAudioPair(
                    hebrewURL: base.appendingPathComponent("\(sentenceID)-he.wav"),
                    thaiURL: base.appendingPathComponent("\(sentenceID)-th.wav")
                ),
                variations: []
            )
        )
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseData: [String: Data] = [:]
    private static var responseStatusCodes: [String: Int] = [:]
    private static var requests: [URLRequest] = []

    static func configure(
        responses: [String: Data],
        statusCodes: [String: Int] = [:]
    ) {
        lock.lock()
        responseData = responses
        responseStatusCodes = statusCodes
        requests = []
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let path = request.url?.path
        let data = path.flatMap { Self.responseData[$0] }
        let statusCode = path.flatMap { Self.responseStatusCodes[$0] } ?? 200
        Self.lock.unlock()

        guard let url = request.url,
              let data,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
