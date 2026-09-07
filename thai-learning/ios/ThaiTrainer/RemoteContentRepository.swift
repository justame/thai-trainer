import CryptoKit
import Foundation

struct RemoteContentIndex: Decodable, Sendable {
    let schemaVersion: Int
    let lessonID: String
    let revision: Int
    let contentSHA256: String
    let lessonPath: String
    let audioManifestPath: String
    let practiceManifestPath: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case lessonID = "lesson_id"
        case revision
        case contentSHA256 = "content_sha256"
        case lessonPath = "lesson_path"
        case audioManifestPath = "audio_manifest_path"
        case practiceManifestPath = "practice_manifest_path"
    }
}

enum RemoteContentProgress: Equatable, Sendable {
    case checkingLatest
    case downloadingLesson
    case downloadingManifest
    case downloadingAudio(current: Int, total: Int)
    case downloadingPracticeManifest
    case downloadingPracticeAudio(current: Int, total: Int)
    case validating

    var message: String {
        switch self {
        case .checkingLatest:
            "Checking for the latest lesson…"
        case .downloadingLesson:
            "Downloading the lesson…"
        case .downloadingManifest:
            "Downloading the audio manifest…"
        case let .downloadingAudio(current, total):
            "Downloading audio \(current) of \(total)…"
        case .downloadingPracticeManifest:
            "Downloading practice audio index…"
        case let .downloadingPracticeAudio(current, total):
            "Downloading practice clips \(current) of \(total)…"
        case .validating:
            "Validating the downloaded pack…"
        }
    }
}

struct RemoteContentRepository {
    static let defaultBaseURLString = "https://justame.github.io/thai-trainer/"

    private let session: URLSession
    private let cache: RemoteContentCache
    private let decoder = JSONDecoder()

    init(
        session: URLSession = .shared,
        cacheRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.session = session
        cache = RemoteContentCache(rootURL: cacheRoot, fileManager: fileManager)
    }

    func loadCachedPackage() throws -> LessonPackage {
        try cache.loadCurrentPackage()
    }

    func loadCachedPackages() -> [LessonPackage] {
        cache.loadAllPackages()
    }

    func refresh(
        progress: (RemoteContentProgress) async -> Void = { _ in }
    ) async throws -> LessonPackage {
        try await refresh(from: Self.defaultBaseURLString, progress: progress)
    }

