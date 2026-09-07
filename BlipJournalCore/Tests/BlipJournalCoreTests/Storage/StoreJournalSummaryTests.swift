import Foundation
import GRDB
import Testing
@testable import BlipJournalCore

@Suite("Store Journal summary")
struct StoreJournalSummaryTests {
    private let t = Fixture.at

    @Test("a new survey defaults to its first mood question")
    func defaultsToFirstMood() throws {
        let (store, created) = try Fixture.seeded()
        let survey = try #require(try store.survey(created.id))
        #expect(survey.journalSummaryQuestionIds == [survey.activeQuestions[0].id])
    }

    @Test("one or two active questions can be selected in display order, including none")
    func updatesSelection() throws {
        let (store, survey) = try Fixture.seeded()
        let activity = try survey.question(labelled: "What are you doing?")
        let mood = try survey.question(labelled: "How are you feeling right now?")

        try store.updateJournalSummaryQuestions(
            surveyId: survey.id, questionIds: [activity.id, mood.id], now: t(1))
        #expect(try store.survey(survey.id)?.journalSummaryQuestionIds == [activity.id, mood.id])

        try store.updateJournalSummaryQuestions(surveyId: survey.id, questionIds: [], now: t(2))
        #expect(try store.survey(survey.id)?.journalSummaryQuestionIds.isEmpty == true)
    }

    @Test("invalid selections do not append a survey version")
    func rejectsInvalidSelection() throws {
        let (store, survey) = try Fixture.seeded()
        let first = survey.activeQuestions[0].id
        let before = try store.backup(now: t(1)).surveyVersions.count

        for ids in [[first, first], [first, "missing"], [first, "a", "b"]] {
            #expect(throws: StoreError.invalidJournalSummary) {
                try store.updateJournalSummaryQuestions(
                    surveyId: survey.id, questionIds: ids, now: t(2))
            }
        }
        #expect(try store.backup(now: t(3)).surveyVersions.count == before)
    }

    @Test("renaming a survey preserves its Journal summary")
    func renamePreservesSelection() throws {
        let (store, survey) = try Fixture.seeded()
        let ids = [survey.activeQuestions[3].id, survey.activeQuestions[0].id]
        try store.updateJournalSummaryQuestions(surveyId: survey.id, questionIds: ids, now: t(1))
        try store.renameSurvey(survey.id, to: "Renamed", now: t(2))
        #expect(try store.survey(survey.id)?.journalSummaryQuestionIds == ids)
    }

    @Test("archiving a selected question omits it from the resolved summary")
    func archivedQuestionIsOmitted() throws {
        let (store, survey) = try Fixture.seeded()
        let mood = survey.activeQuestions[0]
        let activity = survey.activeQuestions[3]
        try store.updateJournalSummaryQuestions(
            surveyId: survey.id, questionIds: [mood.id, activity.id], now: t(1))
        try store.updateQuestion(
            mood.id, label: mood.label, position: mood.position,
            isRequired: mood.isRequired, isArchived: true, scale: mood.scale,
            spectrum: mood.spectrum,
            allowsCustomOptions: mood.allowsCustomOptions, now: t(2))

        #expect(try store.survey(survey.id)?.journalSummaryQuestionIds == [activity.id])
    }

    @Test("a pre-v3 survey preserves the former first-scale summary")
    func migrationFallback() throws {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(Store.databaseFileName).path

        do {
            var v1Only = DatabaseMigrator()
            v1Only.registerMigration("v1", migrate: Schema.migrateV1)
            let queue = try DatabaseQueue(path: path)
            try v1Only.migrate(queue)
            let question = Question(
                id: "q1", kind: .scale, label: "Mood", position: 0,
                scale: ScaleConfig())
            try queue.write { db in
                try SurveyRow(id: "s1", createdAt: t(0)).insert(db)
                try db.execute(
                    sql: "INSERT INTO surveyVersion (id, surveyId, name, isArchived, createdAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: ["sv1", "s1", "Old", false, t(0)])
                for question in [question] {
                    try QuestionRow(
                        id: question.id, surveyId: "s1", kind: question.kind,
                        createdAt: t(0)).insert(db)
                    try db.execute(
                        sql: """
                            INSERT INTO questionVersion
                                (id, questionId, label, position, isRequired, isArchived,
                                 scaleMin, scaleMax, scaleMinLabel, scaleMaxLabel,
                                 allowsCustomOptions, createdAt)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            Identifier.make(), question.id, question.label, question.position,
                            question.isRequired, false, question.scale?.min, question.scale?.max,
                            question.scale?.minLabel, question.scale?.maxLabel,
                            question.allowsCustomOptions, t(0),
                        ])
                }
            }
        }

        let survey = try #require(try Store.open(at: directory).survey("s1"))
        #expect(survey.journalSummaryQuestionIds == [survey.activeQuestions[0].id])
    }
}
