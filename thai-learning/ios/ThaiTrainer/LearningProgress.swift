import Foundation

enum FeedbackRating: String, Codable, CaseIterable, Identifiable, Sendable {
    case again
    case easy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .again: "Again"
        case .easy: "Easy"
        }
    }

    var systemImage: String {
        switch self {
        case .again: "arrow.counterclockwise"
        case .easy: "checkmark"
        }
    }
}

struct PhraseProgressKey: Codable, Hashable, Identifiable, Sendable {
    let lessonID: String
    let revision: Int
    let contentSHA256: String
    let sentenceID: String

    var id: String {
        "\(lessonID)|r\(revision)|\(contentSHA256)|\(sentenceID)"
    }

    enum CodingKeys: String, CodingKey {
        case lessonID = "lesson_id"
        case revision
        case contentSHA256 = "content_sha256"
        case sentenceID = "sentence_id"
    }
}

struct ReviewEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let phrase: PhraseProgressKey
    let rating: FeedbackRating
    let reviewedAt: Date

    init(
        id: UUID = UUID(),
        phrase: PhraseProgressKey,
        rating: FeedbackRating,
        reviewedAt: Date
    ) {
        self.id = id
        self.phrase = phrase
        self.rating = rating
        self.reviewedAt = reviewedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case phrase
        case rating
        case reviewedAt = "reviewed_at"
    }
}

struct LearningProgressDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let timezone = "Asia/Bangkok"

    let schemaVersion: Int
    let timezone: String
    let updatedAt: Date
    let events: [ReviewEvent]

    init(updatedAt: Date, events: [ReviewEvent]) {
        schemaVersion = Self.currentSchemaVersion
        timezone = Self.timezone
        self.updatedAt = updatedAt
        self.events = events
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case timezone
        case updatedAt = "updated_at"
        case events
    }
}

struct SentenceProgress: Equatable, Sendable {
    let key: PhraseProgressKey
    let reviewCount: Int
    let easyStreak: Int
    let againCount: Int
    let lastRating: FeedbackRating
    let lastReviewedAt: Date
    let nextReviewAt: Date
}

enum PlannedPhraseKind: String, Codable, Sendable {
    case review
    case new
}

struct PlannedPracticeItem: Equatable, Identifiable, Sendable {
    let key: PhraseProgressKey
    let lessonDay: Int
    let sentence: LessonSentence
    let kind: PlannedPhraseKind

    var id: String { key.id }
}

struct DailyPracticeDraft: Equatable, Identifiable, Sendable {
    let date: Date
    let items: [PlannedPracticeItem]

    var id: Date { date }
    var reviewCount: Int { items.filter { $0.kind == .review }.count }
    var newCount: Int { items.filter { $0.kind == .new }.count }
}

struct WeeklySummary: Equatable, Sendable {
    let weekStart: Date
    let weekEnd: Date
    let reviewCount: Int
    let easyCount: Int
    let againCount: Int
    let uniquePhraseCount: Int
    let practiceDayCount: Int
    let easyRate: Double
    let dueReviewCount: Int
    let newPhraseCount: Int
}
