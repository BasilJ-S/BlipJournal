import BlipJournalCore
import Foundation
import UserNotifications

/// The app's door to notification scheduling. Task A2 provides the real implementation;
/// until then `NoopNotificationCoordinator` keeps the rest of the app compiling and inert.
@MainActor
protocol NotificationCoordinating: AnyObject {
    /// The current system authorization, as last observed.
    var authorizationStatus: UNAuthorizationStatus { get }
    /// Asks the system for permission. Returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Plan upcoming prompts, persist them, and reconcile the notification centre.
    func refresh(now: Date) async
    /// A survey's schedule changed; replan its prompts.
    func scheduleChanged(surveyId: String, now: Date) async
    /// Prompts were destroyed by a survey hard delete or `eraseEverything`; drop their requests.
    func promptsDestroyed(now: Date) async
    /// The prompt identifier of a tapped notification, waiting to be routed to the runner.
    var pendingRoute: String? { get set }
}

/// Does nothing. Stands in until A2 replaces it in `AppModel.live()`.
@MainActor
final class NoopNotificationCoordinator: NotificationCoordinating {
    var authorizationStatus: UNAuthorizationStatus { .notDetermined }
    var pendingRoute: String?

    init() {}

    func requestAuthorization() async -> Bool { false }
    func refresh(now: Date) async {}
    func scheduleChanged(surveyId: String, now: Date) async {}
    func promptsDestroyed(now: Date) async {}
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
    var pendingRoute: String?

    /// Bumped at the start of every `refresh`. A run that is still awaiting the client
    /// when a newer run starts checks this before each destructive client-side step, so
    /// a reset racing a stale in-flight refresh cannot resurrect requests the reset just
    /// cleared.
    @ObservationIgnored private var generation = 0

    nonisolated static let categoryIdentifier = "PROMPT"

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
    }

    // MARK: NotificationCoordinating

    func requestAuthorization() async -> Bool {
        let granted = (try? await client.requestAuthorization()) ?? false
        authorizationStatus = await client.authorizationStatus()
        return granted
    }

    func refresh(now: Date) async {
        generation += 1
        let myGeneration = generation

        authorizationStatus = await client.authorizationStatus()

        do {
            try planAndPersist(now: now)
        } catch {
            return
        }
        guard myGeneration == generation else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        do {
            try await reconcile(now: now, generation: myGeneration)
        } catch {
            // A store read/write failure here leaves the notification centre as it was;
            // the next refresh retries from scratch.
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

        for id in plan.missedPromptIds {
            try store.setPromptStatus(id, .missed, respondedAt: now)
        }
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

        let currentIds = await client.pendingRequestIdentifiers()
        let currentContent = await client.pendingRequestContent()
        guard myGeneration == generation else { return }

        let toRemove = currentIds.subtracting(targetIds)
        if !toRemove.isEmpty {
            client.removePendingRequests(withIdentifiers: Array(toRemove))
        }
        for prompt in target {
            guard let survey = activeSurveysById[prompt.surveyId] else { continue }
            let content = survey.notificationPreview.content(surveyName: survey.name)
            if currentIds.contains(prompt.id), currentContent[prompt.id] == content { continue }
            let spec = Self.makeSpec(prompt: prompt, content: content, calendar: calendar)
            try? await client.add(spec)
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

    private static func makeSpec(
        prompt: Prompt, content: NotificationContent, calendar: Calendar
    ) -> NotificationRequestSpec {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: prompt.scheduledAt)
        return NotificationRequestSpec(identifier: prompt.id, content: content, dateComponents: components)
    }
}
