import Foundation
import GRDB

/// Every table of the database as plain rows, for a JSON backup.
///
/// The arrays are the GRDB record structs verbatim, in schema order, so the file is a
/// faithful dump rather than a re-interpretation. Import is out of scope for v0.
public struct Backup: Sendable, Equatable, Codable {
    /// `CoreSchema.version` at the time of the backup.
    public var schemaVersion: Int
    /// When the backup was taken.
    public var exportedAt: Date
    public var surveys: [SurveyRow]
    public var surveyVersions: [SurveyVersionRow]
    public var surveySamplings: [SurveySamplingRow]
    /// Absent from a backup taken before schema v2. `decode` defaults a missing array to
    /// empty rather than failing to read an otherwise valid file.
    public var surveyNotificationPreviews: [SurveyNotificationPreviewRow]
    public var questions: [QuestionRow]
    public var questionVersions: [QuestionVersionRow]
    public var options: [OptionRow]
    public var optionVersions: [OptionVersionRow]
    public var prompts: [PromptRow]
    public var entries: [EntryRow]
    public var answers: [AnswerRow]
    public var answerOptions: [AnswerOptionRow]

    public init(
        schemaVersion: Int,
        exportedAt: Date,
        surveys: [SurveyRow],
        surveyVersions: [SurveyVersionRow],
        surveySamplings: [SurveySamplingRow],
        surveyNotificationPreviews: [SurveyNotificationPreviewRow],
        questions: [QuestionRow],
        questionVersions: [QuestionVersionRow],
        options: [OptionRow],
        optionVersions: [OptionVersionRow],
        prompts: [PromptRow],
        entries: [EntryRow],
        answers: [AnswerRow],
        answerOptions: [AnswerOptionRow]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.surveys = surveys
        self.surveyVersions = surveyVersions
        self.surveySamplings = surveySamplings
        self.surveyNotificationPreviews = surveyNotificationPreviews
        self.questions = questions
        self.questionVersions = questionVersions
        self.options = options
        self.optionVersions = optionVersions
        self.prompts = prompts
        self.entries = entries
        self.answers = answers
        self.answerOptions = answerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, exportedAt, surveys, surveyVersions, surveySamplings,
             surveyNotificationPreviews, questions, questionVersions, options, optionVersions,
             prompts, entries, answers, answerOptions
    }

    /// Hand-written so a backup taken before schema v2, which has no
    /// `surveyNotificationPreviews` key, still decodes: it defaults to empty rather than
    /// failing `keyNotFound`. Every other field is required exactly as the synthesised
    /// initialiser would require it. `encode(to:)` is left to synthesis: every field is
    /// always written for a backup taken now.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        surveys = try container.decode([SurveyRow].self, forKey: .surveys)
        surveyVersions = try container.decode([SurveyVersionRow].self, forKey: .surveyVersions)
        surveySamplings = try container.decode([SurveySamplingRow].self, forKey: .surveySamplings)
        surveyNotificationPreviews =
            try container.decodeIfPresent([SurveyNotificationPreviewRow].self, forKey: .surveyNotificationPreviews) ?? []
        questions = try container.decode([QuestionRow].self, forKey: .questions)
        questionVersions = try container.decode([QuestionVersionRow].self, forKey: .questionVersions)
        options = try container.decode([OptionRow].self, forKey: .options)
        optionVersions = try container.decode([OptionVersionRow].self, forKey: .optionVersions)
        prompts = try container.decode([PromptRow].self, forKey: .prompts)
        entries = try container.decode([EntryRow].self, forKey: .entries)
        answers = try container.decode([AnswerRow].self, forKey: .answers)
        answerOptions = try container.decode([AnswerOptionRow].self, forKey: .answerOptions)
    }
}

/// Turns a `Backup` into a JSON file and back.
///
/// Dates are ISO 8601 in UTC with millisecond fractions, which is the precision the
/// database holds. Keys are sorted and the output pretty-printed, so two backups of the
/// same database are byte-identical and diffable. Decoding builds each `Date` through
/// GRDB's own parser, the same path a row takes out of SQLite, so a decoded backup
/// compares equal to the one that was encoded.
public enum BackupExporter {
    /// The backup as JSON.
    public static func json(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeFormatter(fractional: true).string(from: date))
        }
        return try encoder.encode(backup)
    }

    /// The inverse of `json`: reads a backup file back into a `Backup` value. Writing
    /// it into a store is a separate, later feature.
    public static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "not an ISO 8601 UTC date: \(string)")
            }
            return date
        }
        return try decoder.decode(Backup.self, from: data)
    }

    /// `now` as the database would hand it back: rounded to the millisecond and built by
    /// GRDB's parser, so `exportedAt` survives `json` then `decode` unchanged.
    static func normalized(_ date: Date) -> Date {
        Date.fromDatabaseValue(date.databaseValue) ?? date
    }

    /// Parses `yyyy-MM-ddTHH:mm:ss[.SSS]Z` by handing GRDB the same text in its own
    /// `yyyy-MM-dd HH:mm:ss[.SSS]` form. Only UTC (`Z`) is accepted, which is all `json`
    /// ever writes.
    private static func parse(_ string: String) -> Date? {
        guard string.count >= 20, string.hasSuffix("Z"), string.dropFirst(10).first == "T" else {
            return nil
        }
        var sqlite = String(string.dropLast())
        sqlite.replaceSubrange(sqlite.index(sqlite.startIndex, offsetBy: 10)...sqlite.index(sqlite.startIndex, offsetBy: 10), with: " ")
        return Date.fromDatabaseValue(sqlite.databaseValue)
    }

    // `ISO8601DateFormatter` is not `Sendable`, so one is made per use rather than
    // shared.
    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
