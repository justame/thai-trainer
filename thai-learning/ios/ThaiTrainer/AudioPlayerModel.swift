@preconcurrency import AVFoundation
import Combine
import Foundation
import OSLog

enum PlaybackDiagnostics {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yaron.ThaiTrainer",
        category: "PlaybackDiagnostics"
    )
    private static let maximumBytes = 512 * 1_024
    private static let retainedBytes = 256 * 1_024

    static func record(_ event: String, fields: [String: String]) {
        let renderedFields = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.replacingOccurrences(of: "\n", with: " "))" }
            .joined(separator: " | ")
        let line = "\(ISO8601DateFormatter().string(from: Date())) | \(event) | \(renderedFields)\n"

        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("ThaiTrainerContent", isDirectory: true)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let logURL = directory.appendingPathComponent("playback-diagnostics.log")
            try rotateIfNeeded(logURL)
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            logger.error("Unable to write playback diagnostics: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func fileDetails(for url: URL) -> [String: String] {
        var fields = [
            "track": url.lastPathComponent,
            "extension": url.pathExtension.lowercased(),
            "exists": FileManager.default.fileExists(atPath: url.path).description,
        ]
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            fields["bytes"] = String(size)
        }
        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let header = try? handle.read(upToCount: 16) {
                fields["header_hex"] = header.map { String(format: "%02x", $0) }.joined()
            }
        }
        return fields
    }

    static func errorDetails(_ error: NSError) -> [String: String] {
        var fields = [
            "error_domain": error.domain,
            "error_code": String(error.code),
            "error_description": error.localizedDescription,
        ]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            fields["underlying_domain"] = underlying.domain
            fields["underlying_code"] = String(underlying.code)
            fields["underlying_description"] = underlying.localizedDescription
        }
        return fields
    }

    private static func rotateIfNeeded(_ logURL: URL) throws {
        guard let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > maximumBytes else { return }
        let data = try Data(contentsOf: logURL)
        var retained = Data(data.suffix(retainedBytes))
        if let newline = retained.firstIndex(of: 0x0A), newline < retained.endIndex {
            retained.removeSubrange(retained.startIndex...newline)
        }
        try retained.write(to: logURL, options: .atomic)
    }
}

@MainActor
final class LocalAudioPlayer: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yaron.ThaiTrainer",
        category: "LocalAudioPlayer"
    )
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
    private var loadStage = "idle"

    var hasLoadedTrack: Bool { player != nil }

    func toggle(_ track: ValidatedAudioTrack) {
        if currentTrackID == track.id,
           currentTrackURL == track.fileURL,
           player != nil {
            togglePlayPause()
            return
        }

        do {
            loadStage = "starting"
            PlaybackDiagnostics.record(
                "track_selected",
                fields: PlaybackDiagnostics.fileDetails(for: track.fileURL)
            )
            try loadAndPlay(track)
        } catch {
            let nsError = error as NSError
            let fields = PlaybackDiagnostics.errorDetails(nsError).merging(
                ["stage": loadStage, "track": track.fileURL.lastPathComponent],
                uniquingKeysWith: { _, replacement in replacement }
            )
            PlaybackDiagnostics.record("load_failed", fields: fields)
            Self.logger.error(
                "Unable to load local track \(track.fileURL.lastPathComponent, privacy: .public) at \(self.loadStage, privacy: .public): \(nsError.domain, privacy: .public) (\(nsError.code, privacy: .public)) \(nsError.localizedDescription, privacy: .public)"
            )
            lastError = "Audio setup failed at \(loadStage): \(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]."
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
        loadStage = "audio session configuration"
        // .allowAirPlay is only legal when explicitly used with .playAndRecord.
        // Playback sessions already support AirPlay implicitly, and passing that
        // option here causes NSOSStatusErrorDomain -50 on the physical iPhone.
        try session.setCategory(.playback, mode: .spokenAudio)
        loadStage = "audio session activation"
        try session.setActive(true)
        PlaybackDiagnostics.record(
            "session_active",
            fields: [
                "category": session.category.rawValue,
                "mode": session.mode.rawValue,
                "route": session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ","),
            ]
        )

        // The downloaded tracks are MP3s. Supplying the type prevents iOS from
        // relying on filename/content sniffing in the app's cache directory.
        loadStage = "player creation"
        let newPlayer = try AVAudioPlayer(
            contentsOf: track.fileURL,
            fileTypeHint: AVFileType.mp3.rawValue
        )
        newPlayer.numberOfLoops = isLooping ? -1 : 0
        loadStage = "player preparation"
        guard newPlayer.prepareToPlay() else {
            throw LocalAudioPlayerError.playerCouldNotPrepare
        }
        PlaybackDiagnostics.record(
            "player_prepared",
            fields: [
                "track": track.fileURL.lastPathComponent,
                "duration": String(format: "%.3f", newPlayer.duration),
                "format": newPlayer.format.description,
            ]
        )

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
            PlaybackDiagnostics.record(
                "play_started",
                fields: [
                    "track": currentTrackURL?.lastPathComponent ?? "unknown",
                    "duration": String(format: "%.3f", player.duration),
                ]
            )
            isPlaying = true
            lastError = nil
            startProgressTimer()
        } catch {
            let nsError = error as NSError
            PlaybackDiagnostics.record(
                "play_failed",
                fields: PlaybackDiagnostics.errorDetails(nsError).merging(
                    ["track": currentTrackURL?.lastPathComponent ?? "unknown"],
                    uniquingKeysWith: { _, replacement in replacement }
                )
            )
            isPlaying = false
            lastError = "Playback failed: \(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]."
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
    case playerCouldNotPrepare
    case playbackDidNotStart
}
