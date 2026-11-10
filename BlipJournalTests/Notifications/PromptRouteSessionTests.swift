import BlipJournalCore
import Foundation
import Testing
@testable import BlipJournal

@MainActor
struct PromptRouteSessionTests {
    @Test func lateFinishOnlyClearsItsOwnRoute() {
        let notifications = NoopNotificationCoordinator()
        notifications.pendingRoute = "B"
        notifications.finishRoute("A")
        #expect(notifications.pendingRoute == "B")
        notifications.finishRoute("B")
        #expect(notifications.pendingRoute == nil)
    }

    @Test func storeFailureRetainsCurrentDraftAndRoute() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try Store.inMemory()
        let option = ChoiceOption(label: "Temporary", position: 0)
        let question = Question(kind: .singleChoice, label: "Choice", position: 0, options: [option])
        let survey = try store.createSurvey(name: "Test", sampling: .default, questions: [question], now: now)
        let a = Prompt(surveyId: survey.id, day: "2027-01-15", scheduledAt: now, expiresAt: now.addingTimeInterval(600))
        let b = Prompt(surveyId: survey.id, day: a.day, scheduledAt: now, expiresAt: a.expiresAt)
        try store.insertPrompts([a, b])
        let model = try AppModel(store: store, notifications: NoopNotificationCoordinator(), now: now)
        model.unlock()
        let session = PromptRouteSession()
        try await session.resolve(promptId: a.id, appModel: model, now: now)
        let draft = try #require(session.draft)
        // An option removed after the runner loaded produces a real foreign-key failure.
        try store.updateOption(option.id, label: option.label, position: 0, isArchived: true, now: now.addingTimeInterval(1))
        try store.hardDeleteOption(option.id)
        await #expect(throws: (any Error).self) {
            try await draft.set(.single(optionId: option.id), for: question.id, now: now)
        }
        await #expect(throws: (any Error).self) {
            try await session.resolve(promptId: b.id, appModel: model, now: now)
        }
        #expect(session.draft === draft)
        #expect(session.promptId == a.id)
        #expect(try store.entries(surveyId: survey.id, from: nil, to: nil).allSatisfy { $0.promptId == a.id })
        #expect(try store.answers(entryId: draft.entry.id).isEmpty)
    }

    @Test func replacingRouteFlushesFirstDraftAndAssociatesAnswersWithSecondPrompt() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = try Store.inMemory()
        let a = try store.createSurvey(name: "Survey A", sampling: .default,
            questions: [Question(kind: .text, label: "Note A", position: 0)], now: now)
        let b = try store.createSurvey(name: "Survey B", sampling: .default,
            questions: [Question(kind: .text, label: "Note B", position: 0)], now: now)
        let pa = Prompt(surveyId: a.id, day: "2027-01-15", scheduledAt: now, expiresAt: now.addingTimeInterval(600))
        let pb = Prompt(surveyId: b.id, day: pa.day, scheduledAt: now, expiresAt: pa.expiresAt)
        try store.insertPrompts([pa, pb])
        let model = try AppModel(store: store, notifications: NoopNotificationCoordinator(), now: now)
        model.unlock()
        let session = PromptRouteSession()
        try await session.resolve(promptId: pa.id, appModel: model, now: now)
        let first = try #require(session.draft)
        first.setText("Pending A", for: a.questions[0].id, now: now)
        try await session.resolve(promptId: pb.id, appModel: model, now: now)
        #expect(session.promptId == pb.id)
        #expect(session.outcome == .runner(survey: b, promptId: pb.id))
        #expect(try store.answers(entryId: first.entry.id).first?.value == .text("Pending A"))
        let second = try #require(session.draft)
        #expect(second.entry.promptId == pb.id)
        #expect(second.survey.id == b.id)
        second.setText("Answer B", for: b.questions[0].id, now: now)
        try await second.flush()
        let savedB = try #require(try store.entries(surveyId: b.id, from: nil, to: nil).first)
        #expect(savedB.promptId == pb.id)
        #expect(try store.answers(entryId: savedB.id).first?.value == .text("Answer B"))
        #expect(try store.answers(entryId: first.entry.id).map(\.value) == [.text("Pending A")])
        try await session.resolve(promptId: pb.id, appModel: model, now: now)
        #expect(session.draft === second)

        // A completed stored entry cannot accept more edits; it must not block the next route.
        var completed = second.entry
        completed.completedAt = now.addingTimeInterval(30)
        try store.saveEntry(completed, answers: try store.answers(entryId: completed.id))
        second.setText("Unsaved B", for: b.questions[0].id, now: now)
        try await session.resolve(promptId: pa.id, appModel: model, now: now)
        #expect(session.draft?.entry.id == first.entry.id)
        #expect(session.promptId == pa.id)
        #expect(session.outcome == .runner(survey: a, promptId: pa.id))
        #expect(try store.answers(entryId: completed.id).first?.value == .text("Answer B"))
    }
}
