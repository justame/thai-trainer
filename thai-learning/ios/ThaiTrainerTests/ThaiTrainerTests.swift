import AVFoundation
import Foundation
import XCTest
@testable import ThaiTrainer

final class ThaiTrainerTests: XCTestCase {
    private let fixtureContentSHA256 = "23fe57fb79ad049e9732b63f37c255c0a1d9f3c4e90d9203240ab4c85b604970"

    func testBundledDayOneLoadsTwentyRealItemsWithoutGeneratedAudio() throws {
        let package = try LessonPackageLoader(bundle: .main).load()

        XCTAssertEqual(package.lesson.lessonID, "day-001")
        XCTAssertEqual(package.lesson.revision, 2)
        XCTAssertEqual(package.lesson.sentences.count, 20)
        XCTAssertEqual(Set(package.lesson.sentences.map(\.id)).count, 20)
        XCTAssertTrue(package.lesson.sentences.allSatisfy {
            !$0.id.isEmpty
                && !$0.promptHebrew.isEmpty
                && !$0.thai.isEmpty
                && !$0.romanization.isEmpty
        })
        XCTAssertEqual(package.lesson.sentences.first?.id, "d001-s01")
        XCTAssertEqual(package.lesson.sentences.last?.id, "d001-s20")
        XCTAssertEqual(package.lesson.sentences.first?.thai, "ช่วยพูดอีกทีได้ไหมครับ")

        let bundledLessonURL = try XCTUnwrap(Bundle.main.resourceURL)
            .appendingPathComponent(LessonPackageLoader.lessonRelativePath)
        XCTAssertEqual(
            try PublisherContentIntegrity.sha256(
                forLessonData: Data(contentsOf: bundledLessonURL)
            ),
            "45e667d6fa54b4f440bb9511dba8d329471d13b567db946422744edbc5bbd365"
        )

        guard case .notGenerated = package.audioState else {
            return XCTFail("Day 1 should load as notGenerated until a manifest exists in the bundle.")
        }
    }

    func testPublisherContentHashMatchesCanonicalPythonFixture() throws {
        let lessonData = try encodedJSON(makeLessonObject())

        XCTAssertEqual(
            try PublisherContentIntegrity.sha256(forLessonData: lessonData),
            fixtureContentSHA256
        )
        XCTAssertTrue(PublisherContentIntegrity.isValidSHA256(fixtureContentSHA256))
        XCTAssertFalse(PublisherContentIntegrity.isValidSHA256(fixtureContentSHA256.uppercased()))
        XCTAssertFalse(PublisherContentIntegrity.isValidSHA256("fixture"))
    }

    @MainActor
    func testFirstLoadKeepsBundledLessonAndAttemptsDefaultRefreshOnce() async throws {
        XCTAssertEqual(
            RemoteContentRepository.defaultBaseURLString,
            "https://justame.github.io/thai-trainer/"
        )

        let fileManager = FileManager.default
        let cacheRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ThaiTrainerStartupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: cacheRoot) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = RemoteContentRepository(session: session, cacheRoot: cacheRoot)
        let latestPath = "/thai-trainer/latest.json"
        StubURLProtocol.configure(
            responses: [latestPath: Data("Not Found".utf8)],
            statusCodes: [latestPath: 404]
        )

        let store = LessonStore(
            loader: LessonPackageLoader(bundle: .main),
            remoteRepository: repository
        )
        store.loadIfNeeded()

        XCTAssertEqual(store.contentSource, .bundled)
        guard case let .loaded(initialPackage) = store.state else {
            return XCTFail("Bundled content must be visible before the network refresh starts.")
        }
        XCTAssertEqual(initialPackage.lesson.lessonID, "day-001")

        await store.refreshAutomaticallyIfNeeded()

        guard case let .loaded(packageAfterRefresh) = store.state else {
            return XCTFail("A missing published index must not hide bundled content.")
        }
        XCTAssertEqual(packageAfterRefresh.lesson.lessonID, "day-001")
        XCTAssertEqual(store.contentSource, .bundled)
        XCTAssertEqual(store.refreshState, .unavailable("No published update yet."))
        XCTAssertEqual(
            StubURLProtocol.recordedRequests().map(\.url?.absoluteString),
            ["https://justame.github.io/thai-trainer/latest.json"]
        )

