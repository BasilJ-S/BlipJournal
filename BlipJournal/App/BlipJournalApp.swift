import UserNotifications
import SwiftUI

/// Sets the notification centre's delegate before SwiftUI builds anything, so a cold
/// launch from tapping a notification, or from one of its answer actions, is never missed.
///
/// Categories are left to `NotificationCoordinator`'s reconcile, which registers the plain
/// `PROMPT` category with one answer category per question before adding any request.
/// Registering here would replace that set on every launch and strip the answer actions
/// from delivered notifications until the next foreground refresh.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        return true
    }
}

@main
struct BlipJournalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var launch: Launch
    @State private var privacyShield = PrivacyShield()

    /// Either a working model or the reason there is none. Store errors at launch are
    /// fatal in v0: there is no recovery path, and hiding them would be worse.
    private enum Launch {
        case ready(AppModel)
        case failed(String)
    }

    init() {
        BlipAppearance.configure()
        do {
            _launch = State(initialValue: .ready(try AppModel.live()))
        } catch {
            _launch = State(initialValue: .failed(String(describing: error)))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch launch {
            case .ready(let appModel):
                // The lock replaces the content rather than covering it. A sheet or
                // dialog presented from inside RootView is presented above the whole
                // root view, so an overlay lock would leave it on screen and usable;
                // removing RootView tears its presentations down with it.
                Group {
                    if appModel.isLocked {
                        LockView()
                    } else {
                        RootView()
                    }
                }
                .environment(appModel)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    // The shield goes up on leaving `.active`, before the app-switcher
                    // snapshot is taken. While locked, `LockView` shows nothing private.
                    switch phase {
                    case .background:
                        if !appModel.isLocked { privacyShield.show() }
                        appModel.didEnterBackground(at: Date())
                    case .active:
                        // Lock first: on a relock the shield stays up until the
                        // `isLocked` change below, so the old content never shows.
                        appModel.willEnterForeground(at: Date())
                        if !appModel.isLocked { privacyShield.hide() }
                    case .inactive:
                        // The notification permission alert also makes the scene
                        // inactive; covering the screen then would hide the
                        // explanation the alert follows.
                        if !appModel.isLocked && !appModel.notifications.isRequestingAuthorization {
                            privacyShield.show()
                        }
                    @unknown default:
                        break
                    }
                }
                // "Open in Blip Journal" from Files, Mail or a share sheet. Read now,
                // while the URL is valid; previewed once unlocked.
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    appModel.pendingSurveyImport = PendingSurveyImport(fileAt: url)
                }
                .onChange(of: appModel.isLocked) { _, isLocked in
                    if isLocked { privacyShield.hide() }
                }
            case .failed(let message):
                LaunchFailureView(message: message)
                    .preferredColorScheme(.light)
            }
        }
    }
}

/// Full-screen report of a store error at launch.
struct LaunchFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Blip Journal could not open its database")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blipScreenBackground()
    }
}
