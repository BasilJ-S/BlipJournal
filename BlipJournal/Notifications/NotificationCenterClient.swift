import BlipJournalCore
import Foundation
import UserNotifications

/// Everything the coordinator needs from `UNUserNotificationCenter`, so tests run
/// against a fake instead of the real notification centre.
///
/// Beyond authorization and the plain pending/delivered identifier lists, the coordinator
/// needs to compare rendered content so it can tell a stale request from a current one
/// without deleting and re-adding every request on every refresh, and it needs each
/// delivered notification's prompt ID so it can tell which ones belong to prompts that
/// are no longer pending.
protocol NotificationCenterClient: Sendable {
    /// The centre's current authorization, as last observed. Never itself prompts.
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Asks the system for `.alert`, `.sound` and `.badge` permission.
    func requestAuthorization() async throws -> Bool
    /// Identifiers of every request still pending (not yet fired or removed).
    func pendingRequestIdentifiers() async -> Set<String>
    /// The rendered title/body of every pending request, keyed by identifier.
    func pendingRequestContent() async -> [String: NotificationContent]
    /// Schedules one request. Re-adding an identifier already pending replaces it.
    ///
    /// Takes a `Sendable` spec rather than a `UNNotificationRequest`: the request itself
    /// is a plain Foundation class with no `Sendable` conformance, so building it here and
    /// handing it to a `nonisolated` protocol requirement would risk a data race the
    /// compiler correctly refuses. `LiveNotificationCenterClient` builds the real request
    /// from the spec on whichever isolation `add` runs on.
    func add(_ spec: NotificationRequestSpec) async throws
    /// Cancels pending requests by identifier. A request that already fired is
    /// unaffected; use `removeDeliveredNotifications` for those.
    func removePendingRequests(withIdentifiers identifiers: [String])
    /// Every notification still sitting in Notification Centre.
    func deliveredNotifications() async -> [DeliveredNotification]
    /// Removes delivered notifications by identifier.
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    /// Clears every delivered notification, regardless of identifier.
    func removeAllDeliveredNotifications()
}

/// One notification sitting in Notification Centre, as much as the coordinator needs to
/// decide whether to leave it, remove it because its prompt is gone, or remove it because
/// its rendered content is stale.
struct DeliveredNotification: Sendable, Equatable {
    var identifier: String
    /// `userInfo["promptId"]`, if present. Every notification this app schedules carries
    /// one; nil is only possible for a notification from a future app version.
    var promptId: String?
    var content: NotificationContent?
}

/// Everything needed to schedule one request, `Sendable` so it can cross into
/// `NotificationCenterClient.add`. The identifier is always the prompt ID.
struct NotificationRequestSpec: Sendable, Equatable {
    var identifier: String
    var content: NotificationContent
    var dateComponents: DateComponents
}

/// Wraps `UNUserNotificationCenter.current()`. Stateless: every call reaches the live
/// centre, which Apple documents as safe to call from any thread.
struct LiveNotificationCenterClient: NotificationCenterClient {
    init() {}

    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pendingRequestIdentifiers() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    func pendingRequestContent() async -> [String: NotificationContent] {
        var result: [String: NotificationContent] = [:]
        for request in await center.pendingNotificationRequests() {
            result[request.identifier] = NotificationContent(
                title: request.content.title, body: request.content.body)
        }
        return result
    }

    func add(_ spec: NotificationRequestSpec) async throws {
        let content = UNMutableNotificationContent()
        content.title = spec.content.title
        content.body = spec.content.body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = NotificationCoordinator.categoryIdentifier
        content.userInfo = ["promptId": spec.identifier]
        let trigger = UNCalendarNotificationTrigger(dateMatching: spec.dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: spec.identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func deliveredNotifications() async -> [DeliveredNotification] {
        await center.deliveredNotifications().map { note in
            DeliveredNotification(
                identifier: note.request.identifier,
                promptId: note.request.content.userInfo["promptId"] as? String,
                content: NotificationContent(
                    title: note.request.content.title, body: note.request.content.body))
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removeAllDeliveredNotifications() {
        center.removeAllDeliveredNotifications()
    }
}

/// Records what was requested, for tests. Settable authorization status and request
/// outcome let tests drive every branch of the coordinator without a simulator.
///
/// `@unchecked Sendable`: this type is main-actor-only by convention (constructed and
/// used exclusively from `@MainActor` tests and the `@MainActor` coordinator, exactly
/// like the real centre it stands in for), so its mutable state is never touched
/// concurrently.
final class FakeNotificationCenterClient: NotificationCenterClient, @unchecked Sendable {
    struct PendingEntry: Equatable {
        var content: NotificationContent
        var scheduledAt: DateComponents
    }

    private(set) var pending: [String: PendingEntry] = [:]
    private(set) var delivered: [DeliveredNotification] = []
    private(set) var addCallCount = 0
    private(set) var requestAuthorizationCallCount = 0

    var authorizationStatusToReturn: UNAuthorizationStatus = .notDetermined
    var requestAuthorizationGrants = true

    init() {}

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusToReturn
    }

    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCallCount += 1
        authorizationStatusToReturn = requestAuthorizationGrants ? .authorized : .denied
        return requestAuthorizationGrants
    }

    func pendingRequestIdentifiers() async -> Set<String> {
        Set(pending.keys)
    }

    func pendingRequestContent() async -> [String: NotificationContent] {
        pending.mapValues(\.content)
    }

    func add(_ spec: NotificationRequestSpec) async throws {
        addCallCount += 1
        pending[spec.identifier] = PendingEntry(content: spec.content, scheduledAt: spec.dateComponents)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { pending.removeValue(forKey: id) }
    }

    func deliveredNotifications() async -> [DeliveredNotification] {
        delivered
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        let doomed = Set(identifiers)
        delivered.removeAll { doomed.contains($0.identifier) }
    }

    func removeAllDeliveredNotifications() {
        delivered.removeAll()
    }

    /// Test helper: simulates a request having fired, moving it from pending to
    /// delivered under the same identifier and content.
    func simulateDelivery(identifier: String, promptId: String) {
        let content = pending[identifier]?.content
        pending.removeValue(forKey: identifier)
        delivered.append(DeliveredNotification(identifier: identifier, promptId: promptId, content: content))
    }
}
