import Foundation
import GRDB

// The one place that deletes a definition row. Every method here refuses a target whose
// current version is not archived, runs in one transaction, and ends with the
// checkpoint and vacuum step. `deletionImpact` collects exactly the rows the delete
// would remove, so the counts shown to a person are the counts that go.

/// What a hard delete will remove, as `deletionImpact` reports it before the fact.
public struct DeletionImpact: Sendable, Equatable, Hashable {
    /// Answer rows that will go.
    public var answers: Int
    /// Entries touched: those holding at least one of the answers, or, for a survey,
    /// every entry of the survey, all of which go.
    public var entries: Int
    /// Of those, entries left holding no answers. Always 0 for a survey, whose entries
    /// are removed rather than emptied.
    public var entriesEmptied: Int
    /// Option definitions that will go.
    public var options: Int
    /// Version rows that will go: survey versions, sampling rows, question versions and
    /// option versions.
    public var versions: Int
    /// Prompt rows that will go. Non-zero only for a survey.
    public var prompts: Int
    /// `answeredAt` of the oldest answer that will go.
    public var oldest: Date?
    /// `answeredAt` of the newest answer that will go.
    public var newest: Date?

    public init(
        answers: Int = 0, entries: Int = 0, entriesEmptied: Int = 0, options: Int = 0,
        versions: Int = 0, prompts: Int = 0, oldest: Date? = nil, newest: Date? = nil
    ) {
        self.answers = answers
        self.entries = entries
        self.entriesEmptied = entriesEmptied
        self.options = options
        self.versions = versions
        self.prompts = prompts
        self.oldest = oldest
        self.newest = newest
    }
}

extension Store {
    // MARK: Impact

    /// What `hardDeleteSurvey` would remove. Same preconditions as the delete.
    public func deletionImpact(surveyId: String) throws -> DeletionImpact {
        try dbQueue.read { db in try impact(db, of: doomedRows(db, surveyId: surveyId)) }
    }

    /// What `hardDeleteQuestion` would remove. Same preconditions as the delete.
    public func deletionImpact(questionId: String) throws -> DeletionImpact {
        try dbQueue.read { db in try impact(db, of: doomedRows(db, questionId: questionId)) }
    }

    /// What `hardDeleteOption` would remove. Same preconditions as the delete.
    public func deletionImpact(optionId: String) throws -> DeletionImpact {
        try dbQueue.read { db in try impact(db, of: doomedRows(db, optionId: optionId)) }
    }

    // MARK: Deletes

    /// Deletes an archived survey and everything belonging to it: definitions, sampling
    /// history, prompts, entries, answers. Never touches another survey.
    public func hardDeleteSurvey(_ id: String) throws {
        try dbQueue.write { db in try apply(db, doomedRows(db, surveyId: id)) }
        try checkpointAndVacuum()
    }

    /// Deletes an archived question, its versions, its options and their versions,
    /// every answer to it and those answers' selections. Entries are kept, including any
    /// left holding no answers: an entry records that a prompt was answered.
    public func hardDeleteQuestion(_ id: String) throws {
        try dbQueue.write { db in try apply(db, doomedRows(db, questionId: id)) }
        try checkpointAndVacuum()
    }

    /// Deletes an archived option, its versions, and every selection naming it. An
    /// answer left with no selection at all goes too, which is every single-choice
    /// answer that named it; multi-choice answers keep their other selections.
    public func hardDeleteOption(_ id: String) throws {
        try dbQueue.write { db in try apply(db, doomedRows(db, optionId: id)) }
        try checkpointAndVacuum()
    }

    /// Deletes every row of every table, then reseeds `SurveyTemplate.makeDefault(now:)`
    /// so the app comes back in its first-launch state. Returns the new survey.
    @discardableResult
    public func eraseEverything(now: Date = Date()) throws -> Survey {
        let survey = try dbQueue.write { db in
            for table in Schema.tablesChildrenFirst {
                try db.execute(sql: "DELETE FROM \(table)")
            }
            let template = SurveyTemplate.makeDefault(now: now)
            return try insertSurvey(
                db, name: template.name, sampling: template.sampling,
                questions: template.questions, now: now)
        }
        try checkpointAndVacuum()
        return survey
    }

