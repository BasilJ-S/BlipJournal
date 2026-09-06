import Foundation
import GRDB

/// The on-disk schema, as the list of migrations `Store` applies when it opens.
///
/// Migrations are append-only. A released migration is never edited; a schema change
/// registers a new one and bumps `CoreSchema.version` in the same change.
enum Schema {
    /// Every table, children before parents.
    ///
    /// Deleting in this order never trips a foreign key, and `Backup` lists its arrays in
    /// the reverse of it. Foreign keys carry no `ON DELETE CASCADE`, so every deletion is
    /// explicit and the counts in `DeletionImpact` are the counts that go.
    static let tablesChildrenFirst = [
        "answerOption", "answer", "entry", "prompt",
        "optionVersion", "option", "questionVersion", "question",
        "surveyNotificationPreview", "surveySampling", "surveyVersion", "survey",
    ]

    /// The migrator holding every migration, in order.
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: migrateV1)
        migrator.registerMigration("v2", migrate: migrateV2)
        return migrator
    }

    /// Schema version 1: the tables listed in docs/PLAN.md C2.
    ///
    /// Every ID is `TEXT PRIMARY KEY`; every timestamp is a `DATETIME` column holding
    /// GRDB's default UTC string, which sorts lexicographically.
    private static func migrateV1(_ db: Database) throws {
        try db.create(table: "survey") { t in
            t.primaryKey("id", .text)
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "surveyVersion") { t in
            t.primaryKey("id", .text)
            t.column("surveyId", .text).notNull().indexed().references("survey")
            t.column("name", .text).notNull()
            t.column("isArchived", .boolean).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "surveySampling") { t in
            t.primaryKey("id", .text)
            t.column("surveyId", .text).notNull().indexed().references("survey")
            t.column("promptsPerDay", .integer).notNull()
            t.column("windowStartMinutes", .integer).notNull()
            t.column("windowEndMinutes", .integer).notNull()
            t.column("minGapMinutes", .integer).notNull()
            t.column("expiryMinutes", .integer).notNull()
            t.column("isEnabled", .boolean).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "question") { t in
            t.primaryKey("id", .text)
            t.column("surveyId", .text).notNull().indexed().references("survey")
            t.column("kind", .text).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "questionVersion") { t in
            t.primaryKey("id", .text)
            t.column("questionId", .text).notNull().indexed().references("question")
            t.column("label", .text).notNull()
            t.column("position", .integer).notNull()
            t.column("isRequired", .boolean).notNull()
            t.column("isArchived", .boolean).notNull()
            t.column("scaleMin", .integer)
            t.column("scaleMax", .integer)
            t.column("scaleMinLabel", .text)
            t.column("scaleMaxLabel", .text)
            t.column("allowsCustomOptions", .boolean).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "option") { t in
            t.primaryKey("id", .text)
            t.column("questionId", .text).notNull().indexed().references("question")
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "optionVersion") { t in
            t.primaryKey("id", .text)
            t.column("optionId", .text).notNull().indexed().references("option")
            t.column("label", .text).notNull()
            t.column("position", .integer).notNull()
            t.column("isArchived", .boolean).notNull()
            t.column("createdAt", .datetime).notNull()
        }
        try db.create(table: "prompt") { t in
            t.primaryKey("id", .text)
            t.column("surveyId", .text).notNull().references("survey")
            t.column("day", .text).notNull()
            t.column("scheduledAt", .datetime).notNull()
            t.column("expiresAt", .datetime).notNull()
            t.column("status", .text).notNull().indexed()
            t.column("respondedAt", .datetime)
        }
        try db.create(indexOn: "prompt", columns: ["surveyId", "day"])
        try db.create(table: "entry") { t in
            t.primaryKey("id", .text)
            t.column("surveyId", .text).notNull().references("survey")
            t.column("promptId", .text).indexed().references("prompt")
            t.column("startedAt", .datetime).notNull()
            t.column("completedAt", .datetime)
        }
        try db.create(indexOn: "entry", columns: ["surveyId", "startedAt"])
        try db.create(table: "answer") { t in
            t.primaryKey("id", .text)
            t.column("entryId", .text).notNull().indexed().references("entry")
            t.column("questionId", .text).notNull().indexed().references("question")
            t.column("questionVersionId", .text).notNull().references("questionVersion")
            t.column("answeredAt", .datetime).notNull()
            t.column("kind", .text).notNull()
            t.column("numericValue", .integer)
            t.column("textValue", .text)
            t.column("boolValue", .boolean)
            // One answer per question per entry, so consumers never have to pick.
            t.uniqueKey(["entryId", "questionId"])
        }
        try db.create(table: "answerOption") { t in
            t.primaryKey {
                t.column("answerId", .text).references("answer")
                t.column("optionId", .text).references("option")
            }
        }
        try db.create(indexOn: "answerOption", columns: ["optionId"])
    }

    /// Schema version 2: `surveyNotificationPreview`, insert-only like `surveySampling`.
    ///
    /// A survey with no row here predates this migration; `DefinitionRows` resolves that
    /// to `.private`, the same way an absent `surveySampling` row resolves to
    /// `SamplingConfig.default`. No backfill is written, so this migration only creates
    /// the table.
    private static func migrateV2(_ db: Database) throws {
        try db.create(table: "surveyNotificationPreview") { t in
            t.primaryKey("id", .text)
            t.column("surveyId", .text).notNull().indexed().references("survey")
            t.column("mode", .text).notNull()
            t.column("message", .text)
            t.column("createdAt", .datetime).notNull()
        }
    }
}
