import Foundation
import Testing
import BlipJournalCore

/// A seeded store with four entries that between them exercise every hard-delete rule.
///
/// ```
/// e1 (prompted, t100): feeling 5, describes [Calm, Happy], doing Working, anything "note one"
/// e2 (t200):           describes [Calm], doing Resting
/// e3 (t300):           doing Working                       -> emptied by deleting "doing" or "Working"
/// e4 (t400):           describes [Happy], anything "note four"
/// ```
private struct HardDeleteFixture {
    let store: Store
    let survey: Survey
    let feeling: Question
    let describes: Question
    let doing: Question
    let anything: Question
    let calm: ChoiceOption
    let happy: ChoiceOption
    let working: ChoiceOption
    let resting: ChoiceOption
    let prompt: Prompt
    let e1: Entry
    let e2: Entry
    let e3: Entry
    let e4: Entry

    static func make(now: Date = Fixture.t0) throws -> HardDeleteFixture {
        let t = Fixture.at
        let store = try Store.inMemory()
        let survey = try Fixture.seed(store, now: now)
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let describes = try survey.question(labelled: "What best describes this feeling?")
        let doing = try survey.question(labelled: "What are you doing?")
        let anything = try survey.question(labelled: "Anything else?")
        let calm = try describes.option(labelled: "Calm")
        let happy = try describes.option(labelled: "Happy")
        let working = try doing.option(labelled: "Working")
        let resting = try doing.option(labelled: "Resting")
        let prompt = Fixture.prompt(survey, scheduledAt: t(90), status: .answered, respondedAt: t(100))
        try store.insertPrompts([prompt, Fixture.prompt(survey, scheduledAt: t(900))])
        let e1 = try store.record(in: survey, promptId: prompt.id, startedAt: t(100), completedAt: t(110), answers: [
            (feeling, .scale(5)), (describes, .multi(optionIds: [calm.id, happy.id])),
            (doing, .single(optionId: working.id)), (anything, .text("note one")),
        ]).entry
        let e2 = try store.record(in: survey, startedAt: t(200), answers: [
            (describes, .multi(optionIds: [calm.id])), (doing, .single(optionId: resting.id)),
        ]).entry
        let e3 = try store.record(in: survey, startedAt: t(300), answers: [
            (doing, .single(optionId: working.id)),
        ]).entry
        let e4 = try store.record(in: survey, startedAt: t(400), answers: [
            (describes, .multi(optionIds: [happy.id])), (anything, .text("note four")),
        ]).entry
        return HardDeleteFixture(
            store: store, survey: survey, feeling: feeling, describes: describes, doing: doing,
            anything: anything, calm: calm, happy: happy, working: working, resting: resting,
            prompt: prompt, e1: e1, e2: e2, e3: e3, e4: e4)
    }

    func archive(_ option: ChoiceOption, now: Date) throws {
        try store.updateOption(option.id, label: option.label, position: option.position, isArchived: true, now: now)
    }

    func archive(_ question: Question, now: Date) throws {
        try store.updateQuestion(
            question.id, label: question.label, position: question.position, isRequired: question.isRequired,
            isArchived: true, scale: question.scale, allowsCustomOptions: question.allowsCustomOptions, now: now)
    }

    /// Runs `delete` and checks the impact it reported against the rows that went.
    func expectImpactMatchesDelta(
        _ impact: DeletionImpact, surveyLevel: Bool = false, _ delete: () throws -> Void
    ) throws -> (before: Backup, after: Backup) {
        let before = try store.backup(now: Fixture.t0)
        try delete()
        let after = try store.backup(now: Fixture.t0)
        #expect(impact == measuredImpact(before: before, after: after, surveyLevel: surveyLevel))
        return (before, after)
    }
}

@Suite("Store hard delete")
struct StoreHardDeleteTests {
    private let t = Fixture.at

