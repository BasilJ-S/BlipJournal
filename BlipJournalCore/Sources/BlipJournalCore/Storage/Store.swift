import Foundation
import GRDB

/// The errors `Store` raises on its own, as opposed to the `DatabaseError`s GRDB raises
/// when SQLite refuses a statement.
public enum StoreError: Error, Equatable {
    /// A hard delete was asked for a definition whose current version is not archived.
    case notArchived
    /// The identifier names nothing in the database.
    case notFound
    /// `updateNotificationPreview` was asked to save a `.custom` preview whose message
    /// is blank once trimmed.
    case invalidNotificationPreview
}

/// The single door to the SQLite database. Every other subsystem reads and writes
/// through it.
///
/// Definitions (surveys, questions, options) are insert-only: every edit adds a version
/// row, and the current view is the newest version of each. Prompts and entries are
/// mutable. Hard delete, in `Store+HardDelete.swift`, is the one audited exception and
/// only acts on definitions already archived.
///
/// Every method is synchronous and safe to call from any thread; the underlying
/// `DatabaseQueue` serialises access.
public final class Store: Sendable {
    /// The serialised connection. Internal so `Store` extensions across files can use it.
    let dbQueue: DatabaseQueue

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try Schema.makeMigrator().migrate(dbQueue)
    }

    /// Opens (creating if needed) the database at `directory/blipjournal.sqlite` and
    /// applies any pending migrations.
    ///
    /// On iOS the directory is given `FileProtectionType.complete` before the database
    /// file exists, so the database and any journal file inherit it.
    public static func open(at directory: URL) throws -> Store {
        let fileManager = FileManager.default
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: attributes)
        #if os(iOS)
        // The directory may have existed already; make sure it carries the class.
        try fileManager.setAttributes(attributes, ofItemAtPath: directory.path)
        #endif
        let path = directory.appendingPathComponent(databaseFileName).path
        return try Store(dbQueue: DatabaseQueue(path: path, configuration: configuration))
    }

    /// Opens a private in-memory database with the same configuration and schema.
    public static func inMemory() throws -> Store {
        try Store(dbQueue: DatabaseQueue(configuration: configuration))
    }

    /// The name of the database file inside the directory given to `open(at:)`.
    public static let databaseFileName = "blipjournal.sqlite"

    /// `secure_delete` on, so freed pages are overwritten as they are freed, and
    /// `temp_store` in memory, so the full copy `VACUUM` makes of the surviving rows never
    /// touches SQLite's temp directory, which on iOS is outside the protected database
    /// directory. The journal mode is left at SQLite's rollback default; WAL is
    /// deliberately not enabled.
    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        return configuration
    }

    /// The tail of every destructive method: checkpoint the write-ahead log (a no-op in
    /// rollback journal mode, kept so a later switch to WAL stays safe) and rebuild the
    /// file so freed pages leave it. `VACUUM` cannot run inside a transaction, so this
    /// runs after the deleting transaction has committed.
    func checkpointAndVacuum() throws {
        try dbQueue.writeWithoutTransaction { db in
            _ = try Row.fetchAll(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            try db.execute(sql: "VACUUM")
        }
    }
}

// MARK: - Current-view resolution

extension Store {
    /// The one ordering rule for version rows. The current version of a definition is
    /// the last row in this order; history is returned in this order, oldest first.
    static let versionOrder = "createdAt, rowid"

    func currentSurveyVersion(_ db: Database, surveyId: String) throws -> SurveyVersionRow? {
        try SurveyVersionRow.fetchAll(
            db, sql: "SELECT * FROM surveyVersion WHERE surveyId = ? ORDER BY \(Self.versionOrder)",
            arguments: [surveyId]
        ).last
    }

    func currentQuestionVersion(_ db: Database, questionId: String) throws -> QuestionVersionRow? {
        try QuestionVersionRow.fetchAll(
            db, sql: "SELECT * FROM questionVersion WHERE questionId = ? ORDER BY \(Self.versionOrder)",
            arguments: [questionId]
        ).last
    }

    func currentOptionVersion(_ db: Database, optionId: String) throws -> OptionVersionRow? {
        try OptionVersionRow.fetchAll(
            db, sql: "SELECT * FROM optionVersion WHERE optionId = ? ORDER BY \(Self.versionOrder)",
            arguments: [optionId]
        ).last
    }

    /// The scale a question version row describes, or nil when any part is missing.
    static func scaleConfig(of row: QuestionVersionRow) -> ScaleConfig? {
        guard let min = row.scaleMin, let max = row.scaleMax,
              let minLabel = row.scaleMinLabel, let maxLabel = row.scaleMaxLabel
        else { return nil }
        return ScaleConfig(min: min, max: max, minLabel: minLabel, maxLabel: maxLabel)
    }

    /// The preview a notification preview row describes. An unrecognised `mode` (there
    /// is none on any row this module writes) resolves to `.private`, the same as a
    /// missing row, rather than trapping on data written by a future version.
    static func notificationPreview(of row: SurveyNotificationPreviewRow) -> NotificationPreview {
        switch row.mode {
        case "surveyName": .surveyName
        case "custom": .custom(message: row.message ?? "")
        default: .private
        }
    }

    /// The row a notification preview writes. Only `.custom` sets `message`.
    static func notificationPreviewRow(
        id: String = Identifier.make(), surveyId: String, _ preview: NotificationPreview, now: Date
    ) -> SurveyNotificationPreviewRow {
        let mode: String
        let message: String?
        switch preview {
        case .private: mode = "private"; message = nil
        case .surveyName: mode = "surveyName"; message = nil
        case .custom(let text): mode = "custom"; message = text
        }
        return SurveyNotificationPreviewRow(id: id, surveyId: surveyId, mode: mode, message: message, createdAt: now)
    }
}

