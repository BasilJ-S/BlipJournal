import Foundation
import GRDB

// Definitions are insert-only. Nothing in this file updates or deletes a row; every
// edit appends a version row stamped with the caller's `now`, and the current view is
// resolved by `DefinitionRows`.

extension Store {
    // MARK: Surveys

    /// Inserts a survey with one version, one sampling row, and every question and
    /// option in `questions` under their existing identifiers, each with one version
    /// row. This is how `SurveyTemplate.makeDefault()` is seeded.
    ///
    /// The survey itself gets a fresh identifier; `now` is its `createdAt` and the
    /// timestamp of every row written.
    @discardableResult
    public func createSurvey(
        name: String, sampling: SamplingConfig, questions: [Question], now: Date = Date()
    ) throws -> Survey {
        try dbQueue.write { db in
            try insertSurvey(db, name: name, sampling: sampling, questions: questions, now: now)
        }
    }

    /// Appends a survey version with the new name and the current archived flag.
    public func renameSurvey(_ id: String, to name: String, now: Date = Date()) throws {
        try dbQueue.write { db in
            guard let current = try currentSurveyVersion(db, surveyId: id) else {
                throw StoreError.notFound
            }
            try SurveyVersionRow(
                id: Identifier.make(), surveyId: id, name: name,
                isArchived: current.isArchived, createdAt: now
            ).insert(db)
        }
    }

    /// Appends an archived survey version with the current name. Touches nothing below
    /// the survey: its questions keep their own flags.
    public func archiveSurvey(_ id: String, now: Date = Date()) throws {
        try dbQueue.write { db in
            guard let current = try currentSurveyVersion(db, surveyId: id) else {
                throw StoreError.notFound
            }
            try SurveyVersionRow(
                id: Identifier.make(), surveyId: id, name: current.name,
                isArchived: true, createdAt: now
            ).insert(db)
        }
    }

    /// Appends a sampling row. `Survey.sampling` is always the newest one.
    public func updateSampling(surveyId: String, _ config: SamplingConfig, now: Date = Date()) throws {
        try dbQueue.write { db in
            guard try SurveyRow.exists(db, key: surveyId) else { throw StoreError.notFound }
            try makeSamplingRow(surveyId: surveyId, config, now: now).insert(db)
        }
    }

    /// Appends a notification preview row. `Survey.notificationPreview` is always the
    /// newest one. Throws `invalidNotificationPreview` for a `.custom` preview whose
    /// message is blank once trimmed, before writing anything.
    public func updateNotificationPreview(surveyId: String, _ preview: NotificationPreview, now: Date = Date()) throws {
        guard preview.isValid else { throw StoreError.invalidNotificationPreview }
        try dbQueue.write { db in
            guard try SurveyRow.exists(db, key: surveyId) else { throw StoreError.notFound }
            try Self.notificationPreviewRow(surveyId: surveyId, preview, now: now).insert(db)
        }
    }

    // MARK: Questions

    /// Inserts a question at the end of the survey: its position is one past the
    /// highest current position, archived questions included, or 0 for the first.
    public func addQuestion(
        surveyId: String, kind: QuestionKind, label: String, isRequired: Bool,
        scale: ScaleConfig?, allowsCustomOptions: Bool, now: Date = Date()
    ) throws -> Question {
        try dbQueue.write { db in
            let rows = try DefinitionRows.load(db, surveyId: surveyId)
            guard let surveyRow = rows.surveys.first, let survey = rows.survey(for: surveyRow) else {
                throw StoreError.notFound
            }
            let position = survey.questions.map(\.position).max().map { $0 + 1 } ?? 0
            let question = Question(
                kind: kind, label: label, position: position, isRequired: isRequired,
                scale: scale, allowsCustomOptions: allowsCustomOptions)
            try insertQuestion(db, question, surveyId: surveyId, now: now)
            return question
        }
    }

    /// Appends a question version carrying every field. Pass the full intended state,
    /// not a diff. Archiving a question writes nothing to its options.
    public func updateQuestion(
        _ id: String, label: String, position: Int, isRequired: Bool, isArchived: Bool,
        scale: ScaleConfig?, allowsCustomOptions: Bool, now: Date = Date()
    ) throws {
        try dbQueue.write { db in
            guard try QuestionRow.exists(db, key: id) else { throw StoreError.notFound }
            try makeQuestionVersionRow(
                questionId: id, label: label, position: position, isRequired: isRequired,
                isArchived: isArchived, scale: scale, allowsCustomOptions: allowsCustomOptions,
                now: now
            ).insert(db)
        }
    }

    // MARK: Options

    /// Inserts an option at the end of the question: its position is one past the
    /// highest current position, archived options included, or 0 for the first.
    public func addOption(questionId: String, label: String, now: Date = Date()) throws -> ChoiceOption {
        try dbQueue.write { db in
            guard let questionRow = try QuestionRow.fetchOne(db, key: questionId) else {
                throw StoreError.notFound
            }
            let rows = try DefinitionRows.load(db, surveyId: questionRow.surveyId)
            let existing = rows.question(for: questionRow)?.options ?? []
            let position = existing.map(\.position).max().map { $0 + 1 } ?? 0
            let option = ChoiceOption(label: label, position: position)
            try insertOption(db, option, questionId: questionId, now: now)
            return option
        }
    }

    /// Appends an option version carrying every field. Pass the full intended state.
    public func updateOption(
        _ id: String, label: String, position: Int, isArchived: Bool, now: Date = Date()
    ) throws {
        try dbQueue.write { db in
            guard try OptionRow.exists(db, key: id) else { throw StoreError.notFound }
            try OptionVersionRow(
                id: Identifier.make(), optionId: id, label: label, position: position,
                isArchived: isArchived, createdAt: now
            ).insert(db)
        }
    }