    // MARK: The rows a delete removes

    /// Every row one hard delete will remove, collected before anything is deleted.
    /// `impact` counts these and `apply` deletes exactly these.
    private struct DoomedRows {
        /// Set for a survey-level delete; its entries, prompts, sampling and versions go.
        var surveyId: String?
        var questionIds: [String] = []
        var optionIds: [String] = []
        /// Answers that go, with their selections.
        var answers: [AnswerRow] = []
        /// Entries that go. Only a survey-level delete removes entries.
        var entryIds: [String] = []
        var promptCount = 0
        var versionCount = 0

        var isOptionLevel: Bool { surveyId == nil && questionIds.isEmpty }
    }

    private func doomedRows(_ db: Database, surveyId id: String) throws -> DoomedRows {
        guard let current = try currentSurveyVersion(db, surveyId: id) else { throw StoreError.notFound }
        guard current.isArchived else { throw StoreError.notArchived }
        let questionsOfSurvey = "SELECT id FROM question WHERE surveyId = ?"
        var doomed = DoomedRows(surveyId: id)
        doomed.questionIds = try String.fetchAll(db, sql: questionsOfSurvey, arguments: [id])
        doomed.optionIds = try String.fetchAll(
            db, sql: "SELECT id FROM option WHERE questionId IN (\(questionsOfSurvey))", arguments: [id])
        doomed.answers = try AnswerRow.fetchAll(
            db,
            sql: """
                SELECT * FROM answer
                WHERE entryId IN (SELECT id FROM entry WHERE surveyId = ?)
                   OR questionId IN (\(questionsOfSurvey))
                """,
            arguments: [id, id])
        doomed.entryIds = try String.fetchAll(db, sql: "SELECT id FROM entry WHERE surveyId = ?", arguments: [id])
        doomed.promptCount = try count(db, "prompt", "surveyId", [id])
        doomed.versionCount =
            try count(db, "surveyVersion", "surveyId", [id])
            + count(db, "surveySampling", "surveyId", [id])
            + count(db, "questionVersion", "questionId", doomed.questionIds)
            + count(db, "optionVersion", "optionId", doomed.optionIds)
        return doomed
    }

    private func doomedRows(_ db: Database, questionId id: String) throws -> DoomedRows {
        guard let current = try currentQuestionVersion(db, questionId: id) else { throw StoreError.notFound }
        guard current.isArchived else { throw StoreError.notArchived }
        var doomed = DoomedRows()
        doomed.questionIds = [id]
        doomed.optionIds = try String.fetchAll(
            db, sql: "SELECT id FROM option WHERE questionId = ? ORDER BY rowid", arguments: [id])
        doomed.answers = try AnswerRow.fetchAll(
            db, sql: "SELECT * FROM answer WHERE questionId = ?", arguments: [id])
        doomed.versionCount =
            try count(db, "questionVersion", "questionId", [id])
            + count(db, "optionVersion", "optionId", doomed.optionIds)
        return doomed
    }

    private func doomedRows(_ db: Database, optionId id: String) throws -> DoomedRows {
        guard let current = try currentOptionVersion(db, optionId: id) else { throw StoreError.notFound }
        guard current.isArchived else { throw StoreError.notArchived }
        var doomed = DoomedRows()
        doomed.optionIds = [id]
        // Answers that named this option and nothing else.
        doomed.answers = try AnswerRow.fetchAll(
            db,
            sql: """
                SELECT * FROM answer
                WHERE id IN (SELECT answerId FROM answerOption WHERE optionId = ?)
                  AND NOT EXISTS (
                    SELECT 1 FROM answerOption
                    WHERE answerOption.answerId = answer.id AND answerOption.optionId <> ?)
                """,
            arguments: [id, id])
        doomed.versionCount = try count(db, "optionVersion", "optionId", [id])
        return doomed
    }

