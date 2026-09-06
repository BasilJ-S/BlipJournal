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
