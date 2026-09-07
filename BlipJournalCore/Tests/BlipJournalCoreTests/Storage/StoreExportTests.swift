import Foundation
import Testing
import BlipJournalCore

@Suite("Store export")
struct StoreExportTests {
    private let t = Fixture.at

    @Test("exportSnapshot carries the current survey, ordered entries with prompts, and full label histories")
    func snapshot() throws {
        let (store, survey) = try Fixture.seeded()
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let doing = try survey.question(labelled: "What are you doing?")
        let anything = try survey.question(labelled: "Anything else?")
        let originalVersionIds = try store.currentQuestionVersionIds(surveyId: survey.id)
        try store.updateQuestion(
            anything.id, label: "More?", position: 5, isRequired: false, isArchived: false,
            scale: nil, allowsCustomOptions: false, now: t(1))
        try store.updateQuestion(
            anything.id, label: "Notes", position: 5, isRequired: false, isArchived: true,
            scale: nil, allowsCustomOptions: false, now: t(2))
        let working = try doing.option(labelled: "Working")
        try store.updateOption(working.id, label: "At work", position: working.position, isArchived: true, now: t(3))
        let added = try store.addOption(questionId: doing.id, label: "Gardening", now: t(4))
        let prompt = Fixture.prompt(survey, scheduledAt: t(90), status: .answered, respondedAt: t(100))
        try store.insertPrompts([prompt])
        // Inserted out of order; the snapshot must sort by startedAt.
        let (later, laterAnswers) = try store.record(
            in: survey, startedAt: t(300), answers: [(feeling, .scale(6)), (doing, .single(optionId: added.id))])
        let (earlier, earlierAnswers) = try store.record(
            in: survey, promptId: prompt.id, startedAt: t(100), completedAt: t(110),
            answers: [(feeling, .scale(2)), (doing, .single(optionId: working.id)), (anything, .text("hi"))])
        let (partial, _) = try store.record(in: survey, startedAt: t(200), answers: [])

        let snapshot = try store.exportSnapshot(surveyId: survey.id)

        #expect(try snapshot.survey == store.survey(survey.id))
        #expect(snapshot.entries.map(\.entry) == [earlier, partial, later])
        #expect(snapshot.entries[0].prompt == prompt)
        #expect(snapshot.entries[1].prompt == nil)
        #expect(snapshot.entries[2].prompt == nil)
        #expect(Set(snapshot.entries[0].answers) == Set(earlierAnswers))
        #expect(snapshot.entries[1].answers.isEmpty)
        #expect(Set(snapshot.entries[2].answers) == Set(laterAnswers))

        #expect(Set(snapshot.questionLabelHistory.keys) == Set(survey.questions.map(\.id)))
        #expect(snapshot.questionLabelHistory[anything.id] == [
            LabelVersion(label: "Anything else?", validFrom: t(0)),
            LabelVersion(label: "More?", validFrom: t(1)),
            LabelVersion(label: "Notes", validFrom: t(2)),
        ])
        #expect(snapshot.questionLabelHistory[feeling.id]?.count == 1)

        let optionIds = snapshot.survey.questions.flatMap { $0.options.map(\.id) }
        #expect(optionIds.count == 42)
        #expect(Set(snapshot.optionLabelHistory.keys) == Set(optionIds))
        #expect(snapshot.optionLabelHistory[working.id] == [
            LabelVersion(label: "Working", validFrom: t(0)),
            LabelVersion(label: "At work", validFrom: t(3)),
        ])
        #expect(snapshot.optionLabelHistory[added.id] == [LabelVersion(label: "Gardening", validFrom: t(4))])

        #expect(snapshot.questionVersionLabels.count == 6 + 2)
        let versionIds = try store.currentQuestionVersionIds(surveyId: survey.id)
        #expect(snapshot.questionVersionLabels[try #require(versionIds[anything.id])] == "Notes")
        #expect(snapshot.questionVersionLabels[earlierAnswers[2].questionVersionId] == "Notes")
        #expect(snapshot.questionVersionLabels[try #require(originalVersionIds[anything.id])] == "Anything else?")
        #expect(Set(snapshot.questionVersionLabels.values) == Set([
            "How are you feeling right now?", "What best describes this feeling?",
            "What is having the biggest impact?", "What are you doing?", "Who are you with?",
            "Anything else?", "More?", "Notes",
        ]))
        #expect(throws: StoreError.notFound) { try store.exportSnapshot(surveyId: "x") }
    }

    @Test("an answer recorded before a rename keeps resolving to the wording it was given under")
    func recoverabilityAcrossRename() throws {
        let (store, survey) = try Fixture.seeded()
        let anything = try survey.question(labelled: "Anything else?")
        let (entry, answers) = try store.record(in: survey, startedAt: t(100), answers: [(anything, .text("first"))])
        let pinned = answers[0]

        try store.updateQuestion(
            anything.id, label: "Renamed", position: 5, isRequired: false, isArchived: false,
            scale: nil, allowsCustomOptions: false, now: t(200))
        // An autosave after the rename re-saves the same answer; the pin must survive.
        var revised = pinned
        revised.value = .text("second")
        try store.saveEntry(entry, answers: [revised])

        let snapshot = try store.exportSnapshot(surveyId: survey.id)
        let stored = try #require(snapshot.entries.first?.answers.first)
        #expect(stored.questionVersionId == pinned.questionVersionId)
        #expect(stored.answeredAt == t(100))
        #expect(stored.value == .text("second"))
        #expect(snapshot.questionVersionLabels[stored.questionVersionId] == "Anything else?")
        #expect(snapshot.survey.questions.first { $0.id == anything.id }?.label == "Renamed")
        #expect(snapshot.questionLabelHistory[anything.id]?.label(at: t(100)) == "Anything else?")
        #expect(snapshot.questionLabelHistory[anything.id]?.label(at: t(200)) == "Renamed")
    }

    @Test("a backup with millisecond timestamps decodes back equal, including exportedAt")
    func backupRoundTripsMilliseconds() throws {
        let store = try Store.inMemory()
        let survey = try Fixture.seed(store, now: t(0.123))
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        try store.record(in: survey, startedAt: t(100.999), answeredAt: t(101.001), answers: [(feeling, .scale(4))])

        let backup = try store.backup(now: t(200.4567))
        let json = try BackupExporter.json(backup)
        let decoded = try BackupExporter.decode(json)

        #expect(decoded == backup)
        #expect(try BackupExporter.json(decoded) == json)
        #expect(backup.surveys.first?.createdAt == t(0.123))
        #expect(backup.answers.first?.answeredAt == t(101.001))
        #expect(backup.exportedAt == t(200.457))
        #expect(String(decoding: json, as: UTF8.self).contains("T06:16:40.457Z"))
    }

    @Test("exportSnapshot of one survey does not include another survey's entries")
    func snapshotIsPerSurvey() throws {
        let store = try Store.inMemory()
        let a = try Fixture.seed(store, name: "A", now: t(0))
        let b = try Fixture.seed(store, name: "B", now: t(1))
        let (entry, _) = try store.record(in: a, startedAt: t(100), answers: [])
        try store.record(in: b, startedAt: t(100), answers: [])

        let snapshot = try store.exportSnapshot(surveyId: a.id)
        #expect(snapshot.entries.map(\.entry) == [entry])
        #expect(snapshot.survey.name == "A")
    }

    @Test("backup then json is byte-identical across two calls and decodes back to an equal Backup")
    func backupIsDeterministic() throws {
        let (store, survey) = try Fixture.seeded()
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let doing = try survey.question(labelled: "What are you doing?")
        let prompt = Fixture.prompt(survey, scheduledAt: t(90))
        try store.insertPrompts([prompt])
        try store.record(in: survey, promptId: prompt.id, startedAt: t(100), answers: [
            (feeling, .scale(5)), (doing, .single(optionId: try doing.option(labelled: "Resting").id)),
        ])
        try store.renameSurvey(survey.id, to: "Renamed", now: t(5))
        try store.renameSurvey(survey.id, to: "Renamed again", now: t(5))

        let first = try store.backup(now: t(500))
        let second = try store.backup(now: t(500))
        let firstJSON = try BackupExporter.json(first)
        #expect(first == second)
        #expect(try firstJSON == BackupExporter.json(second))
        #expect(try BackupExporter.decode(firstJSON) == first)

        #expect(first.schemaVersion == 4)
        #expect(first.exportedAt == t(500))
        #expect(first.rowCounts == [
            "survey": 1, "surveyVersion": 3, "surveySampling": 1, "surveyNotificationPreview": 1,
            "question": 6, "questionVersion": 6,
            "option": 41, "optionVersion": 41, "prompt": 1, "entry": 1, "answer": 2, "answerOption": 1,
        ])
        #expect(first.surveyVersions.map(\.name) == ["Check-in", "Renamed", "Renamed again"])
        #expect(first.questions.map(\.id) == first.questions.map(\.id).sorted())
        #expect(first.options.map(\.id) == first.options.map(\.id).sorted())
        let text = String(decoding: firstJSON, as: UTF8.self)
        #expect(text.contains("\"exportedAt\" : \"2026-05-"))
        #expect(text.contains("\"kind\" : \"singleChoice\""))
    }
}
