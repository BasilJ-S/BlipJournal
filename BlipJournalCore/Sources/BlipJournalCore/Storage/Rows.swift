import Foundation
import GRDB

// GRDB reads and writes these enums as their raw `String`; GRDB supplies the
// conformance for any `RawRepresentable` whose raw value it already knows.
extension QuestionKind: DatabaseValueConvertible {}
extension PromptStatus: DatabaseValueConvertible {}

// One record struct per table. Each has one property per column and no logic: they are
// the shape of the schema, made public so `Backup` can carry them verbatim.

/// A row of `survey`.
public struct SurveyRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "survey"
    public var id: String
    public var createdAt: Date
}

/// A row of `surveyVersion`.
public struct SurveyVersionRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "surveyVersion"
    public var id: String
    public var surveyId: String
    public var name: String
    public var isArchived: Bool
    public var journalSummaryIsConfigured: Bool
    public var primarySummaryQuestionId: String?
    public var secondarySummaryQuestionId: String?
    public var createdAt: Date

    public init(
        id: String, surveyId: String, name: String, isArchived: Bool,
        journalSummaryIsConfigured: Bool = false,
        primarySummaryQuestionId: String? = nil,
        secondarySummaryQuestionId: String? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.surveyId = surveyId
        self.name = name
        self.isArchived = isArchived
        self.journalSummaryIsConfigured = journalSummaryIsConfigured
        self.primarySummaryQuestionId = primarySummaryQuestionId
        self.secondarySummaryQuestionId = secondarySummaryQuestionId
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, surveyId, name, isArchived, journalSummaryIsConfigured,
             primarySummaryQuestionId, secondarySummaryQuestionId, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        surveyId = try container.decode(String.self, forKey: .surveyId)
        name = try container.decode(String.self, forKey: .name)
        isArchived = try container.decode(Bool.self, forKey: .isArchived)
        journalSummaryIsConfigured = try container.decodeIfPresent(
            Bool.self, forKey: .journalSummaryIsConfigured) ?? false
        primarySummaryQuestionId = try container.decodeIfPresent(
            String.self, forKey: .primarySummaryQuestionId)
        secondarySummaryQuestionId = try container.decodeIfPresent(
            String.self, forKey: .secondarySummaryQuestionId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

/// A row of `surveySampling`.
public struct SurveySamplingRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "surveySampling"
    public var id: String
    public var surveyId: String
    public var promptsPerDay: Int
    public var windowStartMinutes: Int
    public var windowEndMinutes: Int
    public var minGapMinutes: Int
    public var expiryMinutes: Int
    public var isEnabled: Bool
    public var createdAt: Date
}

/// A row of `surveyNotificationPreview`. `mode` is `"private"`, `"surveyName"` or
/// `"custom"`; `message` is set only for `"custom"`.
public struct SurveyNotificationPreviewRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "surveyNotificationPreview"
    public var id: String
    public var surveyId: String
    public var mode: String
    public var message: String?
    public var createdAt: Date
}

/// A row of `question`.
public struct QuestionRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "question"
    public var id: String
    public var surveyId: String
    public var kind: QuestionKind
    public var createdAt: Date
}

/// A row of `questionVersion`.
public struct QuestionVersionRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "questionVersion"
    public var id: String
    public var questionId: String
    public var label: String
    public var position: Int
    public var isRequired: Bool
    public var isArchived: Bool
    public var scaleMin: Int?
    public var scaleMax: Int?
    public var scaleMinLabel: String?
    public var scaleMaxLabel: String?
    public var allowsCustomOptions: Bool
    public var createdAt: Date
}

/// A row of `option`.
public struct OptionRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "option"
    public var id: String
    public var questionId: String
    public var createdAt: Date
}

/// A row of `optionVersion`.
public struct OptionVersionRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "optionVersion"
    public var id: String
    public var optionId: String
    public var label: String
    public var position: Int
    public var isArchived: Bool
    public var createdAt: Date
}

/// A row of `prompt`.
public struct PromptRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "prompt"
    public var id: String
    public var surveyId: String
    public var day: String
    public var scheduledAt: Date
    public var expiresAt: Date
    public var status: PromptStatus
    public var respondedAt: Date?
}

/// A row of `entry`.
public struct EntryRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entry"
    public var id: String
    public var surveyId: String
    public var promptId: String?
    public var startedAt: Date
    public var completedAt: Date?
}

/// A row of `answer`. Exactly one of the three value columns is set for scale, yes/no
/// and text answers; choice answers set none and keep their selections in
/// `answerOption`.
public struct AnswerRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "answer"
    public var id: String
    public var entryId: String
    public var questionId: String
    public var questionVersionId: String
    public var answeredAt: Date
    public var kind: QuestionKind
    public var numericValue: Int?
    public var textValue: String?
    public var boolValue: Bool?
}

/// A row of `answerOption`: one selected option of one choice answer.
public struct AnswerOptionRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "answerOption"
    public var answerId: String
    public var optionId: String
}
