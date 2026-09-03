@preconcurrency import AVFoundation
import Combine
import Foundation

@MainActor
final class LocalAudioPlayer: ObservableObject {
    @Published private(set) var currentTrackID: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var lastError: String?
    @Published var isLooping = false {
        didSet {
            player?.numberOfLoops = isLooping ? -1 : 0
        }
    }

    private var player: AVAudioPlayer?
    private var currentTrackURL: URL?
    private var progressTimer: Timer?

    var hasLoadedTrack: Bool { player != nil }

    func toggle(_ track: ValidatedAudioTrack) {
        if currentTrackID == track.id,
           currentTrackURL == track.fileURL,
           player != nil {
            togglePlayPause()
            return
        }

        do {
            try loadAndPlay(track)
        } catch {
            lastError = "This local audio file could not be played."
            stopProgressTimer()
            isPlaying = false
        }
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            refreshProgress()
            stopProgressTimer()
        } else {
            playLoadedTrack()
        }
    }

    func skip(by interval: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(player.currentTime + interval, 0), player.duration)
        refreshProgress()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), player.duration)
        refreshProgress()
    }

    private func loadAndPlay(_ track: ValidatedAudioTrack) throws {
        player?.stop()
        stopProgressTimer()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay])
        try session.setActive(true)

        let newPlayer = try AVAudioPlayer(contentsOf: track.fileURL)
        newPlayer.numberOfLoops = isLooping ? -1 : 0
        newPlayer.prepareToPlay()

        player = newPlayer
        currentTrackID = track.id
        currentTrackURL = track.fileURL
        currentTime = 0
        duration = newPlayer.duration
        lastError = nil
        playLoadedTrack()
    }

    private func playLoadedTrack() {
        guard let player else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if player.currentTime >= player.duration {
                player.currentTime = 0
            }
            guard player.play() else {
                throw LocalAudioPlayerError.playbackDidNotStart
            }
            isPlaying = true
            lastError = nil
            startProgressTimer()
        } catch {
            isPlaying = false
            lastError = "Audio playback could not start."
            stopProgressTimer()
        }
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func refreshProgress() {
        guard let player else { return }
        currentTime = player.currentTime
        duration = player.duration

        if isPlaying, !player.isPlaying, !isLooping {
            isPlaying = false
            stopProgressTimer()
        }
    }
}

private enum LocalAudioPlayerError: Error {
    case playbackDidNotStart
}
