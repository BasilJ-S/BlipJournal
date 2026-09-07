import BlipJournalCore
import Foundation
import Testing
import UserNotifications
@testable import BlipJournal

@MainActor
@Suite("NotificationCoordinator")
struct NotificationCoordinatorTests {
    let toronto: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }()

    var now: Date {
        toronto.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12, minute: 0))!
    }

    private func makeCoordinator(store: Store, client: FakeNotificationCenterClient) -> NotificationCoordinator {
        NotificationCoordinator(store: store, client: client, calendar: toronto)
    }

    /// An active, enabled survey whose window comfortably covers `now`, with no
    /// questions (the coordinator never reads them).
    @discardableResult
    private func makeSurvey(
        store: Store, name: String = "Check-in", isEnabled: Bool = true, now: Date
    ) throws -> Survey {
        try store.createSurvey(
            name: name,
            sampling: SamplingConfig(
                promptsPerDay: 3, windowStartMinutes: 0, windowEndMinutes: 1440,
                minGapMinutes: 30, expiryMinutes: 20, isEnabled: isEnabled),
            questions: [], now: now)
    }

    // MARK: Refresh

    @Test func rescheduleReplacesFutureRequestsForAllSurveysAndKeepsHistory() async throws {
        let store = try Store.inMemory()
        let a = try makeSurvey(store: store, name: "A", now: now)
        let b = try makeSurvey(store: store, name: "B", now: now)
        let first = Prompt(
            surveyId: a.id, day: DayKey.string(for: now, calendar: toronto),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-1800),
            status: .answered)
        try store.insertPrompts([first])
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)
        let oldIds = await client.pendingRequestIdentifiers()
        #expect(!oldIds.isEmpty)

        #expect(await coordinator.reschedule(now: now))

        let all = try store.prompts(status: nil)
        #expect(all.first { $0.id == first.id } == first)
        let future = all.filter { $0.status == .pending && $0.scheduledAt > now }
        #expect(Set(future.map(\.surveyId)) == [a.id, b.id])
        let newIds = Set(future.map(\.id))
        #expect(newIds.isDisjoint(with: oldIds))
        #expect(await client.pendingRequestIdentifiers() == newIds)
        let todayA = all.filter { $0.surveyId == a.id && $0.day == first.day }
        #expect(todayA.count > 1)
        #expect(todayA.count <= a.sampling.promptsPerDay)
        #expect(client.requestAuthorizationCallCount == 0)

        // An ordinary refresh preserves the newly drawn schedule.
        await coordinator.refresh(now: now)
        #expect(await client.pendingRequestIdentifiers() == newIds)
    }

    @Test func rescheduleReportsMissingPermission() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .denied
        let coordinator = makeCoordinator(store: store, client: client)
        #expect(await coordinator.reschedule(now: now) == false)
        #expect(await client.pendingRequestIdentifiers().isEmpty)
        #expect(client.requestAuthorizationCallCount == 0)
    }

    @Test func refreshSchedulesOnlyPendingFutureActiveEnabledSurveys() async throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)

        await coordinator.refresh(now: now)

        let expectedIds = Set(
            try store.prompts(status: .pending)
                .filter { $0.scheduledAt > now && $0.surveyId == survey.id }
                .map(\.id))
        #expect(!expectedIds.isEmpty)
        #expect(await client.pendingRequestIdentifiers() == expectedIds)
    }

    @Test func expiredPendingPromptIsMarkedMissedAndRequestRemoved() async throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let expired = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: toronto),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-1800))
        try store.insertPrompts([expired])

        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        try? await client.add(
            NotificationRequestSpec(
                identifier: expired.id, content: NotificationContent(title: "Blip Journal", body: "Time for a check-in."),
                dateComponents: DateComponents()))
        let coordinator = makeCoordinator(store: store, client: client)

        await coordinator.refresh(now: now)

        let stored = try #require(try store.prompts(status: nil).first { $0.id == expired.id })
        #expect(stored.status == .missed)
        #expect(await client.pendingRequestIdentifiers().contains(expired.id) == false)
    }

    @Test func scheduleChangedRemovesOnlyThatSurveysFuturePendingPrompts() async throws {
        let store = try Store.inMemory()
        let a = try makeSurvey(store: store, name: "A", now: now)
        let b = try makeSurvey(store: store, name: "B", now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)

        let beforeAIds = Set(try store.prompts(status: .pending).filter { $0.surveyId == a.id }.map(\.id))
        let beforeBIds = Set(try store.prompts(status: .pending).filter { $0.surveyId == b.id }.map(\.id))
        #expect(!beforeAIds.isEmpty)
        #expect(!beforeBIds.isEmpty)

        await coordinator.scheduleChanged(surveyId: a.id, now: now)

        let afterAIds = Set(try store.prompts(status: .pending).filter { $0.surveyId == a.id }.map(\.id))
        let afterBIds = Set(try store.prompts(status: .pending).filter { $0.surveyId == b.id }.map(\.id))
        #expect(afterAIds.isDisjoint(with: beforeAIds) || afterAIds == beforeAIds)
        // B's schedule is untouched by A's change.
        #expect(afterBIds == beforeBIds)
        let pendingRequestIds = await client.pendingRequestIdentifiers()
        #expect(pendingRequestIds.isDisjoint(with: beforeAIds.subtracting(afterAIds)))
        #expect(beforeBIds.isSubset(of: pendingRequestIds))
    }

    @Test func promptsDestroyedAfterHardDeleteLeavesNoRequestForThatSurvey() async throws {
        let store = try Store.inMemory()
        let doomed = try makeSurvey(store: store, name: "Doomed", now: now)
        let survivor = try makeSurvey(store: store, name: "Survivor", now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)

        let survivorIds = Set(try store.prompts(status: .pending).filter { $0.surveyId == survivor.id }.map(\.id))
        #expect(!survivorIds.isEmpty)

        try store.archiveSurvey(doomed.id, now: now)
        try store.hardDeleteSurvey(doomed.id)
        await coordinator.promptsDestroyed(now: now)

        let pendingRequestIds = await client.pendingRequestIdentifiers()
        #expect(pendingRequestIds.allSatisfy { survivorIds.contains($0) })
    }

    @Test func deniedStatusStillPlansAndStoresButAddsNoRequest() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .denied
        let coordinator = makeCoordinator(store: store, client: client)

        await coordinator.refresh(now: now)

        #expect(!(try store.prompts(status: .pending)).isEmpty)
        #expect(await client.pendingRequestIdentifiers().isEmpty)
    }

    @Test func promptWithEntrySurvivesScheduleChangedAndKeepsItsRequest() async throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, now: now)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: toronto),
            scheduledAt: now.addingTimeInterval(600), expiresAt: now.addingTimeInterval(1800))
        try store.insertPrompts([prompt])
        try store.saveEntry(Entry(surveyId: survey.id, promptId: prompt.id, startedAt: now), answers: [])

        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)
        #expect(await client.pendingRequestIdentifiers().contains(prompt.id))

        await coordinator.scheduleChanged(surveyId: survey.id, now: now)

        let stored = try #require(try store.prompts(status: nil).first { $0.id == prompt.id })
        #expect(stored.status == .pending)
        #expect(await client.pendingRequestIdentifiers().contains(prompt.id))
    }

    @Test func twoConsecutiveRefreshesAreIdempotent() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)

        await coordinator.refresh(now: now)
        let idsAfterFirst = await client.pendingRequestIdentifiers()
        let promptsAfterFirst = try store.prompts(status: nil).count

        await coordinator.refresh(now: now)
        let idsAfterSecond = await client.pendingRequestIdentifiers()
        let promptsAfterSecond = try store.prompts(status: nil).count

        #expect(idsAfterFirst == idsAfterSecond)
        #expect(promptsAfterFirst == promptsAfterSecond)
    }

    // MARK: Preview

    @Test func privateIsDefaultAndNeverExposesSurveyName() async throws {
        let store = try Store.inMemory()
        let survey = try makeSurvey(store: store, name: "Very secret survey", now: now)
        #expect(survey.notificationPreview == .private)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)

        await coordinator.refresh(now: now)

        let content = await client.pendingRequestContent()
        for value in content.values {
            #expect(value.title == "Blip Journal")
            #expect(!value.body.contains("Very secret survey"))
        }
    }

    @Test func previewChangeReplacesPendingContentAndRemovesAffectedDeliveredNotificationsOnly() async throws {
        let store = try Store.inMemory()
        let changed = try makeSurvey(store: store, name: "Mood", now: now)
        let untouched = try makeSurvey(store: store, name: "Sleep", now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)

        // Simulate one delivered notification per survey, still pending, rendered under
        // the old (private) content.
        let changedPrompt = try #require(try store.prompts(surveyId: changed.id, day: DayKey.string(for: now, calendar: toronto)).first)
        let untouchedPrompt = try #require(try store.prompts(surveyId: untouched.id, day: DayKey.string(for: now, calendar: toronto)).first)
        client.simulateDelivery(identifier: changedPrompt.id, promptId: changedPrompt.id)
        client.simulateDelivery(identifier: untouchedPrompt.id, promptId: untouchedPrompt.id)

        try store.updateNotificationPreview(surveyId: changed.id, .surveyName, now: now.addingTimeInterval(1))
        await coordinator.refresh(now: now.addingTimeInterval(1))

        let delivered = await client.deliveredNotifications()
        #expect(delivered.map(\.identifier) == [untouchedPrompt.id])

        let content = await client.pendingRequestContent()
        #expect(content[changedPrompt.id]?.title == "Mood")
        #expect(content[untouchedPrompt.id]?.title == "Blip Journal")
    }

    // MARK: Permission

    @Test func refreshNeverRequestsPermission() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .notDetermined
        let coordinator = makeCoordinator(store: store, client: client)

        await coordinator.refresh(now: now)
        await coordinator.refresh(now: now.addingTimeInterval(60))

        #expect(client.requestAuthorizationCallCount == 0)
    }

    @Test func requestAuthorizationCallsClientAndUpdatesStatus() async throws {
        let store = try Store.inMemory()
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .notDetermined
        client.requestAuthorizationGrants = true
        let coordinator = makeCoordinator(store: store, client: client)

        let granted = await coordinator.requestAuthorization()

        #expect(granted)
        #expect(client.requestAuthorizationCallCount == 1)
        #expect(coordinator.authorizationStatus == .authorized)
    }

    // MARK: Delete-all style reset

    @Test func promptsDestroyedAfterEraseEverythingLeavesNothingScheduled() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)
        #expect(!(await client.pendingRequestIdentifiers()).isEmpty)
        coordinator.pendingRoute = try #require(try store.prompts(status: .pending).first?.id)

        try store.eraseEverything(now: now)
        await coordinator.promptsDestroyed(now: now)

        #expect(await client.pendingRequestIdentifiers().isEmpty)
        #expect(await client.deliveredNotifications().isEmpty)
        #expect(coordinator.pendingRoute == nil)

        // The reseeded default survey is paused; a further refresh schedules nothing.
        await coordinator.refresh(now: now.addingTimeInterval(120))
        #expect(await client.pendingRequestIdentifiers().isEmpty)
    }

    @Test func resetWaitsForInFlightAddBeforeReconciling() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        client.holdNextAdd()
        let coordinator = makeCoordinator(store: store, client: client)

        let initialRefresh = Task { @MainActor in
            await coordinator.refresh(now: now)
        }
        await client.waitUntilAddStarted()

        try store.eraseEverything(now: now)
        let reset = Task { @MainActor in
            await coordinator.promptsDestroyed(now: now)
        }
        client.releaseBlockedAdd()

        await initialRefresh.value
        await reset.value

        #expect(await client.pendingRequestIdentifiers().isEmpty)
    }
}
