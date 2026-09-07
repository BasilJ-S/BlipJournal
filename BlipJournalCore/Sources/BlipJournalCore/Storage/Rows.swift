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
    public var createdAt: Date
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
    /// The question's ``SpectrumConfig``, JSON-encoded. Non-nil only for spectrum
    /// questions.
    public var spectrumConfig: String?
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

/// A row of `answer`. Exactly one of the four value columns is set for scale,
/// spectrum, yes/no and text answers; choice answers set none and keep their
/// selections in `answerOption`.
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
    public var spectrumValue: Double?
}

/// A row of `answerOption`: one selected option of one choice answer.
public struct AnswerOptionRow: Sendable, Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "answerOption"
    public var answerId: String
    public var optionId: String
}
