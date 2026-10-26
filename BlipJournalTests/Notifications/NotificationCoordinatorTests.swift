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
        store: Store, name: String = "Check-in", isEnabled: Bool = true,
        questions: [Question] = [], now: Date
    ) throws -> Survey {
        try store.createSurvey(
            name: name,
            sampling: SamplingConfig(
                promptsPerDay: 3, windowStartMinutes: 0, windowEndMinutes: 1440,
                minGapMinutes: 30, expiryMinutes: 20, isEnabled: isEnabled),
            questions: questions, now: now)
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
        #expect(!coordinator.isRequestingAuthorization)
        #expect(coordinator.canDeliverPrompts)
    }

    @Test func canDeliverPromptsOnlyWhenAuthorizedOrProvisional() async throws {
        let store = try Store.inMemory()
        let cases: [(UNAuthorizationStatus, Bool)] = [
            (.authorized, true), (.provisional, true),
            (.ephemeral, false), (.denied, false), (.notDetermined, false),
        ]
        for (status, expected) in cases {
            let client = FakeNotificationCenterClient()
            client.authorizationStatusToReturn = status
            let coordinator = makeCoordinator(store: store, client: client)
            await coordinator.refresh(now: now)
            #expect(coordinator.canDeliverPrompts == expected, "status \(status.rawValue)")
        }
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

    // MARK: Notification answers

    private func yesNoSurvey(store: Store, name: String = "Sleep") throws -> Survey {
        try makeSurvey(
            store: store, name: name,
            questions: [
                Question(kind: .yesNo, label: "Slept well?", position: 0, isRequired: true),
                Question(kind: .text, label: "Anything else?", position: 1),
            ],
            now: now)
    }

    @Test func answerableSurveyRegistersItsActionsAndItsRequestsNameThem() async throws {
        let store = try Store.inMemory()
        let answerable = try yesNoSurvey(store: store)
        let plain = try makeSurvey(store: store, name: "Notes", now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)

        await coordinator.refresh(now: now)

        let questionId = try #require(answerable.activeQuestions.first).id
        let answerCategory = NotificationCoordinator.answerCategoryPrefix + questionId
        #expect(client.categories.map(\.identifier) == [NotificationCoordinator.categoryIdentifier, answerCategory])
        #expect(client.categories.first?.actions.isEmpty == true)
        #expect(client.categories.last?.actions.map(\.title) == ["Yes", "No"])

        let categories = await client.pendingRequestCategories()
        let prompts = try store.prompts(status: .pending).filter { $0.scheduledAt > now }
        #expect(!prompts.isEmpty)
        for prompt in prompts {
            let expected = prompt.surveyId == plain.id ? NotificationCoordinator.categoryIdentifier : answerCategory
            #expect(categories[prompt.id] == expected)
        }
    }

    @Test func changingTheFirstQuestionReplacesTheRequestsCategory() async throws {
        let store = try Store.inMemory()
        let survey = try yesNoSurvey(store: store)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)
        let addsBefore = client.addCallCount

        // Archive the yes/no question: the note is first now, and offers nothing.
        let first = try #require(survey.activeQuestions.first)
        try store.updateQuestion(
            first.id, label: first.label, position: first.position, isRequired: true, isArchived: true,
            scale: nil, allowsCustomOptions: false, now: now.addingTimeInterval(1))
        await coordinator.refresh(now: now.addingTimeInterval(1))

        #expect(client.addCallCount > addsBefore)
        #expect(client.categories.map(\.identifier) == [NotificationCoordinator.categoryIdentifier])
        let categories = await client.pendingRequestCategories()
        #expect(!categories.isEmpty)
        #expect(categories.values.allSatisfy { $0 == NotificationCoordinator.categoryIdentifier })
    }

    @Test func answerFromNotificationSavesAnOpenEntryAndTellsTheApp() async throws {
        let store = try Store.inMemory()
        let survey = try yesNoSurvey(store: store)
        let question = try #require(survey.activeQuestions.first)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: toronto),
            scheduledAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(1140))
        try store.insertPrompts([prompt])
        let coordinator = makeCoordinator(store: store, client: FakeNotificationCenterClient())
        let reloads = ReloadCounter()
        coordinator.onEntrySaved = { reloads.count += 1 }
        let offered = try #require(NotificationAnswers(survey: survey))

        await coordinator.answerFromNotification(
            NotificationAnswerResponse(
                promptId: prompt.id,
                categoryIdentifier: NotificationCoordinator.answerCategoryIdentifier(for: offered),
                actionIdentifier: offered.choices[0].actionIdentifier, answeredAt: now))

        let entry = try #require(try store.entries(surveyId: survey.id, from: nil, to: nil).first)
        #expect(entry.promptId == prompt.id)
        #expect(entry.answeredFromNotification)
        #expect(entry.completedAt == nil)
        #expect(try store.answers(entryId: entry.id).map(\.questionId) == [question.id])
        #expect(reloads.count == 1)
        // The save is followed by a refresh, which plans the prompts still to come.
        #expect(try store.prompts(status: .pending).contains { $0.scheduledAt > now })
        #expect(coordinator.pendingRoute == nil)
    }

    @Test func answerUnderThePlainCategorySavesNothing() async throws {
        let store = try Store.inMemory()
        let survey = try yesNoSurvey(store: store)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: toronto),
            scheduledAt: now.addingTimeInterval(-60), expiresAt: now.addingTimeInterval(1140))
        try store.insertPrompts([prompt])
        let coordinator = makeCoordinator(store: store, client: FakeNotificationCenterClient())

        await coordinator.answerFromNotification(
            NotificationAnswerResponse(
                promptId: prompt.id, categoryIdentifier: NotificationCoordinator.categoryIdentifier,
                actionIdentifier: "answer.yes", answeredAt: now))

        #expect(try store.entries(surveyId: nil, from: nil, to: nil).isEmpty)
    }

    @Test func refreshCompletesAnExpiredNotificationEntryInsteadOfMissingIt() async throws {
        let store = try Store.inMemory()
        let survey = try yesNoSurvey(store: store)
        let question = try #require(survey.activeQuestions.first)
        let prompt = Prompt(
            surveyId: survey.id, day: DayKey.string(for: now, calendar: toronto),
            scheduledAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(-2400))
        try store.insertPrompts([prompt])
        let offered = try #require(NotificationAnswers(survey: survey))
        let answeredAt = now.addingTimeInterval(-3000)
        #expect(try store.saveNotificationAnswer(
            promptId: prompt.id, questionId: question.id,
            actionIdentifier: offered.choices[1].actionIdentifier, now: answeredAt) != .unavailable)
        let coordinator = makeCoordinator(store: store, client: FakeNotificationCenterClient())

        await coordinator.refresh(now: now)

        let settled = try #require(try store.prompts(status: nil).first { $0.id == prompt.id })
        #expect(settled.status == .answered)
        let entry = try #require(try store.entries(surveyId: survey.id, from: nil, to: nil).first)
        #expect(entry.completedAt != nil)
    }

    // MARK: Running out

    /// The last three pending prompts after `date`, by fire time, ties by identifier.
    private func lastThreeScheduledIds(store: Store, after date: Date) throws -> [String] {
        try store.prompts(status: .pending)
            .filter { $0.scheduledAt > date }
            .sorted { ($0.scheduledAt, $0.id) < ($1.scheduledAt, $1.id) }
            .suffix(3)
            .map(\.id)
    }

    @Test func runningOutWarningSitsOnTheLastThreePromptsAndMovesWhenMoreAreScheduled() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        let plain = NotificationPreview.private.content(surveyName: "Check-in")

        await coordinator.refresh(now: now)
        let firstLast = try lastThreeScheduledIds(store: store, after: now)
        try #require(firstLast.count == 3)
        var content = await client.pendingRequestContent()
        #expect(content.count > 3)
        #expect(content[firstLast[0]] == RunningOutWarning.content(plain, remaining: 3))
        #expect(content[firstLast[1]] == RunningOutWarning.content(plain, remaining: 2))
        #expect(content[firstLast[2]] == RunningOutWarning.content(plain, remaining: 1))
        #expect(content.filter { !firstLast.contains($0.key) }.values.allSatisfy { $0 == plain })

        // A day later the app opens again and schedules a new day at the far end.
        let later = now.addingTimeInterval(24 * 3600)
        await coordinator.refresh(now: later)
        let secondLast = try lastThreeScheduledIds(store: store, after: later)
        try #require(secondLast.count == 3)
        #expect(Set(secondLast).isDisjoint(with: firstLast))
        content = await client.pendingRequestContent()
        for id in firstLast {
            #expect(content[id] == plain)
        }
        #expect(content[secondLast[0]] == RunningOutWarning.content(plain, remaining: 3))
        #expect(content[secondLast[1]] == RunningOutWarning.content(plain, remaining: 2))
        #expect(content[secondLast[2]] == RunningOutWarning.content(plain, remaining: 1))
    }

    @Test func deliveredRunningOutNotificationIsNotSweptAsStale() async throws {
        let store = try Store.inMemory()
        try makeSurvey(store: store, now: now)
        let client = FakeNotificationCenterClient()
        client.authorizationStatusToReturn = .authorized
        let coordinator = makeCoordinator(store: store, client: client)
        await coordinator.refresh(now: now)

        let lastId = try #require(try lastThreeScheduledIds(store: store, after: now).last)
        let last = try #require(try store.prompts(status: .pending).first { $0.id == lastId })
        client.simulateDelivery(identifier: last.id, promptId: last.id)

        // Opened from the app icon a minute after the last prompt fired, still answerable.
        await coordinator.refresh(now: last.scheduledAt.addingTimeInterval(60))

        let delivered = await client.deliveredNotifications()
        #expect(delivered.map(\.identifier) == [last.id])
        let plain = NotificationPreview.private.content(surveyName: "Check-in")
        #expect(delivered.first?.content == RunningOutWarning.content(plain, remaining: 1))
    }
}

@MainActor
private final class ReloadCounter {
    var count = 0
}
