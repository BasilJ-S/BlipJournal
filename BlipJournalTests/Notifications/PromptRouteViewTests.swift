import BlipJournalCore
import Foundation
import Testing
@testable import BlipJournal

@MainActor
@Suite("PromptRouteView.route")
struct PromptRouteViewTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeSurvey(store: Store, now: Date) throws -> Survey {
        try store.createSurvey(name: "Check-in", sampling: .default, questions: [], now: now)
    }

    private func surveysById(_ survey: Survey) -> [String: Survey] { [survey.id: survey] }

    @Test func unavailableWhenPromptMissing() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let outcome = PromptRouteView.route(
            promptId: "nonexistent", now: now, store: store, surveysById: surveysById(survey))
        #expect(outcome == .unavailable(message: "This prompt is no longer available."))
    }

    @Test func unavailableWhenSurveyDeleted() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: .current),
            scheduledAt: now.addingTimeInterval(600), expiresAt: now.addingTimeInterval(1800))
        try store.insertPrompts([prompt])

        let outcome = PromptRouteView.route(promptId: prompt.id, now: now, store: store, surveysById: [:])
        #expect(outcome == .unavailable(message: "This prompt's survey has been deleted."))
    }

    @Test func opensFreshRunnerForPendingUnexpiredPromptWithNoEntry() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: .current),
            scheduledAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(600))
        try store.insertPrompts([prompt])

        let outcome = PromptRouteView.route(
            promptId: prompt.id, now: now, store: store, surveysById: surveysById(survey))
        #expect(outcome == .runner(survey: survey, promptId: prompt.id))
    }

    @Test func resumesUnfinishedDraftEvenAfterExpiryAndMissedStatus() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: .current),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-1800),
            status: .missed, respondedAt: now.addingTimeInterval(-1700))
        try store.insertPrompts([prompt])
        let entry = Entry(surveyId: survey.id, promptId: prompt.id, startedAt: now.addingTimeInterval(-3500))
        try store.saveEntry(entry, answers: [])

        let outcome = PromptRouteView.route(
            promptId: prompt.id, now: now, store: store, surveysById: surveysById(survey))
        #expect(outcome == .runner(survey: survey, promptId: prompt.id))
    }

    @Test func completedEntryRoutesReadOnly() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: .current),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-3000),
            status: .answered, respondedAt: now.addingTimeInterval(-3000))
        try store.insertPrompts([prompt])
        let entry = Entry(
            surveyId: survey.id, promptId: prompt.id, startedAt: now.addingTimeInterval(-3500),
            completedAt: now.addingTimeInterval(-3000))
        try store.saveEntry(entry, answers: [])

        let outcome = PromptRouteView.route(
            promptId: prompt.id, now: now, store: store, surveysById: surveysById(survey))
        #expect(outcome == .detail(entry: entry))
    }

    @Test func expiredPendingPromptWithNoDraftMarksMissedAndOffersManualEntry() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: .current),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-1800))
        try store.insertPrompts([prompt])

        let outcome = PromptRouteView.route(
            promptId: prompt.id, now: now, store: store, surveysById: surveysById(survey))
        #expect(outcome == .deadEnd(message: "This prompt expired before it was answered.", survey: survey))

        let stored = try #require(try store.prompts(status: nil).first { $0.id == prompt.id })
        #expect(stored.status == .missed)
    }

    @Test func answeredPromptWithDeletedEntryOffersManualEntryWithoutRecreatingIt() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: .current),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-3000),
            status: .answered, respondedAt: now.addingTimeInterval(-3000))
        try store.insertPrompts([prompt])
        // No entry: it was deleted after answering.

        let outcome = PromptRouteView.route(
            promptId: prompt.id, now: now, store: store, surveysById: surveysById(survey))
        #expect(outcome == .deadEnd(
            message: "This prompt was already answered, but its entry was deleted.", survey: survey))

        // Status is left as answered, not reset or duplicated.
        let stored = try #require(try store.prompts(status: nil).first { $0.id == prompt.id })
        #expect(stored.status == .answered)
    }

    @Test func alreadyMissedPromptWithNoDraftOffersManualEntryWithoutDoubleMarking() throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let respondedAt = now.addingTimeInterval(-1700)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: .current),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-1800),
            status: .missed, respondedAt: respondedAt)
        try store.insertPrompts([prompt])

        let outcome = PromptRouteView.route(
            promptId: prompt.id, now: now, store: store, surveysById: surveysById(survey))
        #expect(outcome == .deadEnd(message: "This prompt expired before it was answered.", survey: survey))

        let stored = try #require(try store.prompts(status: nil).first { $0.id == prompt.id })
        #expect(stored.respondedAt == respondedAt)
    }
}
