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
        try load(relativePath: Self.lessonRelativePath)
    }

    func loadAll() throws -> [LessonPackage] {
        guard let resourceRoot else {
            throw LessonPackageLoadingError.missingResourceRoot
        }

        let daysURL = resourceRoot.appendingPathComponent("days", isDirectory: true)
        let lessonURLs = try fileManager.contentsOfDirectory(
            at: daysURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !lessonURLs.isEmpty else {
            throw LessonPackageLoadingError.missingLesson("days/*.json")
        }
        return try lessonURLs.map {
            try load(relativePath: "days/\($0.lastPathComponent)")
        }
    }

    private func load(relativePath: String) throws -> LessonPackage {
        guard let resourceRoot else {
            throw LessonPackageLoadingError.missingResourceRoot
        }

        let lessonURL = resourceRoot.appendingPathComponent(relativePath)
        guard isRegularFile(at: lessonURL) else {
            throw LessonPackageLoadingError.missingLesson(relativePath)
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
        let contentSHA256: String
        do {
            contentSHA256 = try PublisherContentIntegrity.sha256(forLessonData: lessonData)
        } catch {
            throw LessonPackageLoadingError.invalidLesson(
                "The lesson cannot be hashed using the publisher content contract."
            )
        }
        let audioState = validateAudio(
            for: lesson,
            contentSHA256: contentSHA256,
            resourceRoot: resourceRoot
        )
        return LessonPackage(
            lesson: lesson,
            contentSHA256: contentSHA256,
            audioState: audioState,
            resourceRootURL: resourceRoot
        )
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
        contentSHA256: String,
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
        guard PublisherContentIntegrity.isValidSHA256(manifest.contentSHA256),
              manifest.contentSHA256 == contentSHA256 else {
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
                  manifestTrack.contentSHA256 == contentSHA256,
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

    struct LibraryItem: Identifiable, Equatable {
        let package: LessonPackage
        let source: ContentSource

        var id: String { package.lesson.lessonID }
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var contentSource: ContentSource = .bundled
    @Published private(set) var refreshState: RefreshState = .idle
    @Published private(set) var library: [LibraryItem] = []
    @Published private(set) var reviewCatalog: [PracticeQueueItem] = []

    private let loader: LessonPackageLoader
    private let remoteRepository: RemoteContentRepository
    private let userDefaults: UserDefaults
    private var hasLoaded = false
    private var hasAttemptedAutomaticRefresh = false
    private static let selectedLessonKey = "thai-trainer.selected-lesson-id.v1"

    init(
        loader: LessonPackageLoader = LessonPackageLoader(),
        remoteRepository: RemoteContentRepository = RemoteContentRepository(),
        userDefaults: UserDefaults = .standard
    ) {
        self.loader = loader
        self.remoteRepository = remoteRepository
        self.userDefaults = userDefaults
    }

    var selectedLessonID: String? {
        guard case let .loaded(package) = state else { return nil }
        return package.lesson.lessonID
    }

    var selectedLessonPosition: Int? {
        guard let selectedLessonID,
              let index = library.firstIndex(where: { $0.id == selectedLessonID }) else {
            return nil
        }
        return index + 1
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true

        do {
            let bundled = try loader.loadAll().map {
                LibraryItem(package: $0, source: .bundled)
            }
            let downloaded = remoteRepository.loadCachedPackages().map {
                LibraryItem(package: $0, source: .downloaded)
            }
            library = mergedLibrary(bundled + downloaded)
            rebuildReviewCatalog()
            guard !library.isEmpty else {
                throw LessonPackageLoadingError.missingLesson("days/*.json")
            }

            let savedID = userDefaults.string(forKey: Self.selectedLessonKey)
            let selected = library.first(where: { $0.id == savedID }) ?? library.last!
            show(selected, persist: false)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func selectLesson(id: String) {
        guard let item = library.first(where: { $0.id == id }) else { return }
        show(item, persist: true)
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
            library = mergedLibrary(
                library + [LibraryItem(package: package, source: .downloaded)]
            )
            rebuildReviewCatalog()
            if let item = library.first(where: { $0.id == package.lesson.lessonID }) {
                show(item, persist: true)
            }
            refreshState = .succeeded(
                "Day \(package.lesson.day) revision \(package.lesson.revision) is ready offline."
            )
        } catch RemoteContentError.noPublishedUpdate {
            refreshState = .unavailable("No published update yet.")
        } catch {
            refreshState = .failed(error.localizedDescription)
        }
    }

    private func show(_ item: LibraryItem, persist: Bool) {
        contentSource = item.source
        state = .loaded(item.package)
        if persist {
            userDefaults.set(item.id, forKey: Self.selectedLessonKey)
        }
    }

    private func mergedLibrary(_ items: [LibraryItem]) -> [LibraryItem] {
        var byLessonID: [String: LibraryItem] = [:]
        for item in items {
            guard let existing = byLessonID[item.id] else {
                byLessonID[item.id] = item
                continue
            }
            if item.package.lesson.revision > existing.package.lesson.revision
                || (item.package.lesson.revision == existing.package.lesson.revision
                    && item.source == .downloaded) {
                byLessonID[item.id] = item
            }
        }
        return byLessonID.values.sorted {
            if $0.package.lesson.day == $1.package.lesson.day {
                return $0.package.lesson.lessonID < $1.package.lesson.lessonID
            }
            return $0.package.lesson.day < $1.package.lesson.day
        }
    }

    private func rebuildReviewCatalog() {
        reviewCatalog = library.flatMap { item in
            (try? PracticeQueueItem.items(for: item.package)) ?? []
        }
    }
}
