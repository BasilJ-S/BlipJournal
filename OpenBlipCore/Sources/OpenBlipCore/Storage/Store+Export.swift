import Foundation
import GRDB

extension Store {
    /// Everything the exporters and analytics need about one survey, loaded in one
    /// read. See `Export/ExportSnapshot.swift` for the contract of each field.
    ///
    /// Throws `notFound` for an unknown survey.
    public func exportSnapshot(surveyId: String) throws -> ExportSnapshot {
        try dbQueue.read { db in
            let definitions = try DefinitionRows.load(db, surveyId: surveyId)
            guard let surveyRow = definitions.surveys.first,
                  let survey = definitions.survey(for: surveyRow)
            else { throw StoreError.notFound }

            let entryRows = try EntryRow.fetchAll(
                db, sql: "SELECT * FROM entry WHERE surveyId = ? ORDER BY startedAt, rowid",
                arguments: [surveyId])
            let promptRows = try PromptRow.fetchAll(
                db, sql: "SELECT * FROM prompt WHERE id IN (SELECT promptId FROM entry WHERE surveyId = ?)",
                arguments: [surveyId])
            let answerRows = try AnswerRow.fetchAll(
                db,
                sql: """
                    SELECT * FROM answer
                    WHERE entryId IN (SELECT id FROM entry WHERE surveyId = ?)
                    ORDER BY answeredAt, rowid
                    """,
                arguments: [surveyId])
            let selections = try AnswerOptionRow.fetchAll(
                db,
                sql: """
                    SELECT * FROM answerOption
                    WHERE answerId IN (
                        SELECT id FROM answer WHERE entryId IN (SELECT id FROM entry WHERE surveyId = ?))
                    ORDER BY rowid
                    """,
                arguments: [surveyId])

            let prompts = Dictionary(promptRows.map { ($0.id, Prompt($0)) }, uniquingKeysWith: { first, _ in first })
            let answers = Dictionary(
                grouping: try Self.makeAnswers(answerRows, selections: selections), by: \.entryId)
            let entries = entryRows.map { row in
                ExportEntry(
                    entry: Entry(row),
                    prompt: row.promptId.flatMap { prompts[$0] },
                    answers: answers[row.id] ?? [])
            }

            var questionLabelHistory: [String: [LabelVersion]] = [:]
            var optionLabelHistory: [String: [LabelVersion]] = [:]
            var questionVersionLabels: [String: String] = [:]
            for question in survey.questions {
                let versions = definitions.questionVersions[question.id] ?? []
                questionLabelHistory[question.id] = DefinitionRows.labelHistory(versions)
                for version in versions {
                    questionVersionLabels[version.id] = version.label
                }
                for option in question.options {
                    optionLabelHistory[option.id] =
                        DefinitionRows.labelHistory(definitions.optionVersions[option.id] ?? [])
                }
            }

            return ExportSnapshot(
                survey: survey,
                entries: entries,
                questionLabelHistory: questionLabelHistory,
                optionLabelHistory: optionLabelHistory,
                questionVersionLabels: questionVersionLabels)
        }
    }

    /// Every row of every table. Versioned tables come in `(createdAt, rowid)` order,
    /// the rest in primary-key order, so two backups of one database are equal.
    ///
    /// `now` becomes `Backup.exportedAt`, rounded to the millisecond like every stored
    /// timestamp; it is a parameter so the JSON can be byte-identical across calls.
    public func backup(now: Date = Date()) throws -> Backup {
        try dbQueue.read { db in
            let versioned = "ORDER BY \(Self.versionOrder)"
            return Backup(
                schemaVersion: CoreSchema.version,
                exportedAt: BackupExporter.normalized(now),
                surveys: try SurveyRow.fetchAll(db, sql: "SELECT * FROM survey ORDER BY id"),
                surveyVersions: try SurveyVersionRow.fetchAll(db, sql: "SELECT * FROM surveyVersion \(versioned)"),
                surveySamplings: try SurveySamplingRow.fetchAll(db, sql: "SELECT * FROM surveySampling \(versioned)"),
                questions: try QuestionRow.fetchAll(db, sql: "SELECT * FROM question ORDER BY id"),
                questionVersions: try QuestionVersionRow.fetchAll(db, sql: "SELECT * FROM questionVersion \(versioned)"),
                options: try OptionRow.fetchAll(db, sql: "SELECT * FROM option ORDER BY id"),
                optionVersions: try OptionVersionRow.fetchAll(db, sql: "SELECT * FROM optionVersion \(versioned)"),
                prompts: try PromptRow.fetchAll(db, sql: "SELECT * FROM prompt ORDER BY id"),
                entries: try EntryRow.fetchAll(db, sql: "SELECT * FROM entry ORDER BY id"),
                answers: try AnswerRow.fetchAll(db, sql: "SELECT * FROM answer ORDER BY id"),
                answerOptions: try AnswerOptionRow.fetchAll(db, sql: "SELECT * FROM answerOption ORDER BY answerId, optionId"))
        }
    }
}
