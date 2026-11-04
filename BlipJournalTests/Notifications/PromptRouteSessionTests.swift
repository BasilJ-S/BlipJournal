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

        // A failed flush must not discard B or create a replacement runner.
        var completed = second.entry
        completed.completedAt = now.addingTimeInterval(30)
        try store.saveEntry(completed, answers: try store.answers(entryId: completed.id))
        second.setText("Unsaved B", for: b.questions[0].id, now: now)
        await #expect(throws: EntryDraft.Error.completed) {
            try await session.resolve(promptId: pa.id, appModel: model, now: now)
        }
        #expect(session.draft === second)
        #expect(session.promptId == pb.id)
        #expect(try store.answers(entryId: completed.id).first?.value == .text("Answer B"))
    }
}