    /// Counts the doomed rows. `entriesEmptied` needs one more query: how many answers
    /// each touched entry holds in total.
    private func impact(_ db: Database, of doomed: DoomedRows) throws -> DeletionImpact {
        let doomedPerEntry = Dictionary(grouping: doomed.answers, by: \.entryId).mapValues(\.count)
        var emptied = 0
        if doomed.surveyId == nil {
            for chunk in Self.chunks(Array(doomedPerEntry.keys)) {
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT entryId, COUNT(*) AS total FROM answer WHERE entryId IN (\(Self.placeholders(chunk.count))) GROUP BY entryId",
                    arguments: StatementArguments(chunk))
                for row in rows where (row["total"] as Int) == doomedPerEntry[row["entryId"] as String] {
                    emptied += 1
                }
            }
        }
        let answeredAts = doomed.answers.map(\.answeredAt)
        return DeletionImpact(
            answers: doomed.answers.count,
            entries: doomed.surveyId == nil ? doomedPerEntry.count : doomed.entryIds.count,
            entriesEmptied: emptied,
            options: doomed.optionIds.count,
            versions: doomed.versionCount,
            prompts: doomed.promptCount,
            oldest: answeredAts.min(),
            newest: answeredAts.max())
    }

    /// Deletes the doomed rows, children before parents, inside the caller's
    /// transaction.
    private func apply(_ db: Database, _ doomed: DoomedRows) throws {
        let answerIds = doomed.answers.map(\.id)
        try delete(db, from: "answerOption", where: "answerId", in: answerIds)
        if doomed.isOptionLevel {
            // Selections of surviving multi-choice answers that name the option.
            try delete(db, from: "answerOption", where: "optionId", in: doomed.optionIds)
        }
        // Above option level every selection naming a doomed option belongs to a doomed
        // answer, so nothing else is deleted here on purpose: a selection stored under
        // some other question would fail the `option` foreign key and roll the delete
        // back, rather than being silently stripped from an answer `impact` never counted.
        try delete(db, from: "answer", where: "id", in: answerIds)
        if let surveyId = doomed.surveyId {
            try delete(db, from: "entry", where: "id", in: doomed.entryIds)
            try db.execute(sql: "DELETE FROM prompt WHERE surveyId = ?", arguments: [surveyId])
        }
        try delete(db, from: "optionVersion", where: "optionId", in: doomed.optionIds)
        try delete(db, from: "option", where: "id", in: doomed.optionIds)
        try delete(db, from: "questionVersion", where: "questionId", in: doomed.questionIds)
        try delete(db, from: "question", where: "id", in: doomed.questionIds)
        if let surveyId = doomed.surveyId {
            try db.execute(sql: "DELETE FROM surveySampling WHERE surveyId = ?", arguments: [surveyId])
            try db.execute(sql: "DELETE FROM surveyVersion WHERE surveyId = ?", arguments: [surveyId])
            try db.execute(sql: "DELETE FROM survey WHERE id = ?", arguments: [surveyId])
        }
    }

    // MARK: SQL helpers

    /// SQLite caps bound parameters per statement; lists are sent in chunks well under it.
    private static let chunkSize = 400

    private static func chunks(_ ids: [String]) -> [[String]] {
        stride(from: 0, to: ids.count, by: chunkSize).map { Array(ids[$0..<min($0 + chunkSize, ids.count)]) }
    }

    private static func placeholders(_ count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private func count(_ db: Database, _ table: String, _ column: String, _ ids: [String]) throws -> Int {
        var total = 0
        for chunk in Self.chunks(ids) {
            total += try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM \(table) WHERE \(column) IN (\(Self.placeholders(chunk.count)))",
                arguments: StatementArguments(chunk)) ?? 0
        }
        return total
    }

    private func delete(_ db: Database, from table: String, where column: String, in ids: [String]) throws {
        for chunk in Self.chunks(ids) {
            try db.execute(
                sql: "DELETE FROM \(table) WHERE \(column) IN (\(Self.placeholders(chunk.count)))",
                arguments: StatementArguments(chunk))
        }
    }
}
