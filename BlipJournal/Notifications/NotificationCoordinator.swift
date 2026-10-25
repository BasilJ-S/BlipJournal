import BlipJournalCore
import Foundation
import UserNotifications

/// The app's door to notification scheduling. Task A2 provides the real implementation;
/// until then `NoopNotificationCoordinator` keeps the rest of the app compiling and inert.
@MainActor
protocol NotificationCoordinating: AnyObject {
    /// The current system authorization, as last observed.
    var authorizationStatus: UNAuthorizationStatus { get }
    /// True while `requestAuthorization()` is waiting on the system's permission alert.
    /// The alert makes the scene inactive, and the privacy shield stays down for it.
    var isRequestingAuthorization: Bool { get }
    /// Asks the system for permission. Returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Plan upcoming prompts, persist them, and reconcile the notification centre.
    func refresh(now: Date) async
    /// Replace future pending prompts for every survey with a fresh random schedule.
    func reschedule(now: Date) async -> Bool
    /// A survey's schedule changed; replan its prompts.
    func scheduleChanged(surveyId: String, now: Date) async
    /// Prompts were destroyed by a survey hard delete or `eraseEverything`; drop their requests.
    func promptsDestroyed(now: Date) async
    /// The prompt identifier of a tapped notification, waiting to be routed to the runner.
    var pendingRoute: String? { get set }
    /// Saves an answer picked from a prompt notification's actions. The caller has checked
    /// that protected data is available.
    func answerFromNotification(_ answer: NotificationAnswerResponse, now: Date) async
}

/// An answer action picked on a prompt's notification, as much of the non-`Sendable`
/// `UNNotificationResponse` as saving it needs.
struct NotificationAnswerResponse: Sendable, Equatable {
    var promptId: String
    /// The notification's category, which names the question it offered answers for.
    var categoryIdentifier: String
    var actionIdentifier: String
}

extension NotificationCoordinating {
    /// Whether the system will deliver prompts: the one rule for "notifications are on",
    /// used by the reconcile step and by any view that offers to turn them on.
    var canDeliverPrompts: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional
    }
}

/// Does nothing. Stands in until A2 replaces it in `AppModel.live()`.
@MainActor
final class NoopNotificationCoordinator: NotificationCoordinating {
    var authorizationStatus: UNAuthorizationStatus { .notDetermined }
    var isRequestingAuthorization: Bool { false }
    var pendingRoute: String?

    init() {}

    func requestAuthorization() async -> Bool { false }
    func refresh(now: Date) async {}
    func reschedule(now: Date) async -> Bool { false }
    func scheduleChanged(surveyId: String, now: Date) async {}
    func promptsDestroyed(now: Date) async {}
    func answerFromNotification(_ answer: NotificationAnswerResponse, now: Date) async {}
}

/// Turns the planner's output into real local notifications and routes a tapped
/// notification into the survey runner. See `DESIGN.md` for the refresh sequence and the
/// reconcile rule.
@MainActor
@Observable
final class NotificationCoordinator: NotificationCoordinating {
    private let store: Store
    private let client: NotificationCenterClient
    private let calendar: Calendar
    private let planner: PromptPlanner

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var isRequestingAuthorization = false
    var pendingRoute: String?
    /// Called after a notification answer is saved, so the app can reload what it shows.
    @ObservationIgnored var onEntrySaved: (@MainActor () -> Void)?

    /// Bumped at the start of every `refresh`. A run that is still awaiting the client
    /// when a newer run starts checks this before each destructive client-side step, so
    /// a reset racing a stale in-flight refresh cannot resurrect requests the reset just
    /// cleared.
    @ObservationIgnored private var generation = 0

    /// Refreshes can suspend while talking to the notification centre. Keep later
    /// refreshes behind the current one so a reset cannot reconcile against stale store
    /// state while an older refresh is still adding requests.
    @ObservationIgnored private var refreshInProgress = false
    @ObservationIgnored private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    nonisolated static let categoryIdentifier = "PROMPT"
    /// Prefix of a prompt category that offers answers; the question ID follows it.
    nonisolated static let answerCategoryPrefix = "PROMPT.answers."

    init(
        store: Store, client: NotificationCenterClient,
        calendar: Calendar = .autoupdatingCurrent, planner: PromptPlanner = PromptPlanner()
    ) {
        self.store = store
        self.client = client
        self.calendar = calendar
        self.planner = planner
    }

