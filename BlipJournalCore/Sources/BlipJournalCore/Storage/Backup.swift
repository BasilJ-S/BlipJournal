#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
import GRDB

/// Every table of the database as plain rows, for a JSON backup.
///
/// The arrays are the GRDB record structs verbatim, in schema order, so the file is a
/// faithful dump rather than a re-interpretation. `Store.restore(_:)` writes one back.
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
///
/// File layout: `canonicalJSON(backup)` with `"checksum" : "<64 lowercase hex>",`
/// spliced in straight after the opening brace, so the checksum is the first key and
/// covers exactly the file's bytes with that key, its value and the comma removed. The
/// checksum is not part of `Backup`, so `decode(json(b)) == b`. SHA-256 comes from
/// CryptoKit, or `PortableSHA256` where CryptoKit does not exist.
public enum BackupExporter {
    /// The backup as JSON, with its checksum.
    public static func json(_ backup: Backup) throws -> Data {
        let canonical = try canonicalJSON(backup)
        var file = Data(checksumOpening)
        file.append(contentsOf: checksum(of: canonical).utf8)
        file.append(contentsOf: checksumClosing)
        file.append(canonical.dropFirst())
        return file
    }

    /// The bytes the checksum covers.
    static func canonicalJSON(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeFormatter(fractional: true).string(from: date))
        }
        return try encoder.encode(backup)
    }

    /// The inverse of `json`: reads a backup file back into a `Backup` value. Writing it
    /// into a store is `Store.restore(_:)`; `decodeForRestore` is the entry point for a
    /// file a person chose. It ignores the checksum; `decodeForRestore` checks it.
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

    /// Reads a backup file a person chose and refuses it with a typed `RestoreError`
    /// rather than a decoder error: `.newerSchema` when its `schemaVersion` is above
    /// `CoreSchema.version` (checked first, because a newer file may well not decode),
    /// `.unreadable` for anything else that is not a backup, including one whose
    /// checksum does not verify. A file with no `checksum` key (pre-#47) skips that check.
    public static func decodeForRestore(_ data: Data) throws -> Backup {
        let header: RestoreHeader
        do { header = try JSONDecoder().decode(RestoreHeader.self, from: data) } catch { throw RestoreError.unreadable }
        guard header.schemaVersion <= CoreSchema.version else {
            throw RestoreError.newerSchema(found: header.schemaVersion, supported: CoreSchema.version)
        }
        if header.hasChecksum {
            guard let split = splitChecksum(data), split.checksum == checksum(of: split.canonical) else {
                throw RestoreError.unreadable
            }
        }
        do { return try decode(data) } catch { throw RestoreError.unreadable }
    }

    /// The two top-level facts `decodeForRestore` needs before reading rows. Any
    /// `checksum` key counts, whatever its value (even `null`), so a damaged one is
    /// refused rather than read as a backup from before checksums.
    private struct RestoreHeader: Decodable {
        var schemaVersion: Int
        var hasChecksum: Bool

        private enum CodingKeys: String, CodingKey { case schemaVersion, checksum }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            hasChecksum = container.contains(.checksum)
        }
    }

    /// Lowercase hex SHA-256 of `canonical`.
    static func checksum(of canonical: Data) -> String {
        #if canImport(CryptoKit)
        return hex(Array(SHA256.hash(data: canonical)))
        #else
        return hex(PortableSHA256.hash(canonical))
        #endif
    }

    /// `bytes` as lowercase hex.
    static func hex(_ bytes: [UInt8]) -> String {
        let hexDigits = Array("0123456789abcdef".utf8)
        var hex: [UInt8] = []
        hex.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            hex.append(hexDigits[Int(byte >> 4)])
            hex.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: hex, as: UTF8.self)
    }

    private static let checksumOpening = Array("{\n  \"checksum\" : \"".utf8)
    private static let checksumClosing = Array("\",".utf8)
    private static let checksumLength = PortableSHA256.byteCount * 2

    /// The stored checksum and the canonical bytes it covers, or `nil` unless the file
    /// starts with a 64-digit lowercase hex checksum in exactly the layout `json` writes.
    static func splitChecksum(_ data: Data) -> (checksum: String, canonical: Data)? {
        let bytes = [UInt8](data)
        let hexStart = checksumOpening.count
        let hexEnd = hexStart + checksumLength
        let rest = hexEnd + checksumClosing.count
        guard bytes.count > rest,
              bytes.starts(with: checksumOpening),
              bytes[hexEnd ..< rest].elementsEqual(checksumClosing)
        else { return nil }
        let hex = bytes[hexStart ..< hexEnd]
        let digits = UInt8(ascii: "0")...UInt8(ascii: "9")
        let letters = UInt8(ascii: "a")...UInt8(ascii: "f")
        guard hex.allSatisfy({ digits.contains($0) || letters.contains($0) }) else { return nil }
        var canonical = Data([UInt8(ascii: "{")])
        canonical.append(contentsOf: bytes[rest...])
        return (String(decoding: hex, as: UTF8.self), canonical)
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

/// Why a backup cannot be restored. The app turns these into plain messages.
public enum RestoreError: Error, Equatable, Sendable {
    /// The file is not a backup this version can read.
    case unreadable
    /// The backup was taken by a newer version of the app than this one.
    case newerSchema(found: Int, supported: Int)
    /// The database rejected the rows (a dangling foreign key, a duplicate key). The
    /// transaction rolled back and nothing changed. An error from the vacuum after a
    /// successful commit is not this: it propagates as itself.
    case rejected
}

/// What the restore screen shows about a backup, or about the data on the phone, so the
/// two can sit side by side.
public struct BackupSummary: Sendable, Equatable {
    /// When the backup was taken. `nil` for the live database.
    public var exportedAt: Date?
    public var surveys: Int
    public var entries: Int

    public init(exportedAt: Date?, surveys: Int, entries: Int) {
        self.exportedAt = exportedAt
        self.surveys = surveys
        self.entries = entries
    }
}

extension Backup {
    /// The date and the survey and entry counts of this backup. Archived surveys count.
    public var summary: BackupSummary {
        BackupSummary(exportedAt: exportedAt, surveys: surveys.count, entries: entries.count)
    }
}