    // MARK: Reading

    /// Every survey in its current view, ordered by `createdAt`, each with every
    /// question and option, archived included.
    public func surveys(includeArchived: Bool) throws -> [Survey] {
        try dbQueue.read { db in
            try DefinitionRows.load(db, surveyId: nil).currentSurveys
                .filter { includeArchived || !$0.isArchived }
        }
    }

    /// One survey in its current view, or nil if the identifier is unknown.
    public func survey(_ id: String) throws -> Survey? {
        try dbQueue.read { db in
            let rows = try DefinitionRows.load(db, surveyId: id)
            return rows.surveys.first.flatMap(rows.survey(for:))
        }
    }

    /// Name history of a survey, oldest first. Empty for an unknown identifier.
    public func labelHistory(surveyId: String) throws -> [LabelVersion] {
        try dbQueue.read { db in
            DefinitionRows.labelHistory(try SurveyVersionRow.fetchAll(
                db, sql: "SELECT * FROM surveyVersion WHERE surveyId = ? ORDER BY \(Self.versionOrder)",
                arguments: [surveyId]))
        }
    }

    /// Label history of a question, oldest first. Empty for an unknown identifier.
    public func labelHistory(questionId: String) throws -> [LabelVersion] {
        try dbQueue.read { db in
            DefinitionRows.labelHistory(try QuestionVersionRow.fetchAll(
                db, sql: "SELECT * FROM questionVersion WHERE questionId = ? ORDER BY \(Self.versionOrder)",
                arguments: [questionId]))
        }
    }

    /// Label history of an option, oldest first. Empty for an unknown identifier.
    public func labelHistory(optionId: String) throws -> [LabelVersion] {
        try dbQueue.read { db in
            DefinitionRows.labelHistory(try OptionVersionRow.fetchAll(
                db, sql: "SELECT * FROM optionVersion WHERE optionId = ? ORDER BY \(Self.versionOrder)",
                arguments: [optionId]))
        }
    }

    /// Question identifier to current version identifier, for every question of the
    /// survey, archived included. The runner calls it once when it opens and stamps
    /// `Answer.questionVersionId` from it. Empty for an unknown survey.
    public func currentQuestionVersionIds(surveyId: String) throws -> [String: String] {
        try dbQueue.read { db in
            let rows = try DefinitionRows.load(db, surveyId: surveyId)
            var ids: [String: String] = [:]
            for question in rows.questions[surveyId] ?? [] {
                if let version = rows.questionVersions[question.id]?.last {
                    ids[question.id] = version.id
                }
            }
            return ids
        }
    }

    // MARK: Row builders shared with eraseEverything

    /// The body of `createSurvey`, inside an open transaction.
    func insertSurvey(
        _ db: Database, name: String, sampling: SamplingConfig, questions: [Question], now: Date
    ) throws -> Survey {
        let surveyId = Identifier.make()
        try SurveyRow(id: surveyId, createdAt: now).insert(db)
        try SurveyVersionRow(
            id: Identifier.make(), surveyId: surveyId, name: name, isArchived: false, createdAt: now
        ).insert(db)
        try makeSamplingRow(surveyId: surveyId, sampling, now: now).insert(db)
        try Self.notificationPreviewRow(surveyId: surveyId, .default, now: now).insert(db)
        for question in questions {
            try insertQuestion(db, question, surveyId: surveyId, now: now)
        }
        let rows = try DefinitionRows.load(db, surveyId: surveyId)
        guard let surveyRow = rows.surveys.first, let survey = rows.survey(for: surveyRow) else {
            throw StoreError.notFound
        }
        return survey
    }

    private func insertQuestion(_ db: Database, _ question: Question, surveyId: String, now: Date) throws {
        try QuestionRow(id: question.id, surveyId: surveyId, kind: question.kind, createdAt: now).insert(db)
        try makeQuestionVersionRow(
            questionId: question.id, label: question.label, position: question.position,
            isRequired: question.isRequired, isArchived: question.isArchived, scale: question.scale,
            allowsCustomOptions: question.allowsCustomOptions, now: now
        ).insert(db)
        for option in question.options {
            try insertOption(db, option, questionId: question.id, now: now)
        }
    }

    private func insertOption(_ db: Database, _ option: ChoiceOption, questionId: String, now: Date) throws {
        try OptionRow(id: option.id, questionId: questionId, createdAt: now).insert(db)
        try OptionVersionRow(
            id: Identifier.make(), optionId: option.id, label: option.label,
            position: option.position, isArchived: option.isArchived, createdAt: now
        ).insert(db)
    }

    private func makeSamplingRow(surveyId: String, _ config: SamplingConfig, now: Date) -> SurveySamplingRow {
        SurveySamplingRow(
            id: Identifier.make(), surveyId: surveyId,
            promptsPerDay: config.promptsPerDay,
            windowStartMinutes: config.windowStartMinutes,
            windowEndMinutes: config.windowEndMinutes,
            minGapMinutes: config.minGapMinutes,
            expiryMinutes: config.expiryMinutes,
            isEnabled: config.isEnabled,
            createdAt: now)
    }

    private func makeQuestionVersionRow(
        questionId: String, label: String, position: Int, isRequired: Bool, isArchived: Bool,
        scale: ScaleConfig?, allowsCustomOptions: Bool, now: Date
    ) -> QuestionVersionRow {
        QuestionVersionRow(
            id: Identifier.make(), questionId: questionId, label: label, position: position,
            isRequired: isRequired, isArchived: isArchived,
            scaleMin: scale?.min, scaleMax: scale?.max,
            scaleMinLabel: scale?.minLabel, scaleMaxLabel: scale?.maxLabel,
            allowsCustomOptions: allowsCustomOptions, createdAt: now)
    }
}
