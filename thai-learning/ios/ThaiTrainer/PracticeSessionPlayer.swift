@preconcurrency import AVFoundation
import Combine
import CryptoKit
import Foundation
import OSLog

enum PracticeOrder: String, Codable, CaseIterable, Identifiable, Sendable {
    case sequential
    case shuffle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: "Sequential"
        case .shuffle: "Shuffle"
        }
    }
}

struct PracticeConfiguration: Codable, Equatable, Sendable {
    var speaksHebrew: Bool
    var hebrewToThaiDelay: Double
    var thaiRepetitions: Int
    var gapBetweenRepetitions: Double
    var gapBeforeNextSentence: Double
    var firstThaiRate: Double
    var laterThaiRate: Double
    var autoAdvance: Bool
    var loopsSession: Bool
    var order: PracticeOrder
    var playsVariations: Bool
    var gapBeforeVariation: Double

    init(
        speaksHebrew: Bool,
        hebrewToThaiDelay: Double,
        thaiRepetitions: Int,
        gapBetweenRepetitions: Double,
        gapBeforeNextSentence: Double,
        firstThaiRate: Double,
        laterThaiRate: Double,
        autoAdvance: Bool,
        loopsSession: Bool,
        order: PracticeOrder,
        playsVariations: Bool = true,
        gapBeforeVariation: Double = 1.5
    ) {
        self.speaksHebrew = speaksHebrew
        self.hebrewToThaiDelay = hebrewToThaiDelay
        self.thaiRepetitions = thaiRepetitions
        self.gapBetweenRepetitions = gapBetweenRepetitions
        self.gapBeforeNextSentence = gapBeforeNextSentence
        self.firstThaiRate = firstThaiRate
        self.laterThaiRate = laterThaiRate
        self.autoAdvance = autoAdvance
        self.loopsSession = loopsSession
        self.order = order
        self.playsVariations = playsVariations
        self.gapBeforeVariation = gapBeforeVariation
    }

    private enum CodingKeys: String, CodingKey {
        case speaksHebrew
        case hebrewToThaiDelay
        case thaiRepetitions
        case gapBetweenRepetitions
        case gapBeforeNextSentence
        case firstThaiRate
        case laterThaiRate
        case autoAdvance
        case loopsSession
        case order
        case playsVariations
        case gapBeforeVariation
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        speaksHebrew = try values.decode(Bool.self, forKey: .speaksHebrew)
        hebrewToThaiDelay = try values.decode(Double.self, forKey: .hebrewToThaiDelay)
        thaiRepetitions = try values.decode(Int.self, forKey: .thaiRepetitions)
        gapBetweenRepetitions = try values.decode(Double.self, forKey: .gapBetweenRepetitions)
        gapBeforeNextSentence = try values.decode(Double.self, forKey: .gapBeforeNextSentence)
        firstThaiRate = try values.decode(Double.self, forKey: .firstThaiRate)
        laterThaiRate = try values.decode(Double.self, forKey: .laterThaiRate)
        autoAdvance = try values.decode(Bool.self, forKey: .autoAdvance)
        loopsSession = try values.decode(Bool.self, forKey: .loopsSession)
        order = try values.decode(PracticeOrder.self, forKey: .order)
        playsVariations = try values.decodeIfPresent(Bool.self, forKey: .playsVariations) ?? true
        gapBeforeVariation = try values.decodeIfPresent(
            Double.self,
            forKey: .gapBeforeVariation
        ) ?? 1.5
    }

