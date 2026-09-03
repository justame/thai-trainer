import Combine
import Foundation

struct LessonPackageLoader {
    static let lessonRelativePath = "days/day-001.json"
    static let manifestFilename = "audio-manifest.json"

    private let resourceRoot: URL?
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        resourceRoot = bundle.resourceURL
        self.fileManager = fileManager
        decoder = JSONDecoder()
    }

    init(resourceRoot: URL, fileManager: FileManager = .default) {
        self.resourceRoot = resourceRoot
        self.fileManager = fileManager
        decoder = JSONDecoder()
    }

    func load() throws -> LessonPackage {
        guard let resourceRoot else {
            throw LessonPackageLoadingError.missingResourceRoot
        }

        let lessonURL = resourceRoot.appendingPathComponent(Self.lessonRelativePath)
        guard isRegularFile(at: lessonURL) else {
            throw LessonPackageLoadingError.missingLesson(Self.lessonRelativePath)
        }

        let lessonData: Data
        do {
            lessonData = try Data(contentsOf: lessonURL)
        } catch {
            throw LessonPackageLoadingError.unreadableLesson(error.localizedDescription)
        }

        let lesson: Lesson
        do {
            lesson = try decoder.decode(Lesson.self, from: lessonData)
        } catch {
            throw LessonPackageLoadingError.unreadableLesson(error.localizedDescription)
        }

        try validateLessonTrackContract(lesson)
        let audioState = validateAudio(
            for: lesson,
            lessonData: lessonData,
            resourceRoot: resourceRoot
        )
        return LessonPackage(lesson: lesson, audioState: audioState)
    }

    private func validateLessonTrackContract(_ lesson: Lesson) throws {
        guard lesson.schemaVersion == 1 else {
            throw LessonPackageLoadingError.invalidLesson("schema_version must be 1")
        }
        guard lesson.revision > 0 else {
            throw LessonPackageLoadingError.invalidLesson("revision must be positive")
        }
        if let violation = LessonContentContract.violation(in: lesson) {
            throw LessonPackageLoadingError.invalidLesson(violation)
        }

        let trackIDs = lesson.audioProgram.tracks.map(\.id)
        let expectedTrackIDs = PracticeTrack.allCases.map(\.rawValue)

        guard Set(trackIDs).count == trackIDs.count else {
            throw LessonPackageLoadingError.invalidLesson("audio_program contains duplicate track IDs")
        }
        guard Set(trackIDs) == Set(expectedTrackIDs), trackIDs.count == expectedTrackIDs.count else {
            throw LessonPackageLoadingError.invalidLesson(
                "audio_program must contain exactly: \(expectedTrackIDs.joined(separator: ", "))"
            )
        }
    }

    private func validateAudio(
        for lesson: Lesson,
        lessonData: Data,
        resourceRoot: URL
    ) -> AudioGenerationState {
        let revisionDirectory = resourceRoot
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent(lesson.lessonID, isDirectory: true)
            .appendingPathComponent("r\(lesson.revision)", isDirectory: true)
        let manifestURL = revisionDirectory.appendingPathComponent(Self.manifestFilename)

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return .notGenerated
        }
        guard isRegularFile(at: manifestURL) else {
            return .invalid(reason: "The audio manifest is not a regular file.")
        }

        let manifest: AudioManifest
        do {
            manifest = try decoder.decode(AudioManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            return .invalid(reason: "The audio manifest cannot be decoded.")
        }

        guard manifest.schemaVersion == 1 else {
            return .invalid(reason: "The audio manifest schema is unsupported.")
        }
        guard manifest.lessonID == lesson.lessonID, manifest.revision == lesson.revision else {
            return .invalid(reason: "The audio manifest targets another lesson revision.")
        }
        let lessonContentSHA256: String
        do {
            lessonContentSHA256 = try PublisherContentIntegrity.sha256(forLessonData: lessonData)
        } catch {
            return .invalid(reason: "The lesson cannot be hashed using the publisher content contract.")
        }
        guard PublisherContentIntegrity.isValidSHA256(manifest.contentSHA256),
              manifest.contentSHA256 == lessonContentSHA256 else {
            return .invalid(reason: "The audio manifest content hash does not match the lesson.")
        }

        let expectedTrackIDs = lesson.audioProgram.tracks.map(\.id)
        let actualTrackIDs = manifest.tracks.map(\.trackID)
        guard Set(actualTrackIDs).count == actualTrackIDs.count else {
            return .invalid(reason: "The audio manifest contains duplicate track IDs.")
        }
        guard actualTrackIDs.count == expectedTrackIDs.count,
              Set(actualTrackIDs) == Set(expectedTrackIDs) else {
            return .invalid(reason: "The audio manifest does not contain the exact expected tracks.")
        }

        let manifestTracks = Dictionary(uniqueKeysWithValues: manifest.tracks.map { ($0.trackID, $0) })
        var validatedTracks: [ValidatedAudioTrack] = []

        for trackID in expectedTrackIDs {
            guard let manifestTrack = manifestTracks[trackID] else {
                return .invalid(reason: "The audio manifest is missing \(trackID).")
            }
            guard manifestTrack.lessonID == lesson.lessonID,
                  manifestTrack.revision == lesson.revision else {
                return .invalid(reason: "Track \(trackID) targets another lesson revision.")
            }

            let expectedFilename = "\(trackID).mp3"
            guard manifestTrack.file == expectedFilename else {
                return .invalid(reason: "Track \(trackID) has an unexpected filename.")
            }
            guard manifestTrack.byteCount > 0 else {
                return .invalid(reason: "Track \(trackID) declares an empty file.")
            }
            guard PublisherContentIntegrity.isValidSHA256(manifestTrack.contentSHA256),
                  manifestTrack.contentSHA256 == lessonContentSHA256,
                  manifestTrack.contentSHA256 == manifest.contentSHA256 else {
                return .invalid(reason: "Track \(trackID) content hash does not match the lesson.")
            }

            let audioURL = revisionDirectory.appendingPathComponent(expectedFilename)
            guard isRegularFile(at: audioURL) else {
                return .invalid(reason: "Track \(trackID) is missing.")
            }

            do {
                let attributes = try fileManager.attributesOfItem(atPath: audioURL.path)
                guard let size = attributes[.size] as? NSNumber,
                      size.int64Value > 0,
                      size.int64Value == manifestTrack.byteCount else {
                    return .invalid(reason: "Track \(trackID) does not match its manifest byte count.")
                }
            } catch {
                return .invalid(reason: "Track \(trackID) cannot be inspected.")
            }

            validatedTracks.append(ValidatedAudioTrack(id: trackID, fileURL: audioURL))
        }

        return .ready(validatedTracks)
    }

    private func isRegularFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