    /// Attaches this coordinator to the notification delegate and claims any route a tap
    /// stashed before the coordinator existed (a cold launch from a notification).
    /// Called once, from `AppModel.live()`.
    func attach(to delegate: NotificationDelegate) {
        if let claimed = delegate.attach(self) {
            pendingRoute = claimed
        }
        if let answer = delegate.claimAnswerBeforeAttach() {
            Task { await answerFromNotification(answer, now: Date()) }
        }
    }

    // MARK: NotificationCoordinating

    func requestAuthorization() async -> Bool {
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        let granted = (try? await client.requestAuthorization()) ?? false
        authorizationStatus = await client.authorizationStatus()
        return granted
    }

    func refresh(now: Date) async {
        _ = await refresh(now: now, replacingFuture: false)
    }

    func reschedule(now: Date) async -> Bool {
        await refresh(now: now, replacingFuture: true)
    }

    private func refresh(now: Date, replacingFuture: Bool) async -> Bool {
        await waitForRefreshTurn()
        defer { finishRefreshTurn() }

        generation += 1
        let myGeneration = generation

        authorizationStatus = await client.authorizationStatus()

        do {
            if replacingFuture {
                for survey in try store.surveys(includeArchived: true) {
                    try store.deleteFuturePendingPrompts(surveyId: survey.id, after: now)
                }
            }
            try planAndPersist(now: now)
        } catch {
            return false
        }
        guard myGeneration == generation else { return false }
        guard canDeliverPrompts else { return false }

        do {
            try await reconcile(now: now, generation: myGeneration)
            return true
        } catch {
            // The next refresh retries from the persisted schedule.
            return false
        }
    }

    private func waitForRefreshTurn() async {
        guard refreshInProgress else {
            refreshInProgress = true
            return
        }

        await withCheckedContinuation { continuation in
            refreshWaiters.append(continuation)
        }
    }

    private func finishRefreshTurn() {
        if refreshWaiters.isEmpty {
            refreshInProgress = false
        } else {
            refreshWaiters.removeFirst().resume()
        }
    }

    func scheduleChanged(surveyId: String, now: Date) async {
        do {
            try store.deleteFuturePendingPrompts(surveyId: surveyId, after: now)
        } catch {
            return
        }
        await refresh(now: now)
    }

    func promptsDestroyed(now: Date) async {
        // Clear a route pointing at a prompt that no longer exists (an in-progress hard
        // delete or the erase-all reset), but leave an unrelated pending route alone.
        if let route = pendingRoute {
            let stillExists = (try? store.prompts(status: nil).contains { $0.id == route }) ?? true
            if !stillExists { pendingRoute = nil }
        }
        await refresh(now: now)
    }

    /// Saves the answer through `Store.saveNotificationAnswer`, which owns every rule
    /// (expiry, an entry already complete, a question edited since scheduling), then lets
    /// the app reload. Shows nothing: whatever the outcome, no stored data is put on
    /// screen, so this cannot bypass the app lock.
    func answerFromNotification(_ answer: NotificationAnswerResponse, now: Date) async {
        guard answer.categoryIdentifier.hasPrefix(Self.answerCategoryPrefix) else { return }
        let questionId = String(answer.categoryIdentifier.dropFirst(Self.answerCategoryPrefix.count))
        let outcome = try? store.saveNotificationAnswer(
            promptId: answer.promptId, questionId: questionId,
            actionIdentifier: answer.actionIdentifier, now: now)
        guard let outcome else { return }
        onEntrySaved?()
        if case .expired = outcome {
            // Settling an expired prompt changes what should be pending.
            await refresh(now: now)
        }
    }

    // MARK: Steps 1-4: plan and persist

    private func planAndPersist(now: Date) throws {
        let surveys = try store.surveys(includeArchived: true)
        let todayKey = DayKey.string(for: now, calendar: calendar)

        var existingById: [String: Prompt] = [:]
        for prompt in try store.prompts(status: .pending) { existingById[prompt.id] = prompt }
        for prompt in try store.prompts(status: nil) where prompt.day >= todayKey {
            existingById[prompt.id] = prompt
        }
        let existing = Array(existingById.values)

        var rng = SystemRandomNumberGenerator()
        let plan = planner.plan(now: now, surveys: surveys, existing: existing, calendar: calendar, using: &rng)

        // Missed, unless a notification answer already holds every required answer.
        try store.settleExpiredPrompts(plan.missedPromptIds, now: now)
        try store.insertPrompts(plan.newPrompts)
    }

    // MARK: Steps 5-6: reconcile