/// Every definition row of one survey, or of every survey, loaded in one pass with
/// each version list in `Store.versionOrder`, and resolved to the current view in Swift.
///
/// Volumes are tiny, and one ordering rule in one place beats correlated subqueries in
/// five.
struct DefinitionRows {
    var surveys: [SurveyRow]
    var surveyVersions: [String: [SurveyVersionRow]]
    var samplings: [String: [SurveySamplingRow]]
    var notificationPreviews: [String: [SurveyNotificationPreviewRow]]
    var questions: [String: [QuestionRow]]
    var questionVersions: [String: [QuestionVersionRow]]
    var options: [String: [OptionRow]]
    var optionVersions: [String: [OptionVersionRow]]

    /// Loads the rows of `surveyId`, or of every survey when nil.
    static func load(_ db: Database, surveyId: String?) throws -> DefinitionRows {
        let inSurvey = "surveyId = ?"
        let inQuestion = "questionId IN (SELECT id FROM question WHERE surveyId = ?)"
        let inOption = "optionId IN (SELECT id FROM option WHERE \(inQuestion))"
        return DefinitionRows(
            surveys: try fetch(db, "survey", "id = ?", surveyId),
            surveyVersions: Dictionary(
                grouping: try fetch(db, "surveyVersion", inSurvey, surveyId) as [SurveyVersionRow],
                by: \.surveyId),
            samplings: Dictionary(
                grouping: try fetch(db, "surveySampling", inSurvey, surveyId) as [SurveySamplingRow],
                by: \.surveyId),
            notificationPreviews: Dictionary(
                grouping: try fetch(db, "surveyNotificationPreview", inSurvey, surveyId) as [SurveyNotificationPreviewRow],
                by: \.surveyId),
            questions: Dictionary(
                grouping: try fetch(db, "question", inSurvey, surveyId) as [QuestionRow],
                by: \.surveyId),
            questionVersions: Dictionary(
                grouping: try fetch(db, "questionVersion", inQuestion, surveyId) as [QuestionVersionRow],
                by: \.questionId),
            options: Dictionary(
                grouping: try fetch(db, "option", inQuestion, surveyId) as [OptionRow],
                by: \.questionId),
            optionVersions: Dictionary(
                grouping: try fetch(db, "optionVersion", inOption, surveyId) as [OptionVersionRow],
                by: \.optionId)
        )
    }

    private static func fetch<R: FetchableRecord>(
        _ db: Database, _ table: String, _ predicate: String, _ surveyId: String?
    ) throws -> [R] {
        let filter = surveyId == nil ? "" : "WHERE \(predicate) "
        return try R.fetchAll(
            db, sql: "SELECT * FROM \(table) \(filter)ORDER BY \(Store.versionOrder)",
            arguments: surveyId.map { [$0] } ?? [])
    }

    /// Every loaded survey in its current view, in `createdAt` order.
    var currentSurveys: [Survey] {
        surveys.compactMap(survey(for:))
    }

    /// The current view of one survey row, or nil if it has no version row.
    func survey(for row: SurveyRow) -> Survey? {
        guard let version = surveyVersions[row.id]?.last else { return nil }
        let sampling = samplings[row.id]?.last.map { s in
            SamplingConfig(
                promptsPerDay: s.promptsPerDay,
                windowStartMinutes: s.windowStartMinutes,
                windowEndMinutes: s.windowEndMinutes,
                minGapMinutes: s.minGapMinutes,
                expiryMinutes: s.expiryMinutes,
                isEnabled: s.isEnabled)
        }
        let notificationPreview = notificationPreviews[row.id]?.last.map(Store.notificationPreview(of:))
        return Survey(
            id: row.id,
            name: version.name,
            createdAt: row.createdAt,
            isArchived: version.isArchived,
            sampling: sampling ?? .default,
            notificationPreview: notificationPreview ?? .default,
            questions: (questions[row.id] ?? []).compactMap(question(for:)))
    }

    /// The current view of one question row, or nil if it has no version row.
    func question(for row: QuestionRow) -> Question? {
        guard let version = questionVersions[row.id]?.last else { return nil }
        return Question(
            id: row.id,
            kind: row.kind,
            label: version.label,
            position: version.position,
            isRequired: version.isRequired,
            isArchived: version.isArchived,
            scale: Store.scaleConfig(of: version),
            allowsCustomOptions: version.allowsCustomOptions,
            options: (options[row.id] ?? []).compactMap(option(for:)))
    }

    /// The current view of one option row, or nil if it has no version row.
    func option(for row: OptionRow) -> ChoiceOption? {
        guard let version = optionVersions[row.id]?.last else { return nil }
        return ChoiceOption(
            id: row.id, label: version.label, position: version.position,
            isArchived: version.isArchived)
    }

    /// Rename history of a version list, oldest first.
    static func labelHistory(_ versions: [QuestionVersionRow]) -> [LabelVersion] {
        versions.map { LabelVersion(label: $0.label, validFrom: $0.createdAt) }
    }

    static func labelHistory(_ versions: [OptionVersionRow]) -> [LabelVersion] {
        versions.map { LabelVersion(label: $0.label, validFrom: $0.createdAt) }
    }

    static func labelHistory(_ versions: [SurveyVersionRow]) -> [LabelVersion] {
        versions.map { LabelVersion(label: $0.name, validFrom: $0.createdAt) }
    }
}
