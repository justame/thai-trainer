import CryptoKit
import Foundation

struct Lesson: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let lessonID: String
    let revision: Int
    let day: Int
    let theme: String
    let status: String?
    let sentences: [LessonSentence]
    let audioProgram: LessonAudioProgram

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case lessonID = "lesson_id"
        case revision
        case day
        case theme
        case status
        case sentences
        case audioProgram = "audio_program"
    }
}

struct LessonSentence: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let promptHebrew: String
    let thai: String
    let romanization: String
    let reviewStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case promptHebrew = "prompt_he"
        case thai
        case romanization
        case reviewStatus = "review_status"
    }
}

struct LessonAudioProgram: Decodable, Equatable, Sendable {
    let tracks: [LessonTrackDefinition]
}

struct LessonTrackDefinition: Decodable, Equatable, Identifiable, Sendable {
    let id: String
}

enum PracticeTrack: String, CaseIterable, Identifiable, Sendable {
    case listening
    case shadowing
    case recall
    case scenario

    var id: String { rawValue }

    var title: String {
        switch self {
        case .listening: "Listening"
        case .shadowing: "Shadowing"
        case .recall: "Recall"
        case .scenario: "Scenario"
        }
    }

    var systemImage: String {
        switch self {
        case .listening: "ear"
        case .shadowing: "waveform.and.mic"
        case .recall: "brain.head.profile"
        case .scenario: "person.2.wave.2"
        }
    }
}

struct AudioManifest: Decodable, Sendable {
    let schemaVersion: Int
    let lessonID: String
    let revision: Int
    let contentSHA256: String
    let tracks: [AudioManifestTrack]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case lessonID = "lesson_id"
        case revision
        case contentSHA256 = "content_sha256"
        case tracks
    }
}

struct AudioManifestTrack: Decodable, Sendable {
    let lessonID: String
    let revision: Int
    let trackID: String
    let file: String
    let byteCount: Int64
    let contentSHA256: String

    enum CodingKeys: String, CodingKey {
        case lessonID = "lesson_id"
        case revision
        case trackID = "track_id"
        case file
        case byteCount = "bytes"
        case contentSHA256 = "content_sha256"
    }
}

enum LessonContentContract {
    static let sentenceCount = 20

    static func violation(in lesson: Lesson) -> String? {
        guard lesson.sentences.count == sentenceCount else {
            return "The lesson must contain exactly \(sentenceCount) sentences."
        }

        let sentenceIDs = lesson.sentences.map(\.id)
        guard Set(sentenceIDs).count == sentenceCount else {
            return "The lesson must contain \(sentenceCount) unique sentence IDs."
        }

        for sentence in lesson.sentences {
            let requiredValues = [
                sentence.id,
                sentence.promptHebrew,
                sentence.thai,
                sentence.romanization,
            ]
            guard requiredValues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return "Every sentence needs non-empty id, prompt_he, thai, and romanization."
            }
        }
        return nil
    }
}

enum PublisherContentIntegrity {
    enum IntegrityError: Error {
        case invalidLesson
    }

    static func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    /// Mirrors `audio.generate_audio.canonical_content` and its deterministic
    /// JSON encoding so the static client verifies the publisher's lesson hash.
    static func sha256(forLessonData data: Data) throws -> String {
        guard let lesson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sentences = lesson["sentences"] as? [[String: Any]],
              sentences.count == LessonContentContract.sentenceCount,
              let voices = lesson["voices"] as? [String: Any],
              let audioProgram = lesson["audio_program"] as? [String: Any],
              let tracks = audioProgram["tracks"] as? [[String: Any]],
              !tracks.isEmpty else {
            throw IntegrityError.invalidLesson
        }

        var seenSentenceIDs = Set<String>()
        let canonicalSentences: [[String: String]] = try sentences.map { sentence in
            guard let id = nonemptyString(sentence["id"]),
                  let promptHebrew = nonemptyString(sentence["prompt_he"]),
                  let thai = nonemptyString(sentence["thai"]),
                  seenSentenceIDs.insert(id).inserted else {
                throw IntegrityError.invalidLesson
            }
            return ["id": id, "prompt_he": promptHebrew, "thai": thai]
        }

        for track in tracks {
            guard let sequence = track["sequence"] as? [String],
                  !sequence.isEmpty,
                  sequence.allSatisfy(seenSentenceIDs.contains) else {
                throw IntegrityError.invalidLesson
            }
        }

        let canonical: [String: Any] = [
            "schema_version": lesson["schema_version"] ?? NSNull(),
            "lesson_id": lesson["lesson_id"] ?? NSNull(),
            "revision": lesson["revision"] ?? NSNull(),
            "voices": voices,
            "audio_program": audioProgram,
            "sentences": canonicalSentences,
        ]
        guard JSONSerialization.isValidJSONObject(canonical) else {
            throw IntegrityError.invalidLesson
        }

        let encoded = try JSONSerialization.data(
            withJSONObject: canonical,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        return SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = value as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

struct ValidatedAudioTrack: Equatable, Identifiable, Sendable {
    let id: String
    let fileURL: URL
}

enum AudioGenerationState: Equatable, Sendable {
    case notGenerated
    case ready([ValidatedAudioTrack])
    case invalid(reason: String)

    var playableTracks: [ValidatedAudioTrack] {
        guard case let .ready(tracks) = self else { return [] }
        return tracks
    }
}

struct LessonPackage: Equatable, Sendable {
    let lesson: Lesson
    let audioState: AudioGenerationState
}