        await store.refreshAutomaticallyIfNeeded()
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 1)

        await store.refresh()
        XCTAssertEqual(StubURLProtocol.recordedRequests().count, 2)
        guard case .loaded = store.state else {
            return XCTFail("A failed manual refresh must also keep the bundled lesson visible.")
        }
    }

    func testRemoteIntegrityCacheAtomicityPlaybackAndFallback() async throws {
        let fileManager = FileManager.default
        let cacheRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ThaiTrainerRemoteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: cacheRoot) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = RemoteContentRepository(session: session, cacheRoot: cacheRoot)

        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let staleStagingURL = cacheRoot.appendingPathComponent(".staging-stale", isDirectory: true)
        let stagingLinkTarget = cacheRoot.appendingPathComponent("keep-staging-link-target", isDirectory: true)
        let stagingLinkURL = cacheRoot.appendingPathComponent(".staging-link", isDirectory: true)
        try fileManager.createDirectory(at: staleStagingURL, withIntermediateDirectories: false)
        try fileManager.createDirectory(at: stagingLinkTarget, withIntermediateDirectories: false)
        try fileManager.createSymbolicLink(at: stagingLinkURL, withDestinationURL: stagingLinkTarget)

        let wavData = makePCMFixture()
        let trackData = Dictionary(uniqueKeysWithValues: PracticeTrack.allCases.map { track in
            (track.rawValue, wavData)
        })
        let validResponses = try makeResponses(trackData: trackData)
        StubURLProtocol.configure(responses: validResponses)

        let firstPackage = try await repository.refresh(from: "https://content.example/thai")
        XCTAssertEqual(firstPackage.lesson.lessonID, "day-001")
        XCTAssertEqual(firstPackage.lesson.revision, 2)
        XCTAssertEqual(firstPackage.lesson.sentences.count, 20)
        XCTAssertEqual(
            firstPackage.audioState.playableTracks.map(\.id),
            PracticeTrack.allCases.map(\.rawValue)
        )
        XCTAssertTrue(firstPackage.audioState.playableTracks.allSatisfy {
            fileManager.fileExists(atPath: $0.fileURL.path) && $0.fileURL.path.hasPrefix(cacheRoot.path)
        })
        XCTAssertFalse(fileManager.fileExists(atPath: staleStagingURL.path))
        XCTAssertEqual(
            try fileManager.destinationOfSymbolicLink(atPath: stagingLinkURL.path),
            stagingLinkTarget.path
        )

        let latestRequests = StubURLProtocol.recordedRequests().filter {
            $0.url?.lastPathComponent == "latest.json"
        }
        XCTAssertEqual(latestRequests.count, 1)
        XCTAssertEqual(latestRequests.first?.cachePolicy, .reloadIgnoringLocalCacheData)

        let firstTrack = try XCTUnwrap(firstPackage.audioState.playableTracks.first)
        let player = try AVAudioPlayer(data: Data(contentsOf: firstTrack.fileURL))
        XCTAssertGreaterThan(player.duration, 0)
        XCTAssertTrue(player.prepareToPlay())

        let packsURL = cacheRoot.appendingPathComponent("packs", isDirectory: true)
        let firstPackDirectories = try packDirectoryNames(at: packsURL)
        XCTAssertEqual(firstPackDirectories.count, 1)

        StubURLProtocol.configure(responses: validResponses)
        let secondPackage = try await repository.refresh(from: "https://content.example/thai")
        XCTAssertEqual(secondPackage.audioState.playableTracks.count, 4)
        let secondPackDirectories = try packDirectoryNames(at: packsURL)
        XCTAssertEqual(secondPackDirectories.count, 1)
        XCTAssertNotEqual(secondPackDirectories, firstPackDirectories)

        let pointerURL = cacheRoot.appendingPathComponent("current.json", isDirectory: false)
        let currentPointer = try Data(contentsOf: pointerURL)
        let currentPackDirectories = try packDirectoryNames(at: packsURL)

        typealias Corruption = (label: String, mutate: (inout [String: Data]) throws -> Void)
        let corruptions: [Corruption] = [
            ("latest missing required hash", { responses in
                try self.mutateJSON(in: &responses, path: "/thai/latest.json") {
                    $0.removeValue(forKey: "content_sha256")
                }
            }),
            ("latest hash has invalid format", { responses in
                try self.mutateJSON(in: &responses, path: "/thai/latest.json") {
                    $0["content_sha256"] = self.fixtureContentSHA256.uppercased()
                }
            }),
            ("latest hash does not match lesson", { responses in
                try self.mutateJSON(in: &responses, path: "/thai/latest.json") {
                    $0["content_sha256"] = String(repeating: "0", count: 64)
                }
            }),
            ("manifest missing required hash", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) {
                    $0.removeValue(forKey: "content_sha256")
                }
            }),
            ("manifest hash mismatch", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) {
                    $0["content_sha256"] = String(repeating: "0", count: 64)
                }
            }),
            ("track missing required hash", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) { object in
                    var tracks = object["tracks"] as! [[String: Any]]
                    tracks[0].removeValue(forKey: "content_sha256")
                    object["tracks"] = tracks
                }
            }),
            ("track hash mismatch", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/audio-manifest.json"
                ) { object in
                    var tracks = object["tracks"] as! [[String: Any]]
                    tracks[0]["content_sha256"] = String(repeating: "0", count: 64)
                    object["tracks"] = tracks
                }
            }),
            ("sentence romanization is empty", { responses in
                try self.mutateJSON(
                    in: &responses,
                    path: "/thai/packs/day-001/r2/lesson.json"
                ) { object in
                    var sentences = object["sentences"] as! [[String: Any]]
                    sentences[0]["romanization"] = "  "
                    object["sentences"] = sentences
                }
            }),
            ("track byte count mismatch", { responses in
                responses["/thai/packs/day-001/r2/scenario.mp3"] = Data("wrong-size".utf8)
            }),
        ]

        for corruption in corruptions {
            var responses = validResponses
            try corruption.mutate(&responses)
            StubURLProtocol.configure(responses: responses)

            do {
                _ = try await repository.refresh(from: "https://content.example/thai")
                XCTFail("\(corruption.label) must be rejected")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty, corruption.label)
            }

            XCTAssertEqual(try Data(contentsOf: pointerURL), currentPointer, corruption.label)
            XCTAssertEqual(
                try packDirectoryNames(at: packsURL),
                currentPackDirectories,
                corruption.label
            )
            XCTAssertEqual(
                try repository.loadCachedPackage().audioState.playableTracks.count,
                4,
                corruption.label
            )
        }

        let cachedPackage = try repository.loadCachedPackage()
        let cachedTrack = try XCTUnwrap(cachedPackage.audioState.playableTracks.first)
        let revisionDirectory = cachedTrack.fileURL.deletingLastPathComponent()
        let manifestURL = revisionDirectory.appendingPathComponent(
            LessonPackageLoader.manifestFilename,
            isDirectory: false
        )
        let savedManifest = try Data(contentsOf: manifestURL)

        try fileManager.removeItem(at: manifestURL)
        XCTAssertThrowsError(try repository.loadCachedPackage())
        try savedManifest.write(to: manifestURL, options: .atomic)

        try fileManager.removeItem(at: cachedTrack.fileURL)
        XCTAssertThrowsError(try repository.loadCachedPackage())

        await MainActor.run {
            let store = LessonStore(
                loader: LessonPackageLoader(bundle: .main),
                remoteRepository: repository
            )
            store.loadIfNeeded()
            XCTAssertEqual(store.contentSource, .bundled)
            guard case let .loaded(package) = store.state else {
                return XCTFail("An invalid cache must fall back to the bundled lesson.")
            }
            XCTAssertEqual(package.lesson.lessonID, "day-001")
            XCTAssertEqual(package.lesson.sentences.count, 20)
        }
    }

    private func makeResponses(trackData: [String: Data]) throws -> [String: Data] {
        let manifestTracks: [[String: Any]] = PracticeTrack.allCases.map { track in
            [
                "lesson_id": "day-001",
                "revision": 2,
                "track_id": track.rawValue,
                "file": "\(track.rawValue).mp3",
                "bytes": trackData[track.rawValue]!.count,
                "content_sha256": fixtureContentSHA256,
            ]
        }
        let manifest: [String: Any] = [
            "schema_version": 1,
            "lesson_id": "day-001",
            "revision": 2,
            "content_sha256": fixtureContentSHA256,
            "tracks": manifestTracks,
        ]
        let latest: [String: Any] = [
            "schema_version": 1,
            "lesson_id": "day-001",
            "revision": 2,
            "content_sha256": fixtureContentSHA256,
            "lesson_path": "packs/day-001/r2/lesson.json",
            "audio_manifest_path": "packs/day-001/r2/audio-manifest.json",
        ]

        var responses: [String: Data] = [
            "/thai/latest.json": try encodedJSON(latest),
            "/thai/packs/day-001/r2/lesson.json": try encodedJSON(makeLessonObject()),
            "/thai/packs/day-001/r2/audio-manifest.json": try encodedJSON(manifest),
        ]
        for (trackID, data) in trackData {
            responses["/thai/packs/day-001/r2/\(trackID).mp3"] = data
        }
        return responses
    }

    private func makeLessonObject() -> [String: Any] {
        let sentenceIDs = (1...20).map { String(format: "fixture-s%02d", $0) }
        let sentences: [[String: Any]] = sentenceIDs.enumerated().map { offset, sentenceID in
            [
                "id": sentenceID,
                "prompt_he": "Prompt \(offset + 1)",
                "thai": "ไทย \(offset + 1)",
                "romanization": "thai \(offset + 1)",
                "review_status": "approved",
            ]
        }
        let tracks: [[String: Any]] = PracticeTrack.allCases.map { track in
            ["id": track.rawValue, "sequence": sentenceIDs]
        }
        return [
            "schema_version": 1,
            "lesson_id": "day-001",
            "revision": 2,
            "day": 1,
            "theme": "Remote fixture",
            "status": "approved",
            "voices": [
                "provider": "azure_speech",
                "thai": "th-TH-PremwadeeNeural",
                "hebrew": "he-IL-HilaNeural",
            ],
            "sentences": sentences,
            "audio_program": [
                "normal_speed_only": true,
                "tracks": tracks,
            ],
        ]
    }

    private func makePCMFixture() -> Data {
        let sampleRate: UInt32 = 8_000
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let sampleCount = 800
        let sampleData = Data(repeating: 0, count: sampleCount * Int(bitsPerSample / 8))

        var wav = Data("RIFF".utf8)
        appendLittleEndian(UInt32(36 + sampleData.count), to: &wav)
        wav.append(Data("WAVEfmt ".utf8))
        appendLittleEndian(UInt32(16), to: &wav)
        appendLittleEndian(UInt16(1), to: &wav)
        appendLittleEndian(channelCount, to: &wav)
        appendLittleEndian(sampleRate, to: &wav)
        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        appendLittleEndian(byteRate, to: &wav)
        appendLittleEndian(channelCount * (bitsPerSample / 8), to: &wav)
        appendLittleEndian(bitsPerSample, to: &wav)
        wav.append(Data("data".utf8))
        appendLittleEndian(UInt32(sampleData.count), to: &wav)
        wav.append(sampleData)
        return wav
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func encodedJSON(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func mutateJSON(
        in responses: inout [String: Data],
        path: String,
        mutation: (inout [String: Any]) -> Void
    ) throws {
        let data = try XCTUnwrap(responses[path])
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        mutation(&object)
        responses[path] = try encodedJSON(object)
    }

    private func packDirectoryNames(at packsURL: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: packsURL.path))
    }
}

private final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseData: [String: Data] = [:]
    private static var responseStatusCodes: [String: Int] = [:]
    private static var requests: [URLRequest] = []

    static func configure(
        responses: [String: Data],
        statusCodes: [String: Int] = [:]
    ) {
        lock.lock()
        responseData = responses
        responseStatusCodes = statusCodes
        requests = []
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let path = request.url?.path
        let data = path.flatMap { Self.responseData[$0] }
        let statusCode = path.flatMap { Self.responseStatusCodes[$0] } ?? 200
        Self.lock.unlock()

        guard let url = request.url,
              let data,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/octet-stream"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