    static func defaults(for track: PracticeTrack) -> PracticeConfiguration {
        switch track {
        case .listening:
            PracticeConfiguration(
                speaksHebrew: true,
                hebrewToThaiDelay: 3,
                thaiRepetitions: 2,
                gapBetweenRepetitions: 1.2,
                gapBeforeNextSentence: 2.8,
                firstThaiRate: 0.82,
                laterThaiRate: 1,
                autoAdvance: true,
                loopsSession: false,
                order: .sequential
            )
        case .shadowing:
            PracticeConfiguration(
                speaksHebrew: false,
                hebrewToThaiDelay: 0,
                thaiRepetitions: 3,
                gapBetweenRepetitions: 0.7,
                gapBeforeNextSentence: 1.8,
                firstThaiRate: 0.9,
                laterThaiRate: 0.9,
                autoAdvance: true,
                loopsSession: false,
                order: .sequential
            )
        case .recall:
            PracticeConfiguration(
                speaksHebrew: true,
                hebrewToThaiDelay: 5,
                thaiRepetitions: 1,
                gapBetweenRepetitions: 0,
                gapBeforeNextSentence: 2.5,
                firstThaiRate: 0.9,
                laterThaiRate: 0.9,
                autoAdvance: true,
                loopsSession: false,
                order: .sequential
            )
        case .scenario:
            PracticeConfiguration(
                speaksHebrew: false,
                hebrewToThaiDelay: 0,
                thaiRepetitions: 1,
                gapBetweenRepetitions: 0,
                gapBeforeNextSentence: 1.2,
                firstThaiRate: 1,
                laterThaiRate: 1,
                autoAdvance: true,
                loopsSession: false,
                order: .sequential
            )
        }
    }

    func normalized() -> PracticeConfiguration {
        var result = self
        result.hebrewToThaiDelay = result.hebrewToThaiDelay.clamped(to: 0...10)
        result.thaiRepetitions = result.thaiRepetitions.clamped(to: 1...5)
        result.gapBetweenRepetitions = result.gapBetweenRepetitions.clamped(to: 0...5)
        result.gapBeforeNextSentence = result.gapBeforeNextSentence.clamped(to: 0...10)
        result.firstThaiRate = result.firstThaiRate.clamped(to: 0.75...1.1)
        result.laterThaiRate = result.laterThaiRate.clamped(to: 0.75...1.1)
        result.gapBeforeVariation = result.gapBeforeVariation.clamped(to: 0...5)
        return result
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct PracticeAudioClipManifest: Decodable, Sendable {
    let file: String
    let byteCount: Int64
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case file
        case byteCount = "bytes"
        case sha256
    }
}

struct PracticeAudioPairManifest: Decodable, Sendable {
    let hebrew: PracticeAudioClipManifest
    let thai: PracticeAudioClipManifest
}

struct PracticeAudioSentenceManifest: Decodable, Sendable {
    let sentenceID: String
    let core: PracticeAudioPairManifest
    let variations: [PracticeAudioPairManifest]

    enum CodingKeys: String, CodingKey {
        case sentenceID = "sentence_id"
        case core
        case variations
        case hebrew
        case thai
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sentenceID = try values.decode(String.self, forKey: .sentenceID)
        if let core = try values.decodeIfPresent(
            PracticeAudioPairManifest.self,
            forKey: .core
        ) {
            self.core = core
            variations = try values.decodeIfPresent(
                [PracticeAudioPairManifest].self,
                forKey: .variations
            ) ?? []
        } else {
            core = PracticeAudioPairManifest(
                hebrew: try values.decode(PracticeAudioClipManifest.self, forKey: .hebrew),
                thai: try values.decode(PracticeAudioClipManifest.self, forKey: .thai)
            )
            variations = []
        }
    }
}

struct PracticeAudioManifest: Decodable, Sendable {
    let schemaVersion: Int
    let lessonID: String
    let revision: Int
    let contentSHA256: String
    let sampleRateHertz: Int
    let sentences: [PracticeAudioSentenceManifest]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case lessonID = "lesson_id"
        case revision
        case contentSHA256 = "content_sha256"
        case sampleRateHertz = "sample_rate_hertz"
        case sentences
    }
}

struct PracticeAudioPair: Equatable, Sendable {
    let hebrewURL: URL
    let thaiURL: URL
}

struct PracticeSentenceAudio: Equatable, Identifiable, Sendable {
    let sentenceID: String
    let core: PracticeAudioPair
    let variations: [PracticeAudioPair]

    var id: String { sentenceID }
    var hebrewURL: URL { core.hebrewURL }
    var thaiURL: URL { core.thaiURL }
}

