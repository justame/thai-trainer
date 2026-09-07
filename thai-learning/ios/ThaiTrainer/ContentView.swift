import SwiftUI

struct TrainerView: View {
    @ObservedObject var lessonStore: LessonStore
    @ObservedObject var practicePlayer: PracticeSessionPlayer
    @ObservedObject var learningProgress: LearningProgressStore

    @State private var showsSettings = false
    @State private var showsLessonLibrary = false
    @State private var showsProgress = false
    @State private var feedbackMessage: String?
    @State private var settingsDetent: PresentationDetent = .large
    @State private var vocabularyExpanded = true

    private let scheduler = ReviewScheduler()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch lessonStore.state {
                        case .loading:
                            ProgressView("Loading lesson…")
                                .frame(maxWidth: .infinity, minHeight: 420)
                        case let .failed(message):
                            ContentUnavailableView(
                                "Lesson unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(message)
                            )
                            .frame(minHeight: 420)
                        case let .loaded(package):
                            lessonContent(package)
                                .task(
                                    id: "\(package.lesson.lessonID)-r\(package.lesson.revision)-"
                                        + package.contentSHA256
                                        + package.resourceRootURL.standardizedFileURL.path
                                ) {
                                    practicePlayer.configure(for: package)
                                    #if DEBUG
                                    if ProcessInfo.processInfo.arguments.contains("--screenshot-sentences") {
                                        try? await Task.sleep(for: .milliseconds(250))
                                        proxy.scrollTo("sentences-section", anchor: .top)
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--screenshot-settings") {
                                        try? await Task.sleep(for: .milliseconds(350))
                                        showsSettings = true
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--screenshot-library") {
                                        try? await Task.sleep(for: .milliseconds(350))
                                        showsLessonLibrary = true
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--autoplay-practice") {
                                        try? await Task.sleep(for: .milliseconds(250))
                                        practicePlayer.selectSentence(0, play: true)
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--screenshot-adaptive") {
                                        startAdaptiveSession()
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--screenshot-learning")
                                        || ProcessInfo.processInfo.arguments.contains("--screenshot-adaptive") {
                                        try? await Task.sleep(for: .milliseconds(350))
                                        proxy.scrollTo("word-learning-section", anchor: .top)
                                    }
                                    #endif
                                }
                                .sheet(isPresented: $showsSettings) {
                                    PracticeSettingsSheet(
                                        lessonStore: lessonStore,
                                        practicePlayer: practicePlayer,
                                        package: package
                                    )
                                    .presentationDetents(
                                        [.medium, .large],
                                        selection: $settingsDetent
                                    )
                                    .presentationDragIndicator(.visible)
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(currentNavigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsLessonLibrary = true
                        } label: {
                            Label("Lessons", systemImage: "books.vertical")
                        }
                        .accessibilityHint("Choose a saved lesson day")
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showsProgress = true
                        } label: {
                            Image(systemName: "chart.bar.xaxis")
                        }
                        .accessibilityLabel("Adaptive plan and weekly summary")

                        Button {
                            settingsDetent = .large
                            showsSettings = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("Practice settings")
                    }
                }
                .task {
                    lessonStore.loadIfNeeded()
                    await lessonStore.refreshAutomaticallyIfNeeded()
                }
                .sheet(isPresented: $showsLessonLibrary) {
                    LessonLibrarySheet(lessonStore: lessonStore)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $showsProgress) {
                    AdaptiveProgressSheet(
                        learningProgress: learningProgress,
                        catalog: lessonStore.reviewCatalog,
                        scheduler: scheduler
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private var currentNavigationTitle: String {
        if practicePlayer.isReviewSession { return "Review mix" }
        guard case let .loaded(package) = lessonStore.state else { return "Thai Trainer" }
        return "Day \(package.lesson.day)"
    }

    private func lessonContent(_ package: LessonPackage) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sessionHeader(package)
            adaptiveSessionCard
            practiceModePicker
            phraseFocus(package.lesson)
            vocabularySection
            progressAndTransport
            if practicePlayer.isReviewSession, practicePlayer.currentQueueItem != nil {
                feedbackControls
            }
            quickSettings

            if let error = practicePlayer.playbackError ?? practicePlayer.availabilityError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 2)
            }

            phraseQueue
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var vocabularySection: some View {
        if let sentence = practicePlayer.currentQueueItem?.sentence {
            let words = sentence.learningVocabulary
            DisclosureGroup(isExpanded: $vocabularyExpanded) {
                VStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.element.id) { offset, word in
                        if offset > 0 {
                            Divider()
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(word.thai)
                                    .font(.body.bold())
                                Text(word.romanization)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(word.meaningHebrew)
                                .font(.subheadline.weight(.medium))
                                .multilineTextAlignment(.trailing)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                        .padding(.vertical, 9)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Words in this phrase", systemImage: "character.book.closed")
                            .font(.headline)
                        Text(sentence.thai)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("\(words.count)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .id("word-learning-section")
            .accessibilityHint("Shows each Thai word with pronunciation and Hebrew meaning")
        }
    }

    private func sessionHeader(_ package: LessonPackage) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                showsLessonLibrary = true
            } label: {
                HStack(spacing: 5) {
                    Text("DAY \(package.lesson.day)")
                    if let position = lessonStore.selectedLessonPosition {
                        Text("· \(position) OF \(lessonStore.library.count)")
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                "Day \(package.lesson.day), lesson \(lessonStore.selectedLessonPosition ?? 1) "
                + "of \(lessonStore.library.count)"
            )
            .accessibilityHint("Opens the lesson library")

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Everyday Thai")
                    .font(.title2.bold())
                Spacer(minLength: 8)
                readinessLabel(package)
            }
            Text(package.lesson.theme)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func readinessLabel(_ package: LessonPackage) -> some View {
        if lessonStore.refreshState.isRefreshing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Updating")
            }
            .foregroundStyle(.secondary)
        } else if practicePlayer.isReady {
            Label("Offline ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if case .invalid = package.audioState {
            Label("Audio issue", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        } else {
            Label("Preparing", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }

    private var adaptiveSessionCard: some View {
        let summary = scheduler.weeklySummary(
            catalog: lessonStore.reviewCatalog,
            events: learningProgress.events
        )
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ADAPTIVE PRACTICE")
                    .font(.caption2.bold())
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text("\(summary.dueReviewCount) due · \(summary.newPhraseCount) new")
                    .font(.headline)
                Text("Reviews come first, then new phrases.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(practicePlayer.isReviewSession ? "Refresh mix" : "Start mix") {
                startAdaptiveSession()
            }
            .buttonStyle(.borderedProminent)
            .disabled(lessonStore.reviewCatalog.isEmpty)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var practiceModePicker: some View {
        Picker(
            "Practice mode",
            selection: Binding(
                get: { practicePlayer.activeTrack },
                set: { practicePlayer.selectTrack($0) }
            )
        ) {
            ForEach(PracticeTrack.allCases) { track in
                Text(track.shortTitle).tag(track)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("Changes the saved timing preset used for playback")
    }

    @ViewBuilder
    private func phraseFocus(_ lesson: Lesson) -> some View {
        if let item = practicePlayer.currentQueueItem {
            let sentence = item.sentence
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("HEBREW PROMPT")
                        .font(.caption2.bold())
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    if practicePlayer.isReviewSession {
                        Text("DAY \(item.lessonDay)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(
                        "\(practicePlayer.selectedSentenceIndex + 1) "
                        + "of \(practicePlayer.queueItems.count)"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                }

                Text(sentence.promptHebrew)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .accessibilityLabel("Hebrew prompt: \(sentence.promptHebrew)")

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    Text(sentence.thai)
                        .font(.title2.bold())
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Thai phrase: \(sentence.thai)")
                    Text(sentence.romanization)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("RELATED VERSION", systemImage: "arrow.triangle.branch")
                            .font(.caption2.bold())
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(practicePlayer.configuration.playsVariations ? "Plays next" : "Audio off")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                practicePlayer.configuration.playsVariations
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                    }
                    Text(sentence.variation.promptHebrew)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                        .accessibilityLabel(
                            "Related Hebrew cue: \(sentence.variation.promptHebrew)"
                        )
                    Text(sentence.variation.thai)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel(
                            "Related Thai version: \(sentence.variation.thai)"
                        )
                }
            }
            .padding(18)
            .background(Color.accentColor.opacity(0.085), in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.accentColor.opacity(0.14), lineWidth: 1)
            }
        } else if practicePlayer.isReviewSession {
            ContentUnavailableView(
                "Practice complete",
                systemImage: "checkmark.circle",
                description: Text("Your feedback is saved on this iPhone.")
            )
            .frame(minHeight: 220)
        } else if let sentence = lesson.sentences.first {
            Text(sentence.thai)
                .font(.title2.bold())
        }
    }

    private var progressAndTransport: some View {
        VStack(spacing: 8) {
            ProgressView(
                value: practicePlayer.duration > 0 ? practicePlayer.currentTime : 0,
                total: max(practicePlayer.duration, 1)
            )
            .tint(.accentColor)

            HStack {
                Text(practicePlayer.phase.label)
                Spacer()
                if practicePlayer.duration > 0 {
                    Text(
                        "\(format(practicePlayer.currentTime)) / "
                        + format(practicePlayer.duration)
                    )
                    .monospacedDigit()
                } else {
                    Text("Tap play")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 32) {
                Button {
                    practicePlayer.moveSentence(by: -1)
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(practicePlayer.selectedSentenceIndex == 0)
                .accessibilityLabel("Previous phrase")

                Button {
                    practicePlayer.togglePlayPause()
                } label: {
                    Image(
                        systemName: practicePlayer.isPlaying
                            ? "pause.circle.fill"
                            : "play.circle.fill"
                    )
                    .font(.system(size: 62))
                    .symbolRenderingMode(.hierarchical)
                }
                .disabled(!practicePlayer.isReady)
                .accessibilityLabel(practicePlayer.isPlaying ? "Pause practice" : "Play practice")

                Button {
                    practicePlayer.moveSentence(by: 1)
                } label: {
                    Image(systemName: "forward.end.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(!practicePlayer.isReady)
                .accessibilityLabel("Next phrase")
            }
            .buttonStyle(.plain)
        }
    }

    private var feedbackControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button {
                    recordFeedback(.again)
                } label: {
                    Label("Again", systemImage: FeedbackRating.again.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityHint("Saves feedback and puts this phrase later in the queue")

                Button {
                    recordFeedback(.easy)
                } label: {
                    Label("Easy", systemImage: FeedbackRating.easy.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityHint("Saves feedback and schedules a spaced review")
            }
            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var quickSettings: some View {
        HStack(spacing: 8) {
            quickSetting(
                title: "Hebrew → Thai",
                value: seconds(practicePlayer.configuration.hebrewToThaiDelay)
            )
            quickSetting(
                title: "Main / related",
                value: "\(practicePlayer.configuration.thaiRepetitions)× / "
                    + (practicePlayer.configuration.playsVariations ? "1×" : "off")
            )
            quickSetting(
                title: "First speed",
                value: rate(practicePlayer.configuration.firstThaiRate)
            )
        }
    }

    private func quickSetting(title: String, value: String) -> some View {
        Button {
            settingsDetent = .large
            showsSettings = true
        } label: {
            VStack(spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(.tint)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 4)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value). Open practice settings")
    }

    private var phraseQueue: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(practicePlayer.isReviewSession ? "Adaptive queue" : "Today’s phrases")
                    .font(.headline)
                    .id("sentences-section")
                Spacer()
                Text("\(practicePlayer.queueItems.count) phrases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVStack(spacing: 0) {
                ForEach(Array(practicePlayer.queueItems.enumerated()), id: \.element.id) { index, item in
                    phraseRow(number: index + 1, item: item, index: index)
                    if index < practicePlayer.queueItems.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func phraseRow(
        number: Int,
        item: PracticeQueueItem,
        index: Int
    ) -> some View {
        let isSelected = index == practicePlayer.selectedSentenceIndex
        let sentence = item.sentence
        return Button {
            practicePlayer.selectSentence(index)
        } label: {
            HStack(spacing: 12) {
                Text(String(format: "%02d", number))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, alignment: .trailing)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(sentence.promptHebrew)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if practicePlayer.isReviewSession {
                            Text("D\(item.lessonDay)")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(sentence.thai)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: practicePlayer.isPlaying ? "speaker.wave.2.fill" : "circle.fill")
                        .font(practicePlayer.isPlaying ? .caption : .system(size: 7))
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                        .accessibilityLabel(practicePlayer.isPlaying ? "Playing" : "Selected")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 54)
            .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Phrase \(number). \(sentence.promptHebrew). \(sentence.thai)")
        .accessibilityHint("Selects this phrase for practice")
    }

    private func startAdaptiveSession() {
        let queue = scheduler.sessionQueue(
            catalog: lessonStore.reviewCatalog,
            events: learningProgress.events
        )
        practicePlayer.configure(reviewQueue: queue)
        feedbackMessage = queue.isEmpty
            ? "Nothing is due and there are no new phrases."
            : "Reviews are first. Easy and Again update future sessions."
    }

    private func recordFeedback(_ rating: FeedbackRating) {
        guard let item = practicePlayer.currentQueueItem else { return }
        do {
            try learningProgress.record(rating, for: item.key)
            feedbackMessage = rating == .easy
                ? "Saved as Easy. Its next review follows the spacing ladder."
                : "Saved as Again. It will return at the end of this session."
            practicePlayer.advanceAfterFeedback(requeue: rating == .again)
        } catch {
            feedbackMessage = "Feedback was not saved: \(error.localizedDescription)"
        }
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.1f s", value)
    }

    private func rate(_ value: Double) -> String {
        String(format: "%.2g×", value)
    }

    private func format(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let totalSeconds = Int(interval.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct AdaptiveProgressSheet: View {
    @ObservedObject var learningProgress: LearningProgressStore
    let catalog: [PracticeQueueItem]
    let scheduler: ReviewScheduler

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let summary = scheduler.weeklySummary(
            catalog: catalog,
            events: learningProgress.events
        )
        let drafts = scheduler.threeDayDrafts(
            catalog: catalog,
            events: learningProgress.events
        )

        NavigationStack {
            List {
                Section("This week") {
                    LabeledContent("Reviews", value: "\(summary.reviewCount)")
                    LabeledContent("Easy", value: "\(summary.easyCount)")
                    LabeledContent("Again", value: "\(summary.againCount)")
                    LabeledContent(
                        "Easy rate",
                        value: summary.easyRate.formatted(
                            .percent.precision(.fractionLength(0))
                        )
                    )
                    LabeledContent("Practice days", value: "\(summary.practiceDayCount)")
                    LabeledContent("Due now", value: "\(summary.dueReviewCount)")
                }

                Section {
                    ForEach(drafts) { draft in
                        DisclosureGroup {
                            if draft.items.isEmpty {
                                Text("No practice items available.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(draft.items) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Text(item.kind == .review ? "Review" : "New")
                                            .font(.caption2.bold())
                                            .foregroundStyle(
                                                item.kind == .review ? Color.orange : Color.accentColor
                                            )
                                            .frame(width: 46, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.sentence.thai)
                                                .font(.subheadline.weight(.semibold))
                                            Text("Day \(item.lessonDay) · \(item.sentence.promptHebrew)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        } label: {
                            HStack {
                                Text(draft.date.formatted(
                                    .dateTime.weekday(.wide).month(.abbreviated).day()
                                ))
                                Spacer()
                                Text("\(draft.reviewCount)R · \(draft.newCount)N")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Three-day draft")
                } footer: {
                    Text(
                        "This is a non-mutating preview. Later days remain provisional until "
                        + "you submit real Easy or Again feedback."
                    )
                }

                Section {
                    ShareLink(item: learningProgress.exportJSONString()) {
                        Label("Share private progress export", systemImage: "square.and.arrow.up")
                    }
                    if let error = learningProgress.persistenceError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(
                        "Progress stays in this app unless you explicitly share this JSON. "
                        + "Sharing does not approve text, audio generation, or publishing."
                    )
                }
            }
            .navigationTitle("Learning progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LessonLibrarySheet: View {
    @ObservedObject var lessonStore: LessonStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(lessonStore.library) { item in
                        lessonRow(item)
                    }
                } header: {
                    Text("Saved lessons")
                } footer: {
                    Text(
                        "Downloaded lessons stay on this iPhone. New days are added to "
                        + "this library, so you can return to earlier practice anytime."
                    )
                }

                Section {
                    Button {
                        Task { await lessonStore.refresh() }
                    } label: {
                        if lessonStore.refreshState.isRefreshing {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Checking for a new lesson…")
                            }
                        } else {
                            Label("Check for new lesson", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(lessonStore.refreshState.isRefreshing)

                    refreshMessage
                } footer: {
                    Text("A newer revision replaces only the same day; other days are kept.")
                }
            }
            .navigationTitle("Lessons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func lessonRow(_ item: LessonStore.LibraryItem) -> some View {
        let selected = lessonStore.selectedLessonID == item.id
        return Button {
            lessonStore.selectLesson(id: item.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.accentColor : Color.secondary.opacity(0.13))
                    Text("\(item.package.lesson.day)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Day \(item.package.lesson.day)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(item.package.lesson.theme)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(item.source.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(selected ? "Current lesson" : "Switches to this saved lesson")
    }

    @ViewBuilder
    private var refreshMessage: some View {
        switch lessonStore.refreshState {
        case .idle, .refreshing:
            EmptyView()
        case let .succeeded(message):
            Label(message, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .unavailable(message), let .failed(message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PracticeSettingsSheet: View {
    @ObservedObject var lessonStore: LessonStore
    @ObservedObject var practicePlayer: PracticeSessionPlayer
    let package: LessonPackage

    @Environment(\.dismiss) private var dismiss

    private let rates = [0.75, 0.82, 0.9, 1.0, 1.1]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Editing preset")
                        Spacer()
                        Label(practicePlayer.activeTrack.title, systemImage: practicePlayer.activeTrack.systemImage)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                } footer: {
                    Text("Each practice mode keeps its own settings.")
                }

                Section("Sequence") {
                    Toggle("Speak Hebrew prompt", isOn: binding(\.speaksHebrew))

                    Stepper(
                        value: binding(\.hebrewToThaiDelay),
                        in: 0...10,
                        step: 0.5
                    ) {
                        settingLabel(
                            "Hebrew → Thai delay",
                            value: seconds(practicePlayer.configuration.hebrewToThaiDelay)
                        )
                    }
                    .disabled(!practicePlayer.configuration.speaksHebrew)

                    Stepper(value: binding(\.thaiRepetitions), in: 1...5) {
                        settingLabel(
                            "Thai repetitions",
                            value: "\(practicePlayer.configuration.thaiRepetitions)"
                        )
                    }

                    Toggle(
                        "Play related variation",
                        isOn: binding(\.playsVariations)
                    )

                    Stepper(
                        value: binding(\.gapBeforeVariation),
                        in: 0...5,
                        step: 0.5
                    ) {
                        settingLabel(
                            "Gap before variation",
                            value: seconds(practicePlayer.configuration.gapBeforeVariation)
                        )
                    }
                    .disabled(!practicePlayer.configuration.playsVariations)

                    Stepper(
                        value: binding(\.gapBetweenRepetitions),
                        in: 0...5,
                        step: 0.2
                    ) {
                        settingLabel(
                            "Gap between repeats",
                            value: seconds(practicePlayer.configuration.gapBetweenRepetitions)
                        )
                    }
                    .disabled(practicePlayer.configuration.thaiRepetitions < 2)

                    Stepper(
                        value: binding(\.gapBeforeNextSentence),
                        in: 0...10,
                        step: 0.5
                    ) {
                        settingLabel(
                            "Gap before next phrase",
                            value: seconds(practicePlayer.configuration.gapBeforeNextSentence)
                        )
                    }
                    .disabled(!practicePlayer.configuration.autoAdvance)
                }

                Section {
                    Picker("First Thai pass", selection: binding(\.firstThaiRate)) {
                        ForEach(rates, id: \.self) { value in
                            Text(rate(value)).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("Next Thai passes", selection: binding(\.laterThaiRate)) {
                        ForEach(rates, id: \.self) { value in
                            Text(rate(value)).tag(value)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(practicePlayer.configuration.thaiRepetitions < 2)
                } header: {
                    Text("Voice & pace")
                } footer: {
                    Text(
                        "When Hebrew prompts are on, each related version uses its own "
                        + "Hebrew cue before the Thai audio."
                    )
                }

                Section("Playback") {
                    Toggle("Auto-advance", isOn: binding(\.autoAdvance))
                    Toggle("Loop session", isOn: binding(\.loopsSession))
                    Picker("Order", selection: binding(\.order)) {
                        ForEach(PracticeOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("Content & audio") {
                    LabeledContent("Content source", value: lessonStore.contentSource.label)
                    LabeledContent("Lesson") {
                        Text("Day \(package.lesson.day) · r\(package.lesson.revision)")
                            .foregroundStyle(.secondary)
                    }
                    if practicePlayer.isReady {
                        Label("Configurable audio is ready offline", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if let error = practicePlayer.availabilityError {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await lessonStore.refresh() }
                    } label: {
                        if lessonStore.refreshState.isRefreshing {
                            HStack {
                                ProgressView()
                                Text("Checking for updates…")
                            }
                        } else {
                            Label("Check for lesson updates", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(lessonStore.refreshState.isRefreshing)

                    refreshMessage
                }

                Section {
                    Button("Reset \(practicePlayer.activeTrack.title) defaults") {
                        practicePlayer.resetActiveConfiguration()
                    }
                } footer: {
                    Text("Changes apply immediately and are saved on this iPhone.")
                }
            }
            .navigationTitle("Practice settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var refreshMessage: some View {
        switch lessonStore.refreshState {
        case .idle, .refreshing:
            EmptyView()
        case let .succeeded(message):
            Label(message, systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case let .unavailable(message), let .failed(message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(
        _ keyPath: WritableKeyPath<PracticeConfiguration, Value>
    ) -> Binding<Value> {
        Binding(
            get: { practicePlayer.configuration[keyPath: keyPath] },
            set: { practicePlayer.update(keyPath, to: $0) }
        )
    }

    private func settingLabel(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.1f s", value)
    }

    private func rate(_ value: Double) -> String {
        String(format: "%.2g×", value)
    }
}