    @Test("every hard delete and impact refuses an unarchived target and an unknown ID")
    func refusals() throws {
        let f = try HardDeleteFixture.make()
        #expect(throws: StoreError.notArchived) { try f.store.hardDeleteSurvey(f.survey.id) }
        #expect(throws: StoreError.notArchived) { try f.store.hardDeleteQuestion(f.doing.id) }
        #expect(throws: StoreError.notArchived) { try f.store.hardDeleteOption(f.working.id) }
        #expect(throws: StoreError.notArchived) { try f.store.deletionImpact(surveyId: f.survey.id) }
        #expect(throws: StoreError.notArchived) { try f.store.deletionImpact(questionId: f.doing.id) }
        #expect(throws: StoreError.notArchived) { try f.store.deletionImpact(optionId: f.working.id) }
        #expect(throws: StoreError.notFound) { try f.store.hardDeleteSurvey("x") }
        #expect(throws: StoreError.notFound) { try f.store.hardDeleteQuestion("x") }
        #expect(throws: StoreError.notFound) { try f.store.hardDeleteOption("x") }
        #expect(throws: StoreError.notFound) { try f.store.deletionImpact(surveyId: "x") }
        #expect(throws: StoreError.notFound) { try f.store.deletionImpact(questionId: "x") }
        #expect(throws: StoreError.notFound) { try f.store.deletionImpact(optionId: "x") }
        // Nothing moved.
        #expect(try f.store.backup(now: t(0)).rowCounts["answer"] == 9)
    }

