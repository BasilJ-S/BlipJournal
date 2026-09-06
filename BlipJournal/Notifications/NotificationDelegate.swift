import UserNotifications

/// The centre's delegate, set at launch in `BlipJournalApp`'s `AppDelegate` so a
/// cold-launch tap is never missed.
///
/// Constructed once (`shared`) before any `AppModel` exists. A tap arriving before a
/// coordinator has attached is stashed and claimed by the first coordinator to attach,
/// which is how a cold launch from a notification tap survives store setup.
@MainActor
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    weak var coordinator: (any NotificationCoordinating)?
    private var pendingPromptIdBeforeAttach: String?

    override private init() {}

    /// Attaches `coordinator` and hands back any route a tap stashed before this call.
    func attach(_ coordinator: any NotificationCoordinating) -> String? {
        self.coordinator = coordinator
        defer { pendingPromptIdBeforeAttach = nil }
        return pendingPromptIdBeforeAttach
    }

    /// Shows the notification even while the app is in the foreground.
    ///
    /// `nonisolated` because `UNUserNotificationCenter` and `UNNotification` are not
    /// `Sendable`; the system calls this off the main actor, so it does not touch any
    /// main-actor state.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Routes the tap: to the live coordinator if one has attached, otherwise stashed
    /// for the coordinator constructed during this cold launch to claim.
    ///
    /// `nonisolated` for the same reason as `willPresent`; the identifier it extracts is
    /// `Sendable`, so hopping to the main actor to store it is safe.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let promptId = response.notification.request.content.userInfo["promptId"] as? String else { return }
        await MainActor.run {
            if let coordinator {
                coordinator.pendingRoute = promptId
            } else {
                pendingPromptIdBeforeAttach = promptId
            }
        }
    }
}