    /// Step 5 targets pending prompts scheduled after `now` for active, enabled surveys;
    /// requests missing from that target are added, requests present but stale (rendered
    /// content changed under the same identifier and time) are replaced, and requests for
    /// anything outside the target are removed. Step 6 then drops delivered notifications
    /// whose prompt is gone or no longer pending, and delivered notifications whose
    /// content no longer matches what the survey would render now (a preview or rename
    /// change), without touching any other survey's delivered notifications.
    private func reconcile(now: Date, generation myGeneration: Int) async throws {
        let surveys = try store.surveys(includeArchived: true)
        let surveysById = Dictionary(uniqueKeysWithValues: surveys.map { ($0.id, $0) })
        let activeSurveysById = surveysById.filter { !$0.value.isArchived && $0.value.sampling.isEnabled }

        let allPrompts = try store.prompts(status: nil)
        let promptsById = Dictionary(uniqueKeysWithValues: allPrompts.map { ($0.id, $0) })
        let pendingPrompts = allPrompts.filter { $0.status == .pending }
        let target = pendingPrompts.filter { $0.scheduledAt > now && activeSurveysById[$0.surveyId] != nil }
        let targetIds = Set(target.map(\.id))

        let answersBySurvey = activeSurveysById.compactMapValues(NotificationAnswers.init(survey:))
        let currentIds = await client.pendingRequestIdentifiers()
        let currentContent = await client.pendingRequestContent()
        let currentCategories = await client.pendingRequestCategories()
        guard myGeneration == generation else { return }

        // Register before adding: a request names its category by identifier.
        client.setCategories(Self.categories(for: Array(answersBySurvey.values)))

        let toRemove = currentIds.subtracting(targetIds)
        if !toRemove.isEmpty {
            client.removePendingRequests(withIdentifiers: Array(toRemove))
        }
        for prompt in target {
            guard let survey = activeSurveysById[prompt.surveyId] else { continue }
            let content = survey.notificationPreview.content(surveyName: survey.name)
            let category = Self.answerCategoryIdentifier(for: answersBySurvey[survey.id])
            if currentIds.contains(prompt.id), currentContent[prompt.id] == content,
               currentCategories[prompt.id] == category { continue }
            try await client.add(Self.makeSpec(
                prompt: prompt, content: content, categoryIdentifier: category, calendar: calendar))
        }
        guard myGeneration == generation else { return }

        let pendingIds = Set(pendingPrompts.map(\.id))
        var deliveredToRemove: [String] = []
        for note in await client.deliveredNotifications() {
            guard let promptId = note.promptId else { continue }
            guard let prompt = promptsById[promptId] else {
                deliveredToRemove.append(note.identifier)
                continue
            }
            guard prompt.status == .pending else {
                deliveredToRemove.append(note.identifier)
                continue
            }
            guard pendingIds.contains(promptId), let survey = surveysById[prompt.surveyId] else { continue }
            let expected = survey.notificationPreview.content(surveyName: survey.name)
            if let content = note.content, content != expected {
                deliveredToRemove.append(note.identifier)
            }
        }
        guard myGeneration == generation else { return }
        if !deliveredToRemove.isEmpty {
            client.removeDeliveredNotifications(withIdentifiers: deliveredToRemove)
        }
    }

    /// The category a prompt's request names: one per question that offers answers, so a
    /// changed first question changes the category and the request is replaced.
    static func answerCategoryIdentifier(for answers: NotificationAnswers?) -> String {
        answers.map { answerCategoryPrefix + $0.questionId } ?? categoryIdentifier
    }

    /// The plain `PROMPT` category plus one answer category per distinct question, with
    /// actions in the order `NotificationAnswers` lists them.
    private static func categories(for answers: [NotificationAnswers]) -> [NotificationCategorySpec] {
        var seen: Set<String> = []
        let answerCategories = answers
            .sorted { $0.questionId < $1.questionId }
            .filter { seen.insert($0.questionId).inserted }
            .map { offer in
                NotificationCategorySpec(
                    identifier: answerCategoryIdentifier(for: offer),
                    actions: offer.choices.map {
                        NotificationCategorySpec.Action(identifier: $0.actionIdentifier, title: $0.title)
                    })
            }
        return [NotificationCategorySpec(identifier: categoryIdentifier, actions: [])] + answerCategories
    }

    private static func makeSpec(
        prompt: Prompt, content: NotificationContent, categoryIdentifier: String, calendar: Calendar
    ) -> NotificationRequestSpec {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: prompt.scheduledAt)
        return NotificationRequestSpec(
            identifier: prompt.id, content: content, dateComponents: components,
            categoryIdentifier: categoryIdentifier)
    }
}
