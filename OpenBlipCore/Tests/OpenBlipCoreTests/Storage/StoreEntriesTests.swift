import Foundation
import Testing
import OpenBlipCore

@Suite("Store entries")
struct StoreEntriesTests {
    private let t = Fixture.at

    @Test("saveEntry twice with the same entry ID upserts: one entry row, answers reconciled by ID")
    func saveTwice() throws {
        let (store, survey) = try Fixture.seeded()
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let doing = try survey.question(labelled: "What are you doing?")
        let with = try survey.question(labelled: "Who are you with?")
        let anything = try survey.question(labelled: "Anything else?")
        let working = try doing.option(labelled: "Working")
        let resting = try doing.option(labelled: "Resting")
        let alone = try with.option(labelled: "Alone")
        let versionIds = try store.currentQuestionVersionIds(surveyId: survey.id)
        let entry = Entry(surveyId: survey.id, startedAt: t(100))
        let kept = Answer(
            entryId: entry.id, questionId: feeling.id, questionVersionId: try #require(versionIds[feeling.id]),
            answeredAt: t(101), value: .scale(3))
        let dropped = Answer(
            entryId: entry.id, questionId: with.id, questionVersionId: try #require(versionIds[with.id]),
            answeredAt: t(102), value: .multi(optionIds: [alone.id]))
        let choice = Answer(
            entryId: entry.id, questionId: doing.id, questionVersionId: try #require(versionIds[doing.id]),
            answeredAt: t(103), value: .single(optionId: working.id))
        try store.saveEntry(entry, answers: [kept, dropped, choice])
        #expect(try store.backup(now: t(0)).rowCounts["answerOption"] == 2)

        var completed = entry
        completed.completedAt = t(200)
        var keptAgain = kept
        keptAgain.answeredAt = t(150)    // must be ignored: the stored answeredAt wins
        keptAgain.value = .scale(6)
        var choiceAgain = choice
        choiceAgain.value = .single(optionId: resting.id)
        let added = Answer(
            entryId: entry.id, questionId: anything.id, questionVersionId: try #require(versionIds[anything.id]),
            answeredAt: t(160), value: .text("later"))
        try store.saveEntry(completed, answers: [keptAgain, choiceAgain, added])

        #expect(try store.entries(surveyId: nil, from: nil, to: nil) == [completed])
        let answers = try store.answers(entryId: entry.id)
        #expect(answers.count == 3)
        let keptStored = try #require(answers.first { $0.id == kept.id })
        #expect(keptStored.answeredAt == t(101))
        #expect(keptStored.value == .scale(6))
        #expect(answers.first { $0.id == choice.id }?.value == .single(optionId: resting.id))
        #expect(answers.first { $0.id == dropped.id } == nil)
        #expect(answers.first { $0.id == added.id } == added)
        let backup = try store.backup(now: t(0))
        #expect(backup.rowCounts["entry"] == 1)
        #expect(backup.rowCounts["answer"] == 3)
        #expect(backup.rowCounts["answerOption"] == 1)
        #expect(backup.answerOptions.first?.optionId == resting.id)
    }

    @Test("saveEntry with two answers to one question in a single call throws and writes nothing")
    func oneAnswerPerQuestion() throws {
        let (store, survey) = try Fixture.seeded()
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let versionId = try #require(try store.currentQuestionVersionIds(surveyId: survey.id)[feeling.id])
        let entry = Entry(surveyId: survey.id, startedAt: t(100))
        let answers = [3, 4].map { value in
            Answer(entryId: entry.id, questionId: feeling.id, questionVersionId: versionId,
                   answeredAt: t(100), value: .scale(value))
        }

        #expect(throws: (any Error).self) { try store.saveEntry(entry, answers: answers) }

        // The transaction rolled back: not even the entry row was kept.
        #expect(try store.entries(surveyId: nil, from: nil, to: nil).isEmpty)
        #expect(try store.backup(now: t(0)).rowCounts["answer"] == 0)

        // A later save may still move the question's answer to a new identifier.
        try store.saveEntry(entry, answers: [answers[0]])
        try store.saveEntry(entry, answers: [answers[1]])
        #expect(try store.answers(entryId: entry.id).map(\.id) == [answers[1].id])
    }