    @Test("deleting an option removes single-choice answers that named it and prunes multi-choice ones")
    func deleteOption() throws {
        let f = try HardDeleteFixture.make()
        try f.archive(f.working, now: t(1))
        try f.archive(f.calm, now: t(2))

        // "Working": named by single-choice answers in e1 and e3; e3 has nothing else.
        let workingImpact = try f.store.deletionImpact(optionId: f.working.id)
        #expect(workingImpact == DeletionImpact(
            answers: 2, entries: 2, entriesEmptied: 1, options: 1, versions: 2, prompts: 0,
            oldest: t(100), newest: t(300)))
        let (before, after) = try f.expectImpactMatchesDelta(workingImpact) {
            try f.store.hardDeleteOption(f.working.id)
        }
        #expect(before.answerOptions.count - after.answerOptions.count == 2)
        #expect(after.rowCounts["entry"] == 4)
        #expect(try f.store.answers(entryId: f.e3.id).isEmpty)
        #expect(try f.store.answers(entryId: f.e1.id).count == 3)
        #expect(try f.store.answers(entryId: f.e2.id).first { $0.questionId == f.doing.id }?.value == .single(optionId: f.resting.id))

        // "Calm": e1 keeps [Happy]; e2's multi answer was only [Calm] and goes.
        let calmImpact = try f.store.deletionImpact(optionId: f.calm.id)
        #expect(calmImpact == DeletionImpact(
            answers: 1, entries: 1, entriesEmptied: 0, options: 1, versions: 2, prompts: 0,
            oldest: t(200), newest: t(200)))
        _ = try f.expectImpactMatchesDelta(calmImpact) { try f.store.hardDeleteOption(f.calm.id) }
        #expect(try f.store.answers(entryId: f.e1.id).first { $0.questionId == f.describes.id }?.value
            == .multi(optionIds: [f.happy.id]))
        #expect(try f.store.answers(entryId: f.e2.id).map(\.questionId) == [f.doing.id])
        #expect(try f.store.answers(entryId: f.e4.id).first { $0.questionId == f.describes.id }?.value
            == .multi(optionIds: [f.happy.id]))

        let survey = try #require(try f.store.survey(f.survey.id))
        #expect(try survey.question(labelled: f.doing.label).options.count == 9)
        #expect(try survey.question(labelled: f.describes.label).options.count == 11)
        #expect(try f.store.labelHistory(optionId: f.working.id).isEmpty)
        #expect(!(try f.store.backup(now: t(0)).jsonString().contains("Working")))
    }

    @Test("deleting a question removes its options and answers but leaves entries and sibling answers")
    func deleteQuestion() throws {
        let f = try HardDeleteFixture.make()
        try f.archive(f.doing, now: t(1))
        try f.archive(f.working, now: t(2))    // an archived option inside: still just a version row

        let siblingsBefore = try [f.e1, f.e2, f.e4].map { entry in
            try f.store.answers(entryId: entry.id).filter { $0.questionId != f.doing.id }
        }

        let impact = try f.store.deletionImpact(questionId: f.doing.id)
        #expect(impact == DeletionImpact(
            answers: 3, entries: 3, entriesEmptied: 1, options: 10, versions: 2 + 11, prompts: 0,
            oldest: t(100), newest: t(300)))
        let (before, after) = try f.expectImpactMatchesDelta(impact) { try f.store.hardDeleteQuestion(f.doing.id) }

        // Sibling answers are untouched by value, not just by count.
        for (entry, expected) in zip([f.e1, f.e2, f.e4], siblingsBefore) {
            #expect(try f.store.answers(entryId: entry.id) == expected)
        }
        #expect(siblingsBefore.map(\.count) == [3, 1, 2])

        #expect(after.rowCounts["entry"] == 4)
        #expect(after.rowCounts["prompt"] == 2)
        #expect(after.rowCounts["question"] == 5)
        #expect(after.rowCounts["questionVersion"] == 5)
        #expect(after.rowCounts["option"] == 31)
        #expect(after.rowCounts["optionVersion"] == 31)
        #expect(before.answerOptions.count - after.answerOptions.count == 3)
        #expect(try f.store.answers(entryId: f.e3.id).isEmpty)
        #expect(try f.store.entries(surveyId: f.survey.id, from: nil, to: nil).map(\.id) == [f.e1.id, f.e2.id, f.e3.id, f.e4.id])
        #expect(try f.store.answers(entryId: f.e1.id).map(\.questionId) == [f.feeling.id, f.describes.id, f.anything.id])
        #expect(try f.store.answers(entryId: f.e4.id).count == 2)
        let survey = try #require(try f.store.survey(f.survey.id))
        #expect(survey.questions.count == 5)
        #expect(survey.questions.map(\.id).contains(f.doing.id) == false)
        #expect(try f.store.labelHistory(questionId: f.doing.id).isEmpty)
        #expect(!(try f.store.backup(now: t(0)).jsonString().contains("What are you doing?")))
    }

    @Test("deleting a survey removes all of its rows and leaves a second survey untouched at every table")
    func deleteSurvey() throws {
        let f = try HardDeleteFixture.make()
        let other = try Fixture.seed(f.store, name: "Other", now: t(1))
        let otherDoing = try other.question(labelled: "What are you doing?")
        let otherPrompt = Fixture.prompt(other, scheduledAt: t(95))
        try f.store.insertPrompts([otherPrompt])
        try f.store.record(in: other, promptId: otherPrompt.id, startedAt: t(150), answers: [
            (otherDoing, .single(optionId: try otherDoing.option(labelled: "Eating").id)),
        ])
        // An entry with no answers goes too, and the survey-level count says so.
        try f.store.record(in: f.survey, startedAt: t(450), answers: [])
        try f.store.renameSurvey(f.survey.id, to: "Old", now: t(2))
        try f.store.archiveSurvey(f.survey.id, now: t(3))

        let impact = try f.store.deletionImpact(surveyId: f.survey.id)
        #expect(impact == DeletionImpact(
            answers: 9, entries: 5, entriesEmptied: 0, options: 41, versions: 3 + 1 + 1 + 6 + 41, prompts: 2,
            oldest: t(100), newest: t(400)))
        let (before, after) = try f.expectImpactMatchesDelta(impact, surveyLevel: true) {
            try f.store.hardDeleteSurvey(f.survey.id)
        }

        #expect(after == after.restricted(to: other.id))
        #expect(after.restricted(to: other.id) == before.restricted(to: other.id))
        #expect(after.rowCounts == [
            "survey": 1, "surveyVersion": 1, "surveySampling": 1, "surveyNotificationPreview": 1,
            "question": 6, "questionVersion": 6,
            "option": 41, "optionVersion": 41, "prompt": 1, "entry": 1, "answer": 1, "answerOption": 1,
        ])
        #expect(try f.store.survey(f.survey.id) == nil)
        #expect(try f.store.surveys(includeArchived: true).map(\.id) == [other.id])
        #expect(!(try after.jsonString().contains("note one")))
        #expect(!(try after.jsonString().contains("Old")))
    }

    @Test("eraseEverything leaves exactly the reseeded template and nothing else")
    func eraseEverything() throws {
        let f = try HardDeleteFixture.make()
        try Fixture.seed(f.store, name: "Other", now: t(1))
        try f.store.renameSurvey(f.survey.id, to: "Old", now: t(2))

        let reseeded = try f.store.eraseEverything(now: t(10))

        let backup = try f.store.backup(now: t(11))
        #expect(backup.rowCounts == [
            "survey": 1, "surveyVersion": 1, "surveySampling": 1, "surveyNotificationPreview": 1,
            "question": 6, "questionVersion": 6,
            "option": 41, "optionVersion": 41, "prompt": 0, "entry": 0, "answer": 0, "answerOption": 0,
        ])
        #expect(try f.store.surveys(includeArchived: true) == [reseeded])
        #expect(reseeded.createdAt == t(10))
        #expect(reseeded.id != f.survey.id)
        // Paused reset: sampling.isEnabled is the one field overridden from the template.
        #expect(reseeded.sampling.isEnabled == false)
        #expect(reseeded.notificationPreview == .private)
        var expected = SurveyTemplate.makeDefault(now: t(10))
        expected.id = reseeded.id
        expected.questions = reseeded.questions    // fresh identifiers; compare content below
        expected.sampling.isEnabled = false
        #expect(reseeded == expected)
        #expect(reseeded.activeQuestions.map(\.label) == SurveyTemplate.makeDefault().activeQuestions.map(\.label))
        #expect(backup.surveyVersions.first?.createdAt == t(10))
        let text = try backup.jsonString()
        #expect(!text.contains("note one"))
        #expect(!text.contains("Old"))
        #expect(!text.contains(f.survey.id))
    }

    @Test("every destructive path leaves no sentinel bytes in the database files")
    func byteErasure() throws {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try Store.open(at: directory)
        let survey = try Fixture.seed(store, now: t(0))
        let anything = try survey.question(labelled: "Anything else?")
        let doing = try survey.question(labelled: "What are you doing?")

        func filesContain(_ sentinel: String) -> Bool {
            let needle = Data(sentinel.utf8)
            return ["", "-journal", "-wal", "-shm"]
                .map { directory.appendingPathComponent(Store.databaseFileName + $0) }
                .compactMap { try? Data(contentsOf: $0) }
                .contains { $0.range(of: needle) != nil }
        }
        func sentinel(_ path: String) -> String { "SENTINEL-\(path)-\(UUID().uuidString)" }

        // deleteEntry: a free-text answer.
        let entryText = sentinel("ENTRY")
        let (entry, _) = try store.record(in: survey, startedAt: t(100), answers: [(anything, .text(entryText))])
        #expect(filesContain(entryText))
        try store.deleteEntry(entry.id)
        #expect(!filesContain(entryText))

        // hardDeleteOption: an option label, also named by an answer.
        let optionLabel = sentinel("OPTION")
        let option = try store.addOption(questionId: doing.id, label: optionLabel, now: t(200))
        try store.record(in: survey, startedAt: t(201), answers: [(doing, .single(optionId: option.id))])
        try store.updateOption(option.id, label: optionLabel, position: option.position, isArchived: true, now: t(202))
        #expect(filesContain(optionLabel))
        try store.hardDeleteOption(option.id)
        #expect(!filesContain(optionLabel))

        // hardDeleteQuestion: a question label with a text answer under it.
        let questionLabel = sentinel("QUESTION")
        let questionText = sentinel("QUESTION-ANSWER")
        let question = try store.addQuestion(
            surveyId: survey.id, kind: .text, label: questionLabel, isRequired: false,
            scale: nil, allowsCustomOptions: false, now: t(300))
        try store.record(in: survey, startedAt: t(301), answers: [(question, .text(questionText))])
        try store.updateQuestion(
            question.id, label: questionLabel, position: question.position, isRequired: false,
            isArchived: true, scale: nil, allowsCustomOptions: false, now: t(302))
        #expect(filesContain(questionLabel) && filesContain(questionText))
        try store.hardDeleteQuestion(question.id)
        #expect(!filesContain(questionLabel) && !filesContain(questionText))

        // hardDeleteSurvey: a survey name with an answered entry.
        let surveyName = sentinel("SURVEY")
        let surveyText = sentinel("SURVEY-ANSWER")
        let doomed = try Fixture.seed(store, name: surveyName, now: t(400))
        try store.record(
            in: doomed, startedAt: t(401),
            answers: [(try doomed.question(labelled: "Anything else?"), .text(surveyText))])
        try store.archiveSurvey(doomed.id, now: t(402))
        #expect(filesContain(surveyName) && filesContain(surveyText))
        try store.hardDeleteSurvey(doomed.id)
        #expect(!filesContain(surveyName) && !filesContain(surveyText))

        // eraseEverything: a renamed question and a text answer in the remaining survey.
        let everythingLabel = sentinel("ALL")
        let everythingText = sentinel("ALL-ANSWER")
        try store.updateQuestion(
            anything.id, label: everythingLabel, position: 5, isRequired: false, isArchived: false,
            scale: nil, allowsCustomOptions: false, now: t(500))
        try store.record(in: survey, startedAt: t(501), answers: [(anything, .text(everythingText))])
        #expect(filesContain(everythingLabel) && filesContain(everythingText))
        try store.eraseEverything(now: t(502))
        #expect(!filesContain(everythingLabel) && !filesContain(everythingText))

        let text = try store.backup(now: t(600)).jsonString()
        for value in [entryText, optionLabel, questionLabel, questionText, surveyName, surveyText, everythingLabel, everythingText] {
            #expect(!filesContain(value))
            #expect(!text.contains(value))
        }
    }
}