    func refresh(
        from baseURLString: String,
        progress: (RemoteContentProgress) async -> Void = { _ in }
    ) async throws -> LessonPackage {
        let baseURL = try RemoteContentURLValidator.baseURL(from: baseURLString)

        await progress(.checkingLatest)
        let indexURL = baseURL.appendingPathComponent("latest.json", isDirectory: false)
        let indexRequest = URLRequest(
            url: indexURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        let indexData = try await fetch(indexRequest)
        let index: RemoteContentIndex
        do {
            index = try decoder.decode(RemoteContentIndex.self, from: indexData)
        } catch {
            throw RemoteContentError.invalidLatest("latest.json cannot be decoded")
        }
        try validate(index)

        let lessonURL = try RemoteContentURLValidator.resolve(
            relativePath: index.lessonPath,
            under: baseURL
        )
        let manifestURL = try RemoteContentURLValidator.resolve(
            relativePath: index.audioManifestPath,
            under: baseURL
        )
        let practiceManifestURL = try index.practiceManifestPath.map {
            try RemoteContentURLValidator.resolve(relativePath: $0, under: baseURL)
        }

        await progress(.downloadingLesson)
        let lessonData = try await fetch(lessonURL)
        let lessonContentSHA256: String
        do {
            lessonContentSHA256 = try PublisherContentIntegrity.sha256(forLessonData: lessonData)
        } catch {
            throw RemoteContentError.invalidPack(
                "The lesson cannot be hashed using the publisher content contract."
            )
        }
        guard lessonContentSHA256 == index.contentSHA256 else {
            throw RemoteContentError.invalidPack(
                "The lesson content hash does not match latest.json."
            )
        }
        let lesson: Lesson
        do {
            lesson = try decoder.decode(Lesson.self, from: lessonData)
        } catch {
            throw RemoteContentError.invalidPack("The lesson JSON cannot be decoded.")
        }
        try validate(lesson, matches: index)

        await progress(.downloadingManifest)
        let manifestData = try await fetch(manifestURL)
        let manifest: AudioManifest
        do {
            manifest = try decoder.decode(AudioManifest.self, from: manifestData)
        } catch {
            throw RemoteContentError.invalidPack("The audio manifest cannot be decoded.")
        }
        let orderedTracks = try validate(
            manifest,
            lesson: lesson,
            index: index,
            lessonContentSHA256: lessonContentSHA256
        )

        var practiceManifestData: Data?
        var practiceClips: [PracticeAudioClipManifest] = []
        if let practiceManifestURL {
            await progress(.downloadingPracticeManifest)
            let downloadedManifestData = try await fetch(practiceManifestURL)
            let practiceManifest: PracticeAudioManifest
            do {
                practiceManifest = try decoder.decode(
                    PracticeAudioManifest.self,
                    from: downloadedManifestData
                )
            } catch {
                throw RemoteContentError.invalidPack(
                    "The practice audio manifest cannot be decoded."
                )
            }
            practiceClips = try validate(
                practiceManifest,
                lesson: lesson,
                index: index,
                lessonContentSHA256: lessonContentSHA256
            )
            practiceManifestData = downloadedManifestData
        }

        let stagingURL = try cache.makeStagingDirectory()
        var stagingStillExists = true
        defer {
            if stagingStillExists {
                try? cache.removeItem(at: stagingURL)
            }
        }

        let stagedLessonURL = stagingURL.appendingPathComponent(
            LessonPackageLoader.lessonRelativePath,
            isDirectory: false
        )
        let stagedRevisionURL = stagingURL
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent(lesson.lessonID, isDirectory: true)
            .appendingPathComponent("r\(lesson.revision)", isDirectory: true)
        try cache.createDirectory(at: stagedLessonURL.deletingLastPathComponent())
        try cache.createDirectory(at: stagedRevisionURL)
        try lessonData.write(to: stagedLessonURL, options: .atomic)
        try manifestData.write(
            to: stagedRevisionURL.appendingPathComponent(LessonPackageLoader.manifestFilename),
            options: .atomic
        )

        let remoteAudioDirectory = manifestURL.deletingLastPathComponent()
        for (offset, track) in orderedTracks.enumerated() {
            await progress(.downloadingAudio(current: offset + 1, total: orderedTracks.count))
            let trackURL = remoteAudioDirectory.appendingPathComponent(track.file, isDirectory: false)
            let trackData = try await fetch(trackURL)
            guard Int64(trackData.count) == track.byteCount else {
                throw RemoteContentError.invalidPack(
                    "Track \(track.trackID) does not match its declared byte count."
                )
            }
            try trackData.write(
                to: stagedRevisionURL.appendingPathComponent(track.file, isDirectory: false),
                options: .atomic
            )
        }

        if let practiceManifestURL, let practiceManifestData {
            let stagedPracticeURL = stagingURL
                .appendingPathComponent("practice", isDirectory: true)
                .appendingPathComponent(lesson.lessonID, isDirectory: true)
                .appendingPathComponent("r\(lesson.revision)", isDirectory: true)
            try cache.createDirectory(at: stagedPracticeURL)
            try practiceManifestData.write(
                to: stagedPracticeURL.appendingPathComponent("practice-manifest.json"),
                options: .atomic
            )
            let remotePracticeDirectory = practiceManifestURL.deletingLastPathComponent()
            for (offset, clip) in practiceClips.enumerated() {
                await progress(
                    .downloadingPracticeAudio(current: offset + 1, total: practiceClips.count)
                )
                let clipData = try await fetch(
                    remotePracticeDirectory.appendingPathComponent(clip.file)
                )
                guard Int64(clipData.count) == clip.byteCount else {
                    throw RemoteContentError.invalidPack(
                        "Practice clip \(clip.file) does not match its declared byte count."
                    )
                }
                let digest = SHA256.hash(data: clipData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                guard digest == clip.sha256 else {
                    throw RemoteContentError.invalidPack(
                        "Practice clip \(clip.file) failed integrity checking."
                    )
                }
                try clipData.write(
                    to: stagedPracticeURL.appendingPathComponent(clip.file),
                    options: .atomic
                )
            }
        }

        await progress(.validating)
        let stagedPackage = try LessonPackageLoader(resourceRoot: stagingURL).load()
        guard case let .ready(stagedTracks) = stagedPackage.audioState,
              stagedTracks.count == PracticeTrack.allCases.count else {
            throw RemoteContentError.invalidPack("The staged audio pack did not pass validation.")
        }
        if practiceManifestData != nil {
            do {
                _ = try PracticeAudioPackageLoader(resourceRoot: stagingURL).load(for: lesson)
            } catch {
                throw RemoteContentError.invalidPack(
                    "The staged practice audio did not pass validation."
                )
            }
        }

        let committedURL = try cache.commit(
            stagingURL: stagingURL,
            lessonID: lesson.lessonID,
            revision: lesson.revision,
            contentSHA256: lessonContentSHA256
        )
        stagingStillExists = false
        return try LessonPackageLoader(resourceRoot: committedURL).load()
    }

    private func fetch(_ url: URL) async throws -> Data {
        try await fetch(URLRequest(url: url))
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RemoteContentError.network(
                "Could not download \(request.url?.lastPathComponent ?? "content")."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteContentError.network(
                "The server rejected \(request.url?.lastPathComponent ?? "content")."
            )
        }
        if httpResponse.statusCode == 404,
           request.url?.lastPathComponent == "latest.json" {
            throw RemoteContentError.noPublishedUpdate
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RemoteContentError.network(
                "The server rejected \(request.url?.lastPathComponent ?? "content")."
            )
        }
        guard !data.isEmpty else {
            throw RemoteContentError.network(
                "The server returned an empty \(request.url?.lastPathComponent ?? "content")."
            )
        }
        return data
    }

    private func validate(_ index: RemoteContentIndex) throws {
        guard index.schemaVersion == 1 else {
            throw RemoteContentError.invalidLatest("schema_version must be 1")
        }
        guard RemoteContentURLValidator.isSafePathComponent(index.lessonID) else {
            throw RemoteContentError.invalidLatest("lesson_id is invalid")
        }
        guard index.revision > 0 else {
            throw RemoteContentError.invalidLatest("revision must be positive")
        }
        guard PublisherContentIntegrity.isValidSHA256(index.contentSHA256) else {
            throw RemoteContentError.invalidLatest(
                "content_sha256 must be 64 lowercase hexadecimal characters"
            )
        }
        _ = try RemoteContentURLValidator.validate(relativePath: index.lessonPath)
        _ = try RemoteContentURLValidator.validate(relativePath: index.audioManifestPath)
        if let practiceManifestPath = index.practiceManifestPath {
            _ = try RemoteContentURLValidator.validate(relativePath: practiceManifestPath)
        }
    }

    private func validate(_ lesson: Lesson, matches index: RemoteContentIndex) throws {
        guard lesson.schemaVersion == 1 else {
            throw RemoteContentError.invalidPack("The lesson schema is unsupported.")
        }
        guard lesson.lessonID == index.lessonID, lesson.revision == index.revision else {
            throw RemoteContentError.invalidPack("The lesson does not match latest.json.")
        }
        if let violation = LessonContentContract.violation(in: lesson) {
            throw RemoteContentError.invalidPack(violation)
        }
        guard lesson.status == "approved",
              lesson.sentences.allSatisfy({ $0.reviewStatus == "approved" }) else {
            throw RemoteContentError.invalidPack(
                "The remote lesson and all 20 sentences must be approved."
            )
        }
        if lesson.audioProgram.practiceVariations != nil,
           index.practiceManifestPath == nil {
            throw RemoteContentError.invalidPack(
                "This lesson needs its configurable practice audio package."
            )
        }

        let expectedIDs = Set(PracticeTrack.allCases.map(\.rawValue))
        let actualIDs = lesson.audioProgram.tracks.map(\.id)
        guard actualIDs.count == expectedIDs.count,
              Set(actualIDs).count == actualIDs.count,
              Set(actualIDs) == expectedIDs else {
            throw RemoteContentError.invalidPack("The lesson must define the exact four known tracks.")
        }
    }

    private func validate(
        _ manifest: AudioManifest,
        lesson: Lesson,
        index: RemoteContentIndex,
        lessonContentSHA256: String
    ) throws -> [AudioManifestTrack] {
        guard manifest.schemaVersion == 1 else {
            throw RemoteContentError.invalidPack("The audio manifest schema is unsupported.")
        }
        guard manifest.lessonID == index.lessonID,
              manifest.lessonID == lesson.lessonID,
              manifest.revision == index.revision,
              manifest.revision == lesson.revision else {
            throw RemoteContentError.invalidPack("The audio manifest targets another lesson revision.")
        }
        guard PublisherContentIntegrity.isValidSHA256(manifest.contentSHA256),
              manifest.contentSHA256 == index.contentSHA256,
              manifest.contentSHA256 == lessonContentSHA256 else {
            throw RemoteContentError.invalidPack(
                "The audio manifest content hash does not match the lesson and latest.json."
            )
        }

        let expectedIDs = PracticeTrack.allCases.map(\.rawValue)
        let actualIDs = manifest.tracks.map(\.trackID)
        guard actualIDs.count == expectedIDs.count,
              Set(actualIDs).count == actualIDs.count,
              Set(actualIDs) == Set(expectedIDs) else {
            throw RemoteContentError.invalidPack("The manifest must contain the exact four known tracks.")
        }

        let byID = Dictionary(uniqueKeysWithValues: manifest.tracks.map { ($0.trackID, $0) })
        return try expectedIDs.map { trackID in
            guard let track = byID[trackID] else {
                throw RemoteContentError.invalidPack("The manifest is missing \(trackID).")
            }
            guard track.lessonID == lesson.lessonID, track.revision == lesson.revision else {
                throw RemoteContentError.invalidPack("Track \(trackID) targets another lesson revision.")
            }
            guard track.file == "\(trackID).mp3" else {
                throw RemoteContentError.invalidPack("Track \(trackID) has an unexpected filename.")
            }
            guard track.byteCount > 0 else {
                throw RemoteContentError.invalidPack("Track \(trackID) declares an empty file.")
            }
            guard PublisherContentIntegrity.isValidSHA256(track.contentSHA256),
                  track.contentSHA256 == index.contentSHA256,
                  track.contentSHA256 == manifest.contentSHA256,
                  track.contentSHA256 == lessonContentSHA256 else {
                throw RemoteContentError.invalidPack(
                    "Track \(trackID) content hash does not match the lesson metadata."
                )
            }
            return track
        }
    }

    private func validate(
        _ manifest: PracticeAudioManifest,
        lesson: Lesson,
        index: RemoteContentIndex,
        lessonContentSHA256: String
    ) throws -> [PracticeAudioClipManifest] {
        guard [1, 2].contains(manifest.schemaVersion),
              manifest.lessonID == lesson.lessonID,
              manifest.lessonID == index.lessonID,
              manifest.revision == lesson.revision,
              manifest.revision == index.revision,
              manifest.sampleRateHertz == 24_000,
              manifest.contentSHA256 == lessonContentSHA256,
              manifest.contentSHA256 == index.contentSHA256 else {
            throw RemoteContentError.invalidPack(
                "The practice manifest does not match the approved lesson."
            )
        }

        let expectedIDs = lesson.sentences.map(\.id)
        let actualIDs = manifest.sentences.map(\.sentenceID)
        guard actualIDs == expectedIDs, Set(actualIDs).count == expectedIDs.count else {
            throw RemoteContentError.invalidPack(
                "The practice audio order does not match the approved lesson."
            )
        }

        var clips: [PracticeAudioClipManifest] = []
        for sentence in manifest.sentences {
            clips.append(sentence.core.hebrew)
            clips.append(sentence.core.thai)
            if manifest.schemaVersion == 2, sentence.variations.isEmpty {
                throw RemoteContentError.invalidPack(
                    "Every sentence needs at least one related practice version."
                )
            }
            for variation in sentence.variations {
                clips.append(variation.hebrew)
                clips.append(variation.thai)
            }
        }

        guard Set(clips.map(\.file)).count == clips.count else {
            throw RemoteContentError.invalidPack("Practice clip filenames must be unique.")
        }
        for clip in clips {
            guard RemoteContentURLValidator.isSafePathComponent(clip.file),
                  clip.file.hasSuffix(".wav"),
                  clip.byteCount > 44,
                  PublisherContentIntegrity.isValidSHA256(clip.sha256) else {
                throw RemoteContentError.invalidPack(
                    "The practice manifest contains an invalid clip declaration."
                )
            }
        }
        return clips
    }
}

private struct RemoteContentCache {
    private struct Pointer: Codable {
        let schemaVersion: Int
        let directory: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case directory
        }
    }

    private let configuredRootURL: URL?
    private let fileManager: FileManager

    init(rootURL: URL?, fileManager: FileManager) {
        configuredRootURL = rootURL
        self.fileManager = fileManager
    }

    func loadCurrentPackage() throws -> LessonPackage {
        let rootURL = try resolvedRootURL()
        let pointerURL = rootURL.appendingPathComponent("current.json", isDirectory: false)
        let pointer: Pointer
        do {
            pointer = try JSONDecoder().decode(Pointer.self, from: Data(contentsOf: pointerURL))
        } catch {
            throw RemoteContentError.noCachedPack
        }
        guard pointer.schemaVersion == 1,
              RemoteContentURLValidator.isSafePathComponent(pointer.directory) else {
            throw RemoteContentError.noCachedPack
        }

        let packageURL = rootURL
            .appendingPathComponent("packs", isDirectory: true)
            .appendingPathComponent(pointer.directory, isDirectory: true)
        guard let package = loadValidPackage(at: packageURL) else {
            throw RemoteContentError.noCachedPack
        }
        return package
    }

    func loadAllPackages() -> [LessonPackage] {
        guard let rootURL = try? resolvedRootURL() else { return [] }
        let packsURL = rootURL.appendingPathComponent("packs", isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: packsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var newestByLessonID: [String: LessonPackage] = [:]
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let package = loadValidPackage(at: entry) else {
                continue
            }
            let lessonID = package.lesson.lessonID
            if let existing = newestByLessonID[lessonID],
               existing.lesson.revision >= package.lesson.revision {
                continue
            }
            newestByLessonID[lessonID] = package
        }
        return newestByLessonID.values.sorted {
            if $0.lesson.day == $1.lesson.day {
                return $0.lesson.lessonID < $1.lesson.lessonID
            }
            return $0.lesson.day < $1.lesson.day
        }
    }

    func makeStagingDirectory() throws -> URL {
        let rootURL = try resolvedRootURL()
        try createDirectory(at: rootURL)
        pruneStagingDirectories(in: rootURL)
        let stagingURL = rootURL.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
        return stagingURL
    }

    func commit(
        stagingURL: URL,
        lessonID: String,
        revision: Int,
        contentSHA256: String
    ) throws -> URL {
        let rootURL = try resolvedRootURL()
        let packsURL = rootURL.appendingPathComponent("packs", isDirectory: true)
        try createDirectory(at: packsURL)

        let directory = "\(lessonID)-r\(revision)-\(contentSHA256.prefix(12))"
        let committedURL = packsURL.appendingPathComponent(directory, isDirectory: true)
        if fileManager.fileExists(atPath: committedURL.path) {
            guard loadValidPackage(at: committedURL) != nil else {
                throw RemoteContentError.cache("The existing offline pack is invalid.")
            }
            try removeItem(at: stagingURL)
            try writePointer(directory: directory, rootURL: rootURL)
            pruneSupersededLessonDirectories(
                in: packsURL,
                lessonID: lessonID,
                preserving: committedURL
            )
            return committedURL
        }

        do {
            try fileManager.moveItem(at: stagingURL, to: committedURL)
            try writePointer(directory: directory, rootURL: rootURL)
        } catch {
            try? fileManager.removeItem(at: committedURL)
            throw RemoteContentError.cache("The downloaded pack could not be saved.")
        }
        pruneSupersededLessonDirectories(
            in: packsURL,
            lessonID: lessonID,
            preserving: committedURL
        )
        return committedURL
    }

    func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func writePointer(directory: String, rootURL: URL) throws {
        let pointer = Pointer(schemaVersion: 1, directory: directory)
        let pointerData = try JSONEncoder().encode(pointer)
        try pointerData.write(
            to: rootURL.appendingPathComponent("current.json", isDirectory: false),
            options: .atomic
        )
    }

    private func loadValidPackage(at packageURL: URL) -> LessonPackage? {
        guard let package = try? LessonPackageLoader(
            resourceRoot: packageURL,
            fileManager: fileManager
        ).load(),
        case let .ready(tracks) = package.audioState,
        tracks.count == PracticeTrack.allCases.count,
        Set(tracks.map(\.id)) == Set(PracticeTrack.allCases.map(\.rawValue)) else {
            return nil
        }
        return package
    }

    private func pruneSupersededLessonDirectories(
        in packsURL: URL,
        lessonID: String,
        preserving currentURL: URL
    ) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: packsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let lessonPrefix = "\(lessonID)-r"
        for entry in entries
        where entry.standardizedFileURL != currentURL.standardizedFileURL
            && entry.lastPathComponent.hasPrefix(lessonPrefix) {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    private func pruneStagingDirectories(in rootURL: URL) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return
        }

        for entry in entries where entry.lastPathComponent.hasPrefix(".staging-") {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                continue
            }
            try? fileManager.removeItem(at: entry)
        }
    }

    private func resolvedRootURL() throws -> URL {
        if let configuredRootURL {
            return configuredRootURL
        }
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw RemoteContentError.cache("Application Support is unavailable.")
        }
        return applicationSupport.appendingPathComponent("ThaiTrainerContent", isDirectory: true)
    }
}

