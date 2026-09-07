import MediaPlayer
import UIKit

struct NowPlayingPresentation: Equatable {
    let title: String
    let artist: String
    let album: String
    let elapsedTime: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let queueIndex: Int
    let queueCount: Int

    static func practice(
        sentence: LessonSentence?,
        day: Int?,
        mode: PracticeTrack,
        phase: PracticeSessionPlayer.Phase,
        sentenceIndex: Int,
        sentenceCount: Int,
        elapsedTime: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) -> NowPlayingPresentation {
        let phraseNumber = max(sentenceIndex + 1, 1)
        let safeCount = max(sentenceCount, 1)
        return NowPlayingPresentation(
            title: sentence?.thai ?? "Thai practice",
            artist: "Thai Echo · Day \(day ?? 1) · \(mode.title)",
            album: "\(phase.label) · Phrase \(phraseNumber) of \(safeCount)",
            elapsedTime: max(elapsedTime, 0),
            duration: max(duration, 0),
            isPlaying: isPlaying,
            queueIndex: min(max(sentenceIndex, 0), safeCount - 1),
            queueCount: safeCount
        )
    }
}

@MainActor
final class NowPlayingCoordinator {
    private weak var practicePlayer: PracticeSessionPlayer?
    private let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var hasConfiguredCommands = false
    private var artwork: MPMediaItemArtwork?

    func connect(to practicePlayer: PracticeSessionPlayer) {
        self.practicePlayer = practicePlayer
        guard !hasConfiguredCommands else { return }
        hasConfiguredCommands = true

        UIApplication.shared.beginReceivingRemoteControlEvents()
        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playFromRemote() }
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pauseFromRemote() }
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.practicePlayer?.togglePlayPause() }
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let player = self?.practicePlayer,
                  player.moveSentenceFromRemote(by: 1) else {
                return .commandFailed
            }
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let player = self?.practicePlayer,
                  player.moveSentenceFromRemote(by: -1) else {
                return .commandFailed
            }
            return .success
        }
        commandCenter.changePlaybackPositionCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
    }

    func publish(_ presentation: NowPlayingPresentation) {
        commandCenter.playCommand.isEnabled = !presentation.isPlaying
        commandCenter.pauseCommand.isEnabled = presentation.isPlaying
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = presentation.queueIndex > 0
        commandCenter.nextTrackCommand.isEnabled = presentation.queueIndex + 1 < presentation.queueCount

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: presentation.title,
            MPMediaItemPropertyArtist: presentation.artist,
            MPMediaItemPropertyAlbumTitle: presentation.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: presentation.elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: presentation.isPlaying ? 1 : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: presentation.queueIndex,
            MPNowPlayingInfoPropertyPlaybackQueueCount: presentation.queueCount,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if presentation.duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = presentation.duration
        }
        if let artwork = artwork ?? makeArtwork() {
            self.artwork = artwork
            info[MPMediaItemPropertyArtwork] = artwork
        }
        nowPlayingInfoCenter.nowPlayingInfo = info
        PlaybackDiagnostics.record(
            "now_playing_published",
            fields: [
                "duration": String(format: "%.3f", presentation.duration),
                "is_playing": presentation.isPlaying.description,
                "phase": presentation.album,
                "queue_count": String(presentation.queueCount),
                "queue_index": String(presentation.queueIndex),
            ]
        )
    }

    func clear() {
        nowPlayingInfoCenter.nowPlayingInfo = nil
        PlaybackDiagnostics.record("now_playing_cleared", fields: [:])
    }

    private func playFromRemote() {
        guard let practicePlayer else { return }
        if !practicePlayer.isPlaying {
            practicePlayer.togglePlayPause()
        }
    }

    private func pauseFromRemote() {
        guard let practicePlayer, practicePlayer.isPlaying else { return }
        practicePlayer.togglePlayPause()
    }

    private func makeArtwork() -> MPMediaItemArtwork? {
        let size = CGSize(width: 720, height: 720)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors = [
                UIColor(red: 0.05, green: 0.15, blue: 0.25, alpha: 1).cgColor,
                UIColor(red: 0.05, green: 0.50, blue: 0.47, alpha: 1).cgColor,
            ] as CFArray
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: [0, 1]
            )!
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            let inset = size.width * 0.11
            let glyph = UIImage(
                systemName: "waveform",
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: 250,
                    weight: .medium
                )
            )?.withTintColor(.white, renderingMode: .alwaysOriginal)
            glyph?.draw(in: CGRect(
                x: inset,
                y: size.height * 0.16,
                width: size.width - inset * 2,
                height: size.height * 0.42
            ))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 66, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.78),
            ]
            ("Thai Echo" as NSString).draw(
                in: CGRect(x: inset, y: size.height * 0.68, width: size.width - inset * 2, height: 80),
                withAttributes: titleAttributes
            )
            ("LISTEN · SPEAK · REMEMBER" as NSString).draw(
                in: CGRect(x: inset + 2, y: size.height * 0.80, width: size.width - inset * 2, height: 46),
                withAttributes: subtitleAttributes
            )
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }
}
