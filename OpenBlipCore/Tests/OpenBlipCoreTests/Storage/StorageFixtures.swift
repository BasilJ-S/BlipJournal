import Foundation
import Testing
import OpenBlipCore

/// Shared helpers for the Storage tests: a fixed clock, a seeded store, and ways to
/// measure what a store holds through its public API alone.
enum Fixture {
    /// A fixed instant plus `seconds`, so every test steps time explicitly.
    static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    static let t0 = at(0)

    /// An in-memory store seeded with the default template at `now`.
    static func seeded(now: Date = t0) throws -> (store: Store, survey: Survey) {
        let store = try Store.inMemory()
        return (store, try seed(store, now: now))
    }

    /// Seeds the default template into `store`, optionally under another name.
    @discardableResult
    static func seed(_ store: Store, name: String? = nil, now: Date = t0) throws -> Survey {
        let template = SurveyTemplate.makeDefault(now: now)
        return try store.createSurvey(
            name: name ?? template.name, sampling: template.sampling,
            questions: template.questions, now: now)
    }

    /// A fresh directory for tests that need a database on disk.
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("openblip-storage-tests-\(UUID().uuidString)", isDirectory: true)
    }

    /// A pending prompt for `survey` at `scheduledAt`, expiring twenty minutes later.
    static func prompt(
        _ survey: Survey, day: String = "2026-05-01", scheduledAt: Date,
        status: PromptStatus = .pending, respondedAt: Date? = nil
    ) -> Prompt {
        Prompt(
            surveyId: survey.id, day: day, scheduledAt: scheduledAt,
            expiresAt: scheduledAt.addingTimeInterval(20 * 60), status: status,
            respondedAt: respondedAt)
    }
}

extension Survey {
    /// The question with this label. Fails the test if there is none.
    func question(labelled label: String) throws -> Question {
        try #require(questions.first { $0.label == label }, "no question labelled \(label)")
    }
}

extension Question {
    /// The option with this label. Fails the test if there is none.
    func option(labelled label: String) throws -> ChoiceOption {
        try #require(options.first { $0.label == label }, "no option labelled \(label)")
    }
}

extension Store {
    /// Saves an entry with one answer per pair, each stamped with the question's
    /// current version and `answeredAt` (defaulting to `startedAt`).
    @discardableResult
    func record(
        in survey: Survey, id: String = Identifier.make(), promptId: String? = nil,
        startedAt: Date, completedAt: Date? = nil, answeredAt: Date? = nil,
        answers values: [(Question, AnswerValue)]
    ) throws -> (entry: Entry, answers: [Answer]) {
        let versionIds = try currentQuestionVersionIds(surveyId: survey.id)
        let entry = Entry(
            id: id, surveyId: survey.id, promptId: promptId, startedAt: startedAt,
            completedAt: completedAt)
        let answers = try values.map { question, value in
            Answer(
                entryId: entry.id, questionId: question.id,
                questionVersionId: try #require(versionIds[question.id]),
                answeredAt: answeredAt ?? startedAt, value: value)
        }
        try saveEntry(entry, answers: answers)
        return (entry, answers)
    }
}

extension Backup {
    /// Row count per table, keyed by table name.
    var rowCounts: [String: Int] {
        [
            "survey": surveys.count,
            "surveyVersion": surveyVersions.count,
            "surveySampling": surveySamplings.count,
            "question": questions.count,
            "questionVersion": questionVersions.count,
            "option": options.count,
            "optionVersion": optionVersions.count,
            "prompt": prompts.count,
            "entry": entries.count,
            "answer": answers.count,
            "answerOption": answerOptions.count,
        ]
    }

    /// Every version row across the four versioned tables.
    var versionRowCount: Int {
        surveyVersions.count + surveySamplings.count + questionVersions.count + optionVersions.count
    }

    /// The backup as JSON text, for "no trace of" assertions.
    func jsonString() throws -> String {
        String(decoding: try BackupExporter.json(self), as: UTF8.self)
    }

    /// The rows of this backup that belong to one survey, so another survey's rows can
    /// be compared before and after a delete.
    func restricted(to surveyId: String) -> Backup {
        let questionIds = Set(questions.filter { $0.surveyId == surveyId }.map(\.id))
        let optionIds = Set(options.filter { questionIds.contains($0.questionId) }.map(\.id))
        let entryIds = Set(entries.filter { $0.surveyId == surveyId }.map(\.id))
        let answerIds = Set(answers.filter { entryIds.contains($0.entryId) }.map(\.id))
        return Backup(
            schemaVersion: schemaVersion,
            exportedAt: exportedAt,
            surveys: surveys.filter { $0.id == surveyId },
            surveyVersions: surveyVersions.filter { $0.surveyId == surveyId },
            surveySamplings: surveySamplings.filter { $0.surveyId == surveyId },
            questions: questions.filter { questionIds.contains($0.id) },
            questionVersions: questionVersions.filter { questionIds.contains($0.questionId) },
            options: options.filter { optionIds.contains($0.id) },
            optionVersions: optionVersions.filter { optionIds.contains($0.optionId) },
            prompts: prompts.filter { $0.surveyId == surveyId },
            entries: entries.filter { entryIds.contains($0.id) },
            answers: answers.filter { answerIds.contains($0.id) },
            answerOptions: answerOptions.filter { answerIds.contains($0.answerId) })
    }
}

/// What a delete removed, measured by diffing two backups in the same terms as
/// `DeletionImpact`, so a reported impact can be checked against what actually went.
func measuredImpact(before: Backup, after: Backup, surveyLevel: Bool) -> DeletionImpact {
    let afterAnswerIds = Set(after.answers.map(\.id))
    let answersGone = before.answers.filter { !afterAnswerIds.contains($0.id) }
    let afterEntryIds = Set(after.entries.map(\.id))
    let entriesGone = before.entries.filter { !afterEntryIds.contains($0.id) }
    let touched = Set(answersGone.map(\.entryId))
    let answersPerEntryAfter = Dictionary(grouping: after.answers, by: \.entryId).mapValues(\.count)
    let emptied = touched.filter { afterEntryIds.contains($0) && answersPerEntryAfter[$0, default: 0] == 0 }
    return DeletionImpact(
        answers: answersGone.count,
        entries: surveyLevel ? entriesGone.count : touched.count,
        entriesEmptied: emptied.count,
        options: before.options.count - after.options.count,
        versions: before.versionRowCount - after.versionRowCount,
        prompts: before.prompts.count - after.prompts.count,
        oldest: answersGone.map(\.answeredAt).min(),
        newest: answersGone.map(\.answeredAt).max())
}
