@preconcurrency import AVFoundation
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
    @State private var wordsExpanded = false
    @StateObject private var wordAudioPlayer = WordAudioPlayer()

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
                                    resetSentenceScreen()
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
                                    if ProcessInfo.processInfo.arguments.contains("--screenshot-words") {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        wordsExpanded = true
                                    }
                                    if ProcessInfo.processInfo.arguments.contains("--autoplay-sentence") {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        practicePlayer.playCurrentSentenceOnce()
                                    }
                                    #endif
                                }
                                .onChange(of: practicePlayer.currentQueueItem?.id) { _, _ in
                                    resetSentenceScreen()
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
                .navigationTitle("Everyday Thai")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showsLessonLibrary = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.backward")
                                Text(currentDayTitle)
                            }
                        }
                        .accessibilityHint("Choose a saved lesson day")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Playback settings", systemImage: "slider.horizontal.3") {
                                settingsDetent = .large
                                showsSettings = true
                            }
                            Button("Weekly summary", systemImage: "chart.bar.xaxis") {
                                showsProgress = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
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

    private var currentDayTitle: String {
        guard case let .loaded(package) = lessonStore.state else { return "Lessons" }
        return "Day \(package.lesson.day)"
    }

    private func lessonContent(_ package: LessonPackage) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let item = practicePlayer.currentQueueItem {
                sentenceScreen(item)
            } else if practicePlayer.isReviewSession {
                ContentUnavailableView(
                    "Practice complete",
                    systemImage: "checkmark.circle",
                    description: Text("Your feedback is saved on this iPhone.")
                )
                .frame(minHeight: 280)
            } else if let error = practicePlayer.availabilityError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 24)
    }

    private func sentenceScreen(_ item: PracticeQueueItem) -> some View {
        let sentence = item.sentence
        return VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 10) {
                Text(sentence.thai)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Text(sentence.romanization)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(sentence.promptHebrew)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.top, 6)
            }

            Button {
                wordAudioPlayer.stop()
                practicePlayer.toggleCurrentSentenceOnce()
            } label: {
                Label(
                    practicePlayer.isPlaying ? "Pause" : "Play sentence",
                    systemImage: practicePlayer.isPlaying ? "pause.fill" : "play.fill"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!practicePlayer.isReady)

            if let error = practicePlayer.playbackError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !sentence.learningVocabulary.isEmpty {
                DisclosureGroup(isExpanded: $wordsExpanded) {
                    VStack(spacing: 0) {
                        ForEach(sentence.learningVocabulary) { word in
                            wordRow(word)
                            if word.id != sentence.learningVocabulary.last?.id {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Words")
                        .font(.headline)
                }
                .tint(.primary)
            }

            NavigationLink {
                relatedSentenceScreen(item)
            } label: {
                HStack {
                    Text("Related sentences")
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .font(.body)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            sentenceNavigation
        }
    }

    private func wordRow(_ word: LessonWord) -> some View {
        HStack(spacing: 12) {
            Button {
                practicePlayer.stop()
                wordAudioPlayer.speak(word.thai)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .frame(width: 32, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityLabel("Play \(word.thai)")

            VStack(alignment: .leading, spacing: 2) {
                Text(word.thai)
                    .font(.body.weight(.semibold))
                Text(word.romanization)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(word.meaningHebrew)
                .font(.body)
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .frame(minHeight: 54)
    }

    private var sentenceNavigation: some View {
        HStack {
            Button {
                wordAudioPlayer.stop()
                practicePlayer.moveSentence(by: -1)
            } label: {
                Label("Previous", systemImage: "chevron.backward")
            }
            .disabled(practicePlayer.selectedSentenceIndex == 0)

            Spacer()

            Button {
                wordAudioPlayer.stop()
                practicePlayer.moveSentence(by: 1)
            } label: {
                Label("Next", systemImage: "chevron.forward")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(practicePlayer.selectedSentenceIndex >= practicePlayer.queueItems.count - 1)
        }
        .font(.subheadline.weight(.medium))
    }

    private func relatedSentenceScreen(_ item: PracticeQueueItem) -> some View {
        VStack(spacing: 14) {
            Text(item.sentence.variation.thai)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(item.sentence.variation.promptHebrew)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .environment(\.layoutDirection, .rightToLeft)
                .padding(.top, 6)
            Button {
                wordAudioPlayer.stop()
                practicePlayer.playCurrentVariationOnce()
            } label: {
                Label("Play sentence", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!practicePlayer.isReady)
            Spacer()
        }
        .padding(24)
        .navigationTitle("Related sentence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resetSentenceScreen() {
        wordAudioPlayer.stop()
        wordsExpanded = false
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

@MainActor
private final class WordAudioPlayer: ObservableObject {
    @Published private(set) var errorMessage: String?

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        stop()
        errorMessage = nil

        guard let voice = AVSpeechSynthesisVoice(language: "th-TH") else {
            errorMessage = "Couldn’t play this word. Try again."
            PlaybackDiagnostics.record(
                "word_tts_failed",
                fields: ["reason": "thai_voice_unavailable", "word": text]
            )
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)

            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
            utterance.pitchMultiplier = 1
            utterance.volume = 1
            synthesizer.speak(utterance)
            PlaybackDiagnostics.record(
                "word_tts_started",
                fields: ["language": voice.language, "word": text]
            )
        } catch {
            errorMessage = "Couldn’t play this word. Try again."
            PlaybackDiagnostics.record(
                "word_tts_failed",
                fields: ["reason": error.localizedDescription, "word": text]
            )
        }
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
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