    @Test("every answer kind round-trips, including a multi-choice answer with no selections")
    func valuesRoundTrip() throws {
        let (store, survey) = try Fixture.seeded()
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let describes = try survey.question(labelled: "What best describes this feeling?")
        let impact = try survey.question(labelled: "What is having the biggest impact?")
        let doing = try survey.question(labelled: "What are you doing?")
        let anything = try survey.question(labelled: "Anything else?")
        let yesNo = try store.addQuestion(
            surveyId: survey.id, kind: .yesNo, label: "Slept well?", isRequired: false,
            scale: nil, allowsCustomOptions: false, now: t(1))
        let tired = try describes.option(labelled: "Tired")
        let calm = try describes.option(labelled: "Calm")
        let sad = try describes.option(labelled: "Sad")

        let (_, answers) = try store.record(in: survey, startedAt: t(100), answers: [
            (feeling, .scale(7)),
            (describes, .multi(optionIds: [tired.id, calm.id, sad.id, calm.id])),
            (impact, .multi(optionIds: [])),
            (doing, .single(optionId: try doing.option(labelled: "Eating").id)),
            (yesNo, .yesNo(false)),
            (anything, .text("")),
        ])

        let stored = try store.answers(entryId: answers[0].entryId)
        #expect(stored.count == 6)
        for answer in answers {
            let match = try #require(stored.first { $0.id == answer.id })
            if answer.questionId == describes.id {
                // Duplicates collapse; the caller's order is kept.
                #expect(match.value == .multi(optionIds: [tired.id, calm.id, sad.id]))
            } else {
                #expect(match == answer)
            }
        }
        #expect(stored.first { $0.questionId == impact.id }?.value == .multi(optionIds: []))
        #expect(stored.first { $0.questionId == impact.id }?.value.isEmpty == true)
    }

    @Test("entries(surveyId:from:to:) is inclusive of from, exclusive of to, ascending, and nil means unbounded")
    func entryBounds() throws {
        let store = try Store.inMemory()
        let a = try Fixture.seed(store, name: "A", now: t(0))
        let b = try Fixture.seed(store, name: "B", now: t(1))
        let e3 = try store.record(in: a, startedAt: t(300), answers: []).entry
        let e1 = try store.record(in: a, startedAt: t(100), answers: []).entry
        let e2 = try store.record(in: a, startedAt: t(200), answers: []).entry
        let other = try store.record(in: b, startedAt: t(200), answers: []).entry

        #expect(try store.entries(surveyId: a.id, from: nil, to: nil) == [e1, e2, e3])
        #expect(try store.entries(surveyId: a.id, from: t(100), to: t(300)) == [e1, e2])
        #expect(try store.entries(surveyId: a.id, from: t(101), to: t(301)) == [e2, e3])
        #expect(try store.entries(surveyId: a.id, from: t(200), to: t(200)).isEmpty)
        #expect(try store.entries(surveyId: a.id, from: nil, to: t(200)) == [e1])
        #expect(try store.entries(surveyId: a.id, from: t(200), to: nil) == [e2, e3])
        #expect(try store.entries(surveyId: nil, from: t(200), to: t(201)) == [e2, other])
        #expect(try store.entries(surveyId: b.id, from: nil, to: nil) == [other])
        #expect(try store.answers(entryId: "x").isEmpty)
    }

    @Test("deleteEntry removes the entry and its answers but leaves the prompt answered")
    func deleteEntry() throws {
        let (store, survey) = try Fixture.seeded()
        let prompt = Fixture.prompt(survey, scheduledAt: t(90))
        try store.insertPrompts([prompt])
        try store.setPromptStatus(prompt.id, .answered, respondedAt: t(100))
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let doing = try survey.question(labelled: "What are you doing?")
        let (deleted, _) = try store.record(in: survey, promptId: prompt.id, startedAt: t(100), answers: [
            (feeling, .scale(2)), (doing, .single(optionId: try doing.option(labelled: "Chores").id)),
        ])
        let (kept, keptAnswers) = try store.record(in: survey, startedAt: t(200), answers: [(feeling, .scale(4))])

        try store.deleteEntry(deleted.id)

        #expect(try store.entries(surveyId: nil, from: nil, to: nil) == [kept])
        #expect(try store.answers(entryId: deleted.id).isEmpty)
        #expect(try store.answers(entryId: kept.id) == keptAnswers)
        let stored = try #require(try store.prompts(status: nil).first)
        #expect(stored.id == prompt.id)
        #expect(stored.status == .answered)
        #expect(stored.respondedAt == t(100))
        let backup = try store.backup(now: t(0))
        #expect(backup.rowCounts["answer"] == 1)
        #expect(backup.rowCounts["answerOption"] == 0)
        #expect(throws: StoreError.notFound) { try store.deleteEntry(deleted.id) }
    }
}
