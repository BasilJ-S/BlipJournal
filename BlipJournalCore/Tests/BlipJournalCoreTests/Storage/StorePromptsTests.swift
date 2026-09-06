import Foundation
import Testing
import OpenBlipCore

@Suite("Store prompts")
struct StorePromptsTests {
    private let t = Fixture.at

    @Test("prompts round-trip and are listed by scheduledAt, filtered by status or by survey and day")
    func insertAndList() throws {
        let store = try Store.inMemory()
        let a = try Fixture.seed(store, name: "A", now: t(0))
        let b = try Fixture.seed(store, name: "B", now: t(1))
        let late = Fixture.prompt(a, scheduledAt: t(3000))
        let early = Fixture.prompt(a, scheduledAt: t(1000), status: .missed, respondedAt: t(2200))
        let other = Fixture.prompt(b, day: "2026-05-02", scheduledAt: t(2000))

        try store.insertPrompts([late, early, other])

        #expect(try store.prompts(status: nil) == [early, other, late])
        #expect(try store.prompts(status: .pending) == [other, late])
        #expect(try store.prompts(status: .missed) == [early])
        #expect(try store.prompts(status: .answered).isEmpty)
        #expect(try store.prompts(surveyId: a.id, day: "2026-05-01") == [early, late])
        #expect(try store.prompts(surveyId: b.id, day: "2026-05-01").isEmpty)
        #expect(try store.prompts(surveyId: b.id, day: "2026-05-02") == [other])
    }

    @Test("insertPrompts is one transaction: an unknown survey in the batch inserts nothing")
    func insertIsAtomic() throws {
        let (store, survey) = try Fixture.seeded()
        let good = Fixture.prompt(survey, scheduledAt: t(100))
        let bad = Prompt(surveyId: "missing", day: "2026-05-01", scheduledAt: t(200), expiresAt: t(300))

        #expect(throws: (any Error).self) { try store.insertPrompts([good, bad]) }
        #expect(try store.prompts(status: nil).isEmpty)
    }

    @Test("setPromptStatus changes only status and respondedAt")
    func setStatus() throws {
        let (store, survey) = try Fixture.seeded()
        let prompt = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([prompt])

        try store.setPromptStatus(prompt.id, .answered, respondedAt: t(105))

        var expected = prompt
        expected.status = .answered
        expected.respondedAt = t(105)
        #expect(try store.prompts(status: nil) == [expected])

        try store.setPromptStatus(prompt.id, .pending, respondedAt: nil)
        #expect(try store.prompts(status: nil) == [prompt])
        #expect(throws: StoreError.notFound) { try store.setPromptStatus("x", .missed, respondedAt: t(1)) }
    }

    @Test("deleteFuturePendingPrompts keeps past pending, future answered, and other surveys' prompts")
    func deleteFuturePending() throws {
        let store = try Store.inMemory()
        let a = try Fixture.seed(store, name: "A", now: t(0))
        let b = try Fixture.seed(store, name: "B", now: t(1))
        let pastPending = Fixture.prompt(a, scheduledAt: t(1000))
        let atCutoff = Fixture.prompt(a, scheduledAt: t(2000))
        let futurePending = Fixture.prompt(a, scheduledAt: t(3000))
        let futureAnswered = Fixture.prompt(a, scheduledAt: t(4000), status: .answered, respondedAt: t(4001))
        let futureMissed = Fixture.prompt(a, scheduledAt: t(5000), status: .missed, respondedAt: t(5020))
        let otherSurvey = Fixture.prompt(b, scheduledAt: t(6000))
        let beingAnswered = Fixture.prompt(a, scheduledAt: t(7000))
        try store.insertPrompts([pastPending, atCutoff, futurePending, futureAnswered, futureMissed, otherSurvey, beingAnswered])
        // The runner autosaves against a still-pending prompt; deleting it would orphan the entry.
        try store.record(in: a, promptId: beingAnswered.id, startedAt: t(7001), answers: [])

        try store.deleteFuturePendingPrompts(surveyId: a.id, after: t(2000))

        #expect(try store.prompts(status: nil) == [pastPending, atCutoff, futureAnswered, futureMissed, otherSurvey, beingAnswered])
    }
}