struct PracticeAudioPackageLoader {
    private let resourceRoot: URL?
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(
        resourceRoot: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) {
        self.resourceRoot = resourceRoot
        self.fileManager = fileManager
    }

    func load(for lesson: Lesson) throws -> [PracticeSentenceAudio] {
        guard let resourceRoot else { throw PracticeAudioLoadingError.missingResourceRoot }
        let directory = resourceRoot
            .appendingPathComponent("practice", isDirectory: true)
            .appendingPathComponent(lesson.lessonID, isDirectory: true)
            .appendingPathComponent("r\(lesson.revision)", isDirectory: true)
        let manifestURL = directory.appendingPathComponent("practice-manifest.json")
        guard isRegularFile(manifestURL) else {
            throw PracticeAudioLoadingError.missingManifest
        }

        let manifest: PracticeAudioManifest
        do {
            manifest = try decoder.decode(
                PracticeAudioManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw PracticeAudioLoadingError.invalidManifest("The manifest cannot be decoded.")
        }

        guard [1, 2].contains(manifest.schemaVersion),
              manifest.lessonID == lesson.lessonID,
              manifest.revision == lesson.revision,
              manifest.sampleRateHertz == 24_000,
              PublisherContentIntegrity.isValidSHA256(manifest.contentSHA256) else {
            throw PracticeAudioLoadingError.invalidManifest(
                "The manifest does not match the active approved lesson."
            )
        }

        let expectedIDs = lesson.sentences.map(\.id)
        let actualIDs = manifest.sentences.map(\.sentenceID)
        guard actualIDs == expectedIDs, Set(actualIDs).count == expectedIDs.count else {
            throw PracticeAudioLoadingError.invalidManifest(
                "The sentence audio order does not match the active lesson."
            )
        }

        return try manifest.sentences.map { entry in
            let core = try validate(entry.core, in: directory)
            let variations = try entry.variations.map { try validate($0, in: directory) }
            if manifest.schemaVersion == 2, variations.isEmpty {
                throw PracticeAudioLoadingError.invalidManifest(
                    "A revision-2 practice manifest needs at least one variation per sentence."
                )
            }
            return PracticeSentenceAudio(
                sentenceID: entry.sentenceID,
                core: core,
                variations: variations
            )
        }
    }

    private func validate(
        _ pair: PracticeAudioPairManifest,
        in directory: URL
    ) throws -> PracticeAudioPair {
        PracticeAudioPair(
            hebrewURL: try validate(pair.hebrew, in: directory),
            thaiURL: try validate(pair.thai, in: directory)
        )
    }

    private func validate(
        _ clip: PracticeAudioClipManifest,
        in directory: URL
    ) throws -> URL {
        guard isSafePathComponent(clip.file),
              clip.file.hasSuffix(".wav"),
              clip.byteCount > 44,
              PublisherContentIntegrity.isValidSHA256(clip.sha256) else {
            throw PracticeAudioLoadingError.invalidManifest("A clip declaration is invalid.")
        }
        let url = directory.appendingPathComponent(clip.file)
        guard isRegularFile(url) else {
            throw PracticeAudioLoadingError.missingClip(clip.file)
        }
        let data = try Data(contentsOf: url)
        guard Int64(data.count) == clip.byteCount else {
            throw PracticeAudioLoadingError.invalidClip("\(clip.file) has the wrong size.")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == clip.sha256 else {
            throw PracticeAudioLoadingError.invalidClip("\(clip.file) failed integrity checking.")
        }
        return url
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.contains("\0")
    }
}

enum PracticeAudioLoadingError: LocalizedError, Equatable {
    case missingResourceRoot
    case missingManifest
    case missingClip(String)
    case invalidManifest(String)
    case invalidClip(String)

    var errorDescription: String? {
        switch self {
        case .missingResourceRoot:
            "The app bundle has no resource directory."
        case .missingManifest:
            "Configurable sentence audio is unavailable for this lesson revision."
        case let .missingClip(file):
            "The sentence audio clip \(file) is missing."
        case let .invalidManifest(reason), let .invalidClip(reason):
            reason
        }
    }
}

enum PracticeSpeechLanguage: Equatable, Sendable {
    case hebrew
    case thai(repetition: Int, total: Int)
    case variationHebrew(index: Int, total: Int)
    case variationThai(index: Int, total: Int)
}

enum PracticePauseKind: Equatable, Sendable {
    case hebrewToThai
    case betweenRepetitions
    case beforeVariation
    case variationHebrewToThai
}

enum PracticeSequenceStep: Equatable, Sendable {
    case speech(url: URL, rate: Double, language: PracticeSpeechLanguage)
    case pause(seconds: Double, kind: PracticePauseKind)
}

enum PracticeSequenceBuilder {
    static func steps(
        for audio: PracticeSentenceAudio,
        configuration: PracticeConfiguration
    ) -> [PracticeSequenceStep] {
        let configuration = configuration.normalized()
        var steps: [PracticeSequenceStep] = []
        if configuration.speaksHebrew {
            steps.append(.speech(url: audio.hebrewURL, rate: 1, language: .hebrew))
            if configuration.hebrewToThaiDelay > 0 {
                steps.append(
                    .pause(
                        seconds: configuration.hebrewToThaiDelay,
                        kind: .hebrewToThai
                    )
                )
            }
        }
        for repetition in 1...configuration.thaiRepetitions {
            let rate = repetition == 1
                ? configuration.firstThaiRate
                : configuration.laterThaiRate
            steps.append(
                .speech(
                    url: audio.thaiURL,
                    rate: rate,
                    language: .thai(
                        repetition: repetition,
                        total: configuration.thaiRepetitions
                    )
                )
            )
            if repetition < configuration.thaiRepetitions,
               configuration.gapBetweenRepetitions > 0 {
                steps.append(
                    .pause(
                        seconds: configuration.gapBetweenRepetitions,
                        kind: .betweenRepetitions
                    )
                )
            }
        }
        if configuration.playsVariations {
            for (offset, variation) in audio.variations.enumerated() {
                let index = offset + 1
                if configuration.gapBeforeVariation > 0 {
                    steps.append(
                        .pause(
                            seconds: configuration.gapBeforeVariation,
                            kind: .beforeVariation
                        )
                    )
                }
                if configuration.speaksHebrew {
                    steps.append(
                        .speech(
                            url: variation.hebrewURL,
                            rate: 1,
                            language: .variationHebrew(
                                index: index,
                                total: audio.variations.count
                            )
                        )
                    )
                    if configuration.hebrewToThaiDelay > 0 {
                        steps.append(
                            .pause(
                                seconds: configuration.hebrewToThaiDelay,
                                kind: .variationHebrewToThai
                            )
                        )
                    }
                }
                steps.append(
                    .speech(
                        url: variation.thaiURL,
                        rate: configuration.laterThaiRate,
                        language: .variationThai(
                            index: index,
                            total: audio.variations.count
                        )
                    )
                )
            }
        }
        return steps
    }
}

enum PracticeSilenceAudio {
    static let sampleRateHertz = 24_000

    static func wavData(
        duration: Double,
        sampleRateHertz: Int = sampleRateHertz
    ) throws -> Data {
        guard duration.isFinite,
              duration > 0,
              duration <= 10,
              sampleRateHertz > 0 else {
            throw PracticeSilenceAudioError.invalidDuration
        }

        let frameCount = Int((duration * Double(sampleRateHertz)).rounded())
        let audioByteCount = frameCount * MemoryLayout<Int16>.size
        guard frameCount > 0,
              audioByteCount <= Int(UInt32.max - 36) else {
            throw PracticeSilenceAudioError.invalidDuration
        }

        var data = Data()
        data.reserveCapacity(44 + audioByteCount)
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + audioByteCount), to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRateHertz), to: &data)
        append(UInt32(sampleRateHertz * MemoryLayout<Int16>.size), to: &data)
        append(UInt16(MemoryLayout<Int16>.size), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(UInt32(audioByteCount), to: &data)
        data.append(Data(count: audioByteCount))
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

private enum PracticeSilenceAudioError: LocalizedError {
    case invalidDuration

    var errorDescription: String? {
        "The configured background-audio pause is invalid."
    }
}

@MainActor
final class PracticeSessionPlayer: ObservableObject {
    enum Phase: Equatable {
        case idle
        case hebrew
        case waitingForThai
        case thai(repetition: Int, total: Int)
        case betweenRepetitions
        case beforeVariation
        case variationHebrew(index: Int, total: Int)
        case waitingForVariationThai
        case variationThai(index: Int, total: Int)
        case beforeNextSentence

        var label: String {
            switch self {
            case .idle: "Ready"
            case .hebrew: "Hebrew prompt"
            case .waitingForThai: "Your turn"
            case let .thai(repetition, total): "Thai · pass \(repetition) of \(total)"
            case .betweenRepetitions: "Repeat gap"
            case .beforeVariation: "Related version next"
            case let .variationHebrew(index, total):
                "Variation \(index) of \(total) · Hebrew cue"
            case .waitingForVariationThai: "Your turn · variation"
            case let .variationThai(index, total):
                "Variation \(index) of \(total) · Thai"
            case .beforeNextSentence: "Next phrase soon"
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.yaron.ThaiTrainer",
        category: "PracticeSessionPlayer"
    )
    private static let settingsKey = "thai-trainer.practice-configurations.v1"

    @Published private(set) var activeTrack: PracticeTrack = .listening
    @Published private(set) var selectedSentenceIndex = 0
    @Published private(set) var configurations: [String: PracticeConfiguration]
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var availabilityError: String?
    @Published private(set) var playbackError: String?
    @Published private(set) var queueItems: [PracticeQueueItem] = []
    @Published private(set) var isReviewSession = false

    private let userDefaults: UserDefaults
    private var configuredLessonToken: String?
    private var player: AVAudioPlayer?
    private var playTask: Task<Void, Never>?
    private var sessionToken = UUID()
    private var silenceDataCache: [Int: Data] = [:]
    private lazy var nowPlaying = NowPlayingCoordinator()

    convenience init() {
        self.init(userDefaults: .standard, resourceRoot: Bundle.main.resourceURL)
    }

    init(userDefaults: UserDefaults, resourceRoot _: URL?) {
        self.userDefaults = userDefaults
        configurations = Dictionary(
            uniqueKeysWithValues: PracticeTrack.allCases.map {
                ($0.id, PracticeConfiguration.defaults(for: $0))
            }
        )
        loadPersistedConfigurations()
    }

    var configuration: PracticeConfiguration {
        configurations[activeTrack.id] ?? .defaults(for: activeTrack)
    }

    var isReady: Bool {
        availabilityError == nil && !queueItems.isEmpty
    }

    var currentQueueItem: PracticeQueueItem? {
        guard queueItems.indices.contains(selectedSentenceIndex) else { return nil }
        return queueItems[selectedSentenceIndex]
    }

    func configure(for package: LessonPackage) {
        let token = [
            package.lesson.lessonID,
            "r\(package.lesson.revision)",
            package.contentSHA256,
            package.resourceRootURL.standardizedFileURL.path,
        ].joined(separator: "|")
        nowPlaying.connect(to: self)
        guard token != configuredLessonToken else { return }
        stopPlayback(resetPhase: true)
        configuredLessonToken = token
        selectedSentenceIndex = 0
        isReviewSession = false
        do {
            queueItems = try PracticeQueueItem.items(for: package)
            availabilityError = nil
        } catch {
            queueItems = []
            availabilityError = error.localizedDescription
        }
    }

    func configure(reviewQueue: [PracticeQueueItem]) {
        nowPlaying.connect(to: self)
        stopPlayback(resetPhase: true)
        configuredLessonToken = "review:\(reviewQueue.map(\.id).joined(separator: ","))"
        queueItems = reviewQueue
        selectedSentenceIndex = 0
        isReviewSession = true
        availabilityError = reviewQueue.isEmpty ? "No phrases are due for practice." : nil
    }

    func advanceAfterFeedback(requeue: Bool) {
        guard queueItems.indices.contains(selectedSentenceIndex) else { return }
        let wasPlaying = isPlaying
        stopPlayback(resetPhase: true)
        let completed = queueItems.remove(at: selectedSentenceIndex)
        if requeue {
            queueItems.append(completed)
        }
        if queueItems.isEmpty {
            selectedSentenceIndex = 0
            availabilityError = "Practice complete for now."
            return
        }
        selectedSentenceIndex = min(selectedSentenceIndex, queueItems.count - 1)
        availabilityError = nil
        if wasPlaying { startSession() }
    }

    func selectTrack(_ track: PracticeTrack) {
        guard activeTrack != track else { return }
        stopPlayback(resetPhase: true)
        activeTrack = track
    }

    func selectSentence(_ index: Int, play: Bool = false) {
        guard queueItems.indices.contains(index) else { return }
        let wasActive = playTask != nil
        stopPlayback(resetPhase: true)
        selectedSentenceIndex = index
        if play || wasActive {
            startSession()
        }
    }

    func moveSentence(by offset: Int) {
        guard !queueItems.isEmpty else { return }
        let newIndex = (selectedSentenceIndex + offset).clamped(
            to: 0...(queueItems.count - 1)
        )
        selectSentence(newIndex, play: playTask != nil)
    }

    func moveSentenceFromRemote(by offset: Int) -> Bool {
        guard !queueItems.isEmpty else { return false }
        let target = selectedSentenceIndex + offset
        guard queueItems.indices.contains(target) else { return false }
        moveSentence(by: offset)
        return true
    }

    func togglePlayPause() {
        guard isReady else { return }
        if playTask == nil {
            startSession()
        } else if isPlaying {
            isPlaying = false
            player?.pause()
            publishNowPlaying()
        } else {
            isPlaying = true
            if let player, player.currentTime < player.duration {
                _ = player.play()
            }
            publishNowPlaying()
        }
    }

    func stop() {
        stopPlayback(resetPhase: true)
    }

    func update<Value>(
        _ keyPath: WritableKeyPath<PracticeConfiguration, Value>,
        to value: Value
    ) {
        var updated = configuration
        updated[keyPath: keyPath] = value
        configurations[activeTrack.id] = updated.normalized()
        persistConfigurations()
    }

    func resetActiveConfiguration() {
        configurations[activeTrack.id] = .defaults(for: activeTrack)
        persistConfigurations()
    }

    private func loadPersistedConfigurations() {
        guard let data = userDefaults.data(forKey: Self.settingsKey),
              let decoded = try? JSONDecoder().decode(
                  [String: PracticeConfiguration].self,
                  from: data
              ) else { return }
        for track in PracticeTrack.allCases {
            if let configuration = decoded[track.id] {
                configurations[track.id] = configuration.normalized()
            }
        }
    }

    private func persistConfigurations() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        userDefaults.set(data, forKey: Self.settingsKey)
    }

    private func startSession() {
        guard isReady, playTask == nil else { return }
        playbackError = nil
        isPlaying = true
        let token = UUID()
        sessionToken = token
        playTask = Task { [weak self] in
            await self?.runSession(token: token)
        }
    }

    private func runSession(token: UUID) async {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            PlaybackDiagnostics.record(
                "practice_session_started",
                fields: [
                    "category": session.category.rawValue,
                    "mode": session.mode.rawValue,
                    "route": session.currentRoute.outputs.map {
                        "\($0.portType.rawValue):\($0.portName)"
                    }.joined(separator: ","),
                    "sentence_count": String(queueItems.count),
                    "track": activeTrack.id,
                ]
            )
        } catch {
            finish(token: token, error: "Audio session failed: \(error.localizedDescription)")
            return
        }

        var order = Array(queueItems.indices)
        if configuration.order == .shuffle {
            order.shuffle()
            order.removeAll { $0 == selectedSentenceIndex }
            order.insert(selectedSentenceIndex, at: 0)
        } else if let start = order.firstIndex(of: selectedSentenceIndex) {
            order = Array(order[start...])
        }

        var position = 0
        while token == sessionToken, !Task.isCancelled, position < order.count {
            let sentenceIndex = order[position]
            selectedSentenceIndex = sentenceIndex
            let audio = queueItems[sentenceIndex].audio

            let steps = PracticeSequenceBuilder.steps(
                for: audio,
                configuration: configuration
            )
            for step in steps {
                guard token == sessionToken, !Task.isCancelled else { return }
                do {
                    switch step {
                    case let .speech(url, rate, language):
                        switch language {
                        case .hebrew:
                            phase = .hebrew
                        case let .thai(repetition, total):
                            phase = .thai(repetition: repetition, total: total)
                        case let .variationHebrew(index, total):
                            phase = .variationHebrew(index: index, total: total)
                        case let .variationThai(index, total):
                            phase = .variationThai(index: index, total: total)
                        }
                        try await playClip(url, rate: rate, token: token)
                    case let .pause(seconds, kind):
                        switch kind {
                        case .hebrewToThai:
                            phase = .waitingForThai
                        case .betweenRepetitions:
                            phase = .betweenRepetitions
                        case .beforeVariation:
                            phase = .beforeVariation
                        case .variationHebrewToThai:
                            phase = .waitingForVariationThai
                        }
                        try await playSilence(seconds: seconds, token: token)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    finish(token: token, error: error.localizedDescription)
                    return
                }
            }

            let currentConfiguration = configuration
            guard currentConfiguration.autoAdvance else { break }
            position += 1
            if position >= order.count {
                guard currentConfiguration.loopsSession else { break }
                position = 0
                if currentConfiguration.order == .shuffle {
                    order.shuffle()
                }
            }
            phase = .beforeNextSentence
            do {
                try await playSilence(
                    seconds: currentConfiguration.gapBeforeNextSentence,
                    token: token
                )
            } catch is CancellationError {
                return
            } catch {
                finish(token: token, error: error.localizedDescription)
                return
            }
        }
        finish(token: token, error: nil)
    }

    private func playClip(_ url: URL, rate: Double, token: UUID) async throws {
        let newPlayer = try AVAudioPlayer(
            contentsOf: url,
            fileTypeHint: AVFileType.wav.rawValue
        )
        newPlayer.enableRate = true
        newPlayer.rate = Float(rate)
        guard newPlayer.prepareToPlay() else {
            throw PracticePlayerError.playerCouldNotPrepare
        }
        player = newPlayer
        currentTime = 0
        let effectiveDuration = newPlayer.duration / rate
        duration = effectiveDuration
        guard newPlayer.play() else {
            throw PracticePlayerError.playbackDidNotStart
        }
        publishNowPlaying()
        PlaybackDiagnostics.record(
            "practice_clip_started",
            fields: [
                "duration": String(format: "%.3f", effectiveDuration),
                "phase": phase.label,
                "rate": String(format: "%.2f", rate),
                "sentence": currentSentenceID,
                "track": url.lastPathComponent,
            ]
        )

        var elapsed: TimeInterval = 0
        while token == sessionToken,
              !Task.isCancelled,
              elapsed < effectiveDuration {
            if !isPlaying {
                if newPlayer.isPlaying { newPlayer.pause() }
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
            if !newPlayer.isPlaying {
                guard newPlayer.play() else {
                    throw PracticePlayerError.playbackDidNotStart
                }
            }
            try await Task.sleep(for: .milliseconds(50))
            elapsed += 0.05
            currentTime = min(elapsed, effectiveDuration)
        }
        newPlayer.stop()
        guard token == sessionToken, !Task.isCancelled else {
            throw CancellationError()
        }
        currentTime = effectiveDuration
        PlaybackDiagnostics.record(
            "practice_clip_finished",
            fields: [
                "phase": phase.label,
                "sentence": currentSentenceID,
                "track": url.lastPathComponent,
            ]
        )
        return
    }

    private func playSilence(seconds: Double, token: UUID) async throws {
        guard seconds > 0 else { return }
        let data = try silenceData(for: seconds)
        let newPlayer = try AVAudioPlayer(
            data: data,
            fileTypeHint: AVFileType.wav.rawValue
        )
        guard newPlayer.prepareToPlay() else {
            throw PracticePlayerError.playerCouldNotPrepare
        }
        player = newPlayer
        duration = newPlayer.duration
        currentTime = 0
        guard newPlayer.play() else {
            throw PracticePlayerError.playbackDidNotStart
        }
        publishNowPlaying()
        PlaybackDiagnostics.record(
            "practice_pause_started",
            fields: [
                "duration": String(format: "%.3f", newPlayer.duration),
                "phase": phase.label,
                "sentence": currentSentenceID,
            ]
        )

        var elapsed: TimeInterval = 0
        while token == sessionToken,
              !Task.isCancelled,
              elapsed < newPlayer.duration {
            if !isPlaying {
                if newPlayer.isPlaying { newPlayer.pause() }
                try await Task.sleep(for: .milliseconds(50))
                continue
            }
            if !newPlayer.isPlaying {
                guard newPlayer.play() else {
                    throw PracticePlayerError.playbackDidNotStart
                }
            }
            try await Task.sleep(for: .milliseconds(50))
            elapsed += 0.05
            currentTime = min(elapsed, newPlayer.duration)
        }
        newPlayer.stop()
        guard token == sessionToken, !Task.isCancelled else {
            throw CancellationError()
        }
        currentTime = newPlayer.duration
        PlaybackDiagnostics.record(
            "practice_pause_finished",
            fields: [
                "phase": phase.label,
                "sentence": currentSentenceID,
            ]
        )
    }

    private func silenceData(for seconds: Double) throws -> Data {
        let milliseconds = Int((seconds * 1_000).rounded())
        if let cached = silenceDataCache[milliseconds] { return cached }
        let data = try PracticeSilenceAudio.wavData(
            duration: Double(milliseconds) / 1_000
        )
        silenceDataCache[milliseconds] = data
        return data
    }

    private var currentSentenceID: String {
        currentQueueItem?.sentence.id ?? "unknown"
    }

    private func publishNowPlaying() {
        let item = currentQueueItem
        nowPlaying.publish(.practice(
            sentence: item?.sentence,
            day: item?.lessonDay,
            mode: activeTrack,
            phase: phase,
            sentenceIndex: selectedSentenceIndex,
            sentenceCount: queueItems.count,
            elapsedTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        ))
    }

    private func finish(token: UUID, error: String?) {
        guard token == sessionToken else { return }
        if let error {
            Self.logger.error("Configurable playback failed: \(error, privacy: .public)")
            PlaybackDiagnostics.record(
                "practice_session_failed",
                fields: [
                    "error": error,
                    "phase": phase.label,
                    "sentence": currentSentenceID,
                    "track": activeTrack.id,
                ]
            )
            playbackError = error
        } else {
            PlaybackDiagnostics.record(
                "practice_session_finished",
                fields: [
                    "sentence": currentSentenceID,
                    "track": activeTrack.id,
                ]
            )
        }
        player?.stop()
        player = nil
        playTask = nil
        isPlaying = false
        phase = .idle
        currentTime = 0
        duration = 0
        nowPlaying.clear()
    }

    private func stopPlayback(resetPhase: Bool) {
        if playTask != nil {
            PlaybackDiagnostics.record(
                "practice_session_stopped",
                fields: [
                    "phase": phase.label,
                    "sentence": currentSentenceID,
                    "track": activeTrack.id,
                ]
            )
        }
        sessionToken = UUID()
        playTask?.cancel()
        playTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        nowPlaying.clear()
        if resetPhase { phase = .idle }
    }
}

private enum PracticePlayerError: LocalizedError {
    case playerCouldNotPrepare
    case playbackDidNotStart

    var errorDescription: String? {
        switch self {
        case .playerCouldNotPrepare:
            "The sentence audio could not be prepared."
        case .playbackDidNotStart:
            "The sentence audio could not start."
        }
    }
}
