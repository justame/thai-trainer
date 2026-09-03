import SwiftUI

struct TrainerView: View {
    @ObservedObject var lessonStore: LessonStore
    @ObservedObject var audioPlayer: LocalAudioPlayer

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        remoteContentControls

                        Group {
                            switch lessonStore.state {
                            case .loading:
                                ProgressView("Loading lesson…")
                                    .frame(maxWidth: .infinity, minHeight: 280)
                            case let .failed(message):
                                ContentUnavailableView(
                                    "Lesson unavailable",
                                    systemImage: "exclamationmark.triangle",
                                    description: Text(message)
                                )
                                .frame(minHeight: 280)
                            case let .loaded(package):
                                lessonContent(package)
                            }
                        }
                    }
                    .padding()
                }
                .navigationTitle("Thai Trainer")
                .task {
                    lessonStore.loadIfNeeded()
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--screenshot-sentences") {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        proxy.scrollTo("sentences-section", anchor: .top)
                    }
                    #endif
                    await lessonStore.refreshAutomaticallyIfNeeded()
                }
            }
        }
    }

    private var remoteContentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Updates: GitHub Pages", systemImage: "globe")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    Task {
                        await lessonStore.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(lessonStore.refreshState.isRefreshing)
            }

            refreshStatus
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var refreshStatus: some View {
        Group {
            switch lessonStore.refreshState {
            case .idle:
                Text(lessonStore.contentSource.label)
                    .foregroundStyle(.secondary)
            case let .refreshing(message):
                HStack(spacing: 8) {
                    ProgressView()
                    Text(message)
                }
                .foregroundStyle(.secondary)
            case let .succeeded(message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .unavailable(message):
                Text(message)
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
    }

    @ViewBuilder
    private func lessonContent(_ package: LessonPackage) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("DAY \(package.lesson.day)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(package.lesson.theme)
                    .font(.title2.weight(.semibold))
            }

            audioStatus(package.audioState)
            trackGrid(package.audioState.playableTracks)
            transport

            if let lastError = audioPlayer.lastError {
                Label(lastError, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("20 sentences")
                .font(.headline)
                .id("sentences-section")

            LazyVStack(spacing: 12) {
                ForEach(Array(package.lesson.sentences.enumerated()), id: \.element.id) { index, sentence in
                    sentenceCard(number: index + 1, sentence: sentence)
                }
            }
        }
    }

    @ViewBuilder
    private func audioStatus(_ state: AudioGenerationState) -> some View {
        switch state {
        case .notGenerated:
            statusBanner(
                title: "Audio not generated",
                message: "The lesson is ready to read. Playback stays off until the four MP3s and manifest are downloaded or bundled.",
                color: .orange,
                systemImage: "waveform.badge.exclamationmark"
            )
        case let .invalid(reason):
            statusBanner(
                title: "Audio package invalid",
                message: "\(reason) Playback is disabled for every track.",
                color: .red,
                systemImage: "xmark.shield"
            )
        case .ready:
            statusBanner(
                title: "Offline audio ready",
                message: "All four tracks passed the local manifest checks.",
                color: .green,
                systemImage: "checkmark.circle"
            )
        }
    }

    private func statusBanner(
        title: String,
        message: String,
        color: Color,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private func trackGrid(_ tracks: [ValidatedAudioTrack]) -> some View {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(PracticeTrack.allCases) { practiceTrack in
                let audioTrack = tracksByID[practiceTrack.id]
                Button {
                    if let audioTrack {
                        audioPlayer.toggle(audioTrack)
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: trackIcon(for: practiceTrack))
                            .font(.title2)
                        Text(practiceTrack.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.bordered)
                .disabled(audioTrack == nil)
            }
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { audioPlayer.seek(to: $0) }
                ),
                in: 0...max(audioPlayer.duration, 1)
            )
            .disabled(!audioPlayer.hasLoadedTrack)

            HStack {
                Text(format(audioPlayer.currentTime))
                Spacer()
                Text(format(audioPlayer.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                Button {
                    audioPlayer.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                }

                Button {
                    audioPlayer.togglePlayPause()
                } label: {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }

                Button {
                    audioPlayer.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                }

                Button {
                    audioPlayer.isLooping.toggle()
                } label: {
                    Image(systemName: "repeat")
                        .foregroundStyle(audioPlayer.isLooping ? Color.accentColor : Color.primary)
                }
                .accessibilityLabel(audioPlayer.isLooping ? "Turn looping off" : "Turn looping on")
            }
            .buttonStyle(.plain)
            .disabled(!audioPlayer.hasLoadedTrack)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sentenceCard(number: Int, sentence: LessonSentence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(number). \(sentence.promptHebrew)")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .environment(\.layoutDirection, .rightToLeft)
                .font(.body.weight(.medium))
            Text(sentence.thai)
                .font(.title3)
            Text(sentence.romanization)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func trackIcon(for track: PracticeTrack) -> String {
        guard audioPlayer.currentTrackID == track.id else { return track.systemImage }
        return audioPlayer.isPlaying ? "pause.fill" : "play.fill"
    }

    private func format(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval >= 0 else { return "0:00" }
        let totalSeconds = Int(interval.rounded(.down))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