enum LessonPackageLoadingError: LocalizedError, Equatable {
    case missingResourceRoot
    case missingLesson(String)
    case unreadableLesson(String)
    case invalidLesson(String)

    var errorDescription: String? {
        switch self {
        case .missingResourceRoot:
            "The app bundle has no resource directory."
        case let .missingLesson(path):
            "Missing bundled lesson: \(path)"
        case let .unreadableLesson(reason):
            "The bundled lesson cannot be decoded: \(reason)"
        case let .invalidLesson(reason):
            "The bundled lesson is invalid: \(reason)"
        }
    }
}

@MainActor
final class LessonStore: ObservableObject {
    enum ContentSource: Equatable {
        case bundled
        case downloaded

        var label: String {
            switch self {
            case .bundled: "Bundled lesson"
            case .downloaded: "Downloaded lesson"
            }
        }
    }

    enum RefreshState: Equatable {
        case idle
        case refreshing(String)
        case succeeded(String)
        case unavailable(String)
        case failed(String)

        var isRefreshing: Bool {
            if case .refreshing = self { return true }
            return false
        }
    }

    enum State {
        case loading
        case loaded(LessonPackage)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var contentSource: ContentSource = .bundled
    @Published private(set) var refreshState: RefreshState = .idle

    private let loader: LessonPackageLoader
    private let remoteRepository: RemoteContentRepository
    private var hasLoaded = false
    private var hasAttemptedAutomaticRefresh = false

    init(
        loader: LessonPackageLoader = LessonPackageLoader(),
        remoteRepository: RemoteContentRepository = RemoteContentRepository()
    ) {
        self.loader = loader
        self.remoteRepository = remoteRepository
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        if let cachedPackage = try? remoteRepository.loadCachedPackage() {
            contentSource = .downloaded
            state = .loaded(cachedPackage)
            return
        }

        do {
            contentSource = .bundled
            state = .loaded(try loader.load())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refreshAutomaticallyIfNeeded() async {
        guard !hasAttemptedAutomaticRefresh else { return }
        hasAttemptedAutomaticRefresh = true
        await refresh()
    }

    func refresh() async {
        guard !refreshState.isRefreshing else { return }
        refreshState = .refreshing(RemoteContentProgress.checkingLatest.message)

        do {
            let package = try await remoteRepository.refresh(
                progress: { [weak self] progress in
                    await MainActor.run {
                        self?.refreshState = .refreshing(progress.message)
                    }
                }
            )
            contentSource = .downloaded
            state = .loaded(package)
            refreshState = .succeeded(
                "Day \(package.lesson.day) revision \(package.lesson.revision) is ready offline."
            )
        } catch RemoteContentError.noPublishedUpdate {
            refreshState = .unavailable("No published update yet.")
        } catch {
            refreshState = .failed(error.localizedDescription)
        }
    }
}