private enum RemoteContentURLValidator {
    static func baseURL(from input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw RemoteContentError.invalidBaseURL
        }

        let isHTTPS = scheme == "https"
        #if DEBUG
        let isLocalHTTP = scheme == "http" && (
            host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
        )
        #else
        let isLocalHTTP = false
        #endif
        guard isHTTPS || isLocalHTTP else {
            throw RemoteContentError.insecureBaseURL
        }

        components.scheme = scheme
        guard var url = components.url else {
            throw RemoteContentError.invalidBaseURL
        }
        if !url.path.hasSuffix("/") {
            url.appendPathComponent("", isDirectory: true)
        }
        return url
    }

    static func resolve(relativePath: String, under baseURL: URL) throws -> URL {
        let components = try validate(relativePath: relativePath)
        return components.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }
    }

    static func validate(relativePath: String) throws -> [String] {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains("?"),
              !relativePath.contains("#"),
              !relativePath.contains("%") else {
            throw RemoteContentError.invalidLatest("A content path is not a safe relative URL.")
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, components.allSatisfy(isSafePathComponent) else {
            throw RemoteContentError.invalidLatest("A content path is not a safe relative URL.")
        }
        return components
    }

    static func isSafePathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

enum RemoteContentError: LocalizedError, Equatable {
    case invalidBaseURL
    case insecureBaseURL
    case noPublishedUpdate
    case invalidLatest(String)
    case invalidPack(String)
    case network(String)
    case cache(String)
    case noCachedPack

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter a complete content URL, such as https://example.com/thai/."
        case .insecureBaseURL:
            "Content URLs must use HTTPS. Debug builds also allow HTTP on localhost."
        case .noPublishedUpdate:
            "No published update is available yet."
        case let .invalidLatest(reason):
            "The content index is invalid: \(reason)."
        case let .invalidPack(reason):
            "The downloaded pack is invalid: \(reason)"
        case let .network(message):
            message
        case let .cache(message):
            message
        case .noCachedPack:
            "No downloaded lesson is cached yet."
        }
    }
}
