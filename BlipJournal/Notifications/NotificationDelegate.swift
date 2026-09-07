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

    // MARK: UNUserNotificationCenterDelegate
    //
    // Both callbacks take the completion-handler form rather than the shorter `async`
    // one, and both resume on the main actor before calling it. UIKit runs
    // main-thread-only work (`-[UIApplication _updateSnapshotAndStateRestorationWithAction:
    // windowScene:]`, which asserts inside `_performBlockAfterCATransactionCommitSynchronizes:`)
    // synchronously inside these completion handlers. A `nonisolated async` delegate
    // method runs on the cooperative pool, and the compiler-synthesized `@objc` thunk
    // calls the completion handler from that same background thread, so UIKit's
    // assertion fires as an uncaught Objective-C exception and the app is killed with
    // SIGABRT — which looked like a tapped notification bouncing straight back to the
    // Home Screen. Never reintroduce the `async` form.

    /// Shows the notification even while the app is in the foreground.
    ///
    /// `nonisolated` because `UNUserNotificationCenter` and `UNNotification` are not
    /// `Sendable`; nothing here touches main-actor state before the hop.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler([.banner, .sound])
        }
    }

    /// Routes the tap: to the live coordinator if one has attached, otherwise stashed
    /// for the coordinator constructed during this cold launch to claim.
    ///
    /// `nonisolated` for the same reason as `willPresent`; the identifier it reads out of
    /// the non-`Sendable` response is a `String`, so carrying it to the main actor is safe.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let promptId = response.notification.request.content.userInfo["promptId"] as? String
        Task { @MainActor in
            if let promptId {
                if let coordinator = self.coordinator {
                    coordinator.pendingRoute = promptId
                } else {
                    self.pendingPromptIdBeforeAttach = promptId
                }
            }
            completionHandler()
        }
    }
}
