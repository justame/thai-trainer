import Combine
import Foundation

enum LearningProgressStoreError: LocalizedError {
    case unsupportedSchema
    case invalidTimezone
    case duplicateEvent
    case invalidPhraseIdentity

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            "Learning progress uses an unsupported schema."
        case .invalidTimezone:
            "Learning progress is not anchored to Asia/Bangkok."
        case .duplicateEvent:
            "Learning progress contains a duplicate event."
        case .invalidPhraseIdentity:
            "Learning progress contains an invalid phrase identity."
        }
    }
}
@MainActor
final class LearningProgressStore: ObservableObject {
    @Published private(set) var events: [ReviewEvent] = []
    @Published private(set) var persistenceError: String?

    let fileURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    convenience init() {
        self.init(fileURL: Self.defaultFileURL())
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    @discardableResult
    func record(
        _ rating: FeedbackRating,
        for phrase: PhraseProgressKey,
        at reviewedAt: Date = Date(),
        id: UUID = UUID()
    ) throws -> ReviewEvent {
        if let existing = events.first(where: { $0.id == id }) {
            return existing
        }

        let event = ReviewEvent(
            id: id,
            phrase: phrase,
            rating: rating,
            reviewedAt: reviewedAt
        )
        let previous = events
        events.append(event)
        events.sort(by: Self.eventOrder)
        do {
            try persist(updatedAt: reviewedAt)
            persistenceError = nil
            return event
        } catch {
            events = previous
            persistenceError = error.localizedDescription
            throw error
        }
    }

    func exportJSONString(at generatedAt: Date = Date()) -> String {
        do {
            let data = try encodedDocument(updatedAt: generatedAt)
            return String(decoding: data, as: UTF8.self)
        } catch {
            persistenceError = error.localizedDescription
            return "{\"schema_version\":1,\"timezone\":\"Asia/Bangkok\",\"events\":[]}"
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        do {
            let document = try decoder.decode(
                LearningProgressDocument.self,
                from: Data(contentsOf: fileURL)
            )
            try validate(document)
            events = document.events.sorted(by: Self.eventOrder)
            persistenceError = nil
        } catch {
            events = []
            persistenceError = "Saved learning progress could not be read. \(error.localizedDescription)"
        }
    }

    private func validate(_ document: LearningProgressDocument) throws {
        guard document.schemaVersion == LearningProgressDocument.currentSchemaVersion else {
            throw LearningProgressStoreError.unsupportedSchema
        }
        guard document.timezone == LearningProgressDocument.timezone else {
            throw LearningProgressStoreError.invalidTimezone
        }
        guard Set(document.events.map(\.id)).count == document.events.count else {
            throw LearningProgressStoreError.duplicateEvent
        }
        for event in document.events {
            let key = event.phrase
            guard !key.lessonID.isEmpty,
                  key.revision > 0,
                  !key.sentenceID.isEmpty,
                  PublisherContentIntegrity.isValidSHA256(key.contentSHA256) else {
                throw LearningProgressStoreError.invalidPhraseIdentity
            }
        }
    }

    private func persist(updatedAt: Date) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encodedDocument(updatedAt: updatedAt).write(to: fileURL, options: .atomic)
    }

    private func encodedDocument(updatedAt: Date) throws -> Data {
        try encoder.encode(LearningProgressDocument(updatedAt: updatedAt, events: events))
    }

    private static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let root = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("ThaiTrainerContent", isDirectory: true)
            .appendingPathComponent("learning-progress.json", isDirectory: false)
    }

    private static func eventOrder(_ lhs: ReviewEvent, _ rhs: ReviewEvent) -> Bool {
        if lhs.reviewedAt == rhs.reviewedAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.reviewedAt < rhs.reviewedAt
    }
}
