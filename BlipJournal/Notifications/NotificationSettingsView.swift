import BlipJournalCore
import SwiftUI
import UserNotifications

/// Reached from Settings → Notifications. Never requests system permission on its own;
/// only the explicit "Enable notifications" button does.
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isRequesting = false
    @State private var isRefreshing = false
    @State private var isRescheduling = false
    @State private var rescheduleMessage: String?
    @State private var upcoming: [UpcomingPrompt] = []
    #if DEBUG
    @State private var testMessage: String?
    #endif

    private struct UpcomingPrompt: Identifiable {
        let id: String
        let surveyName: String
        let scheduledAt: Date
    }

    private var status: UNAuthorizationStatus { appModel.notifications.authorizationStatus }

    var body: some View {
        List {
            Section {
                LabeledContent("Status", value: Self.statusText(status))
            }

            switch status {
            case .notDetermined:
                explanationSection
            case .denied:
                deniedSection
            case .authorized, .provisional, .ephemeral:
                authorizedSection
            @unknown default:
                explanationSection
            }

            #if DEBUG
            testSection
            #endif
        }
        .blipScreen("Notifications")
        .task { await loadUpcoming() }
    }

    private var explanationSection: some View {
        Section {
            Text("Blip Journal asks how you are at a few random moments each day. It needs "
                + "permission to send those prompts.")
                .foregroundStyle(.secondary)
            Button {
                Task { await requestAuthorization() }
            } label: {
                if isRequesting {
                    ProgressView()
                } else {
                    Text("Enable notifications")
                }
            }
            .disabled(isRequesting)
            .accessibilityLabel("Enable notifications")
        }
    }

    private var deniedSection: some View {
        Section {
            Text("Blip Journal cannot send prompts until notifications are allowed in "
                + "Settings. Manual journaling, surveys, insights and export all still work.")
                .foregroundStyle(.secondary)
            Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                .accessibilityLabel("Open system notification settings")
        }
    }

    private var authorizedSection: some View {
        Section {
            Text("Prompts may be silenced by Focus.")
                .foregroundStyle(.secondary)

            if upcoming.isEmpty {
                Text("No prompts scheduled")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcoming) { prompt in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prompt.surveyName)
                        Text(prompt.scheduledAt, format: .dateTime.day().month().hour().minute())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Button {
                Task { await refreshSchedule() }
            } label: {
                if isRefreshing {
                    ProgressView()
                } else {
                    Text("Refresh schedule")
                }
            }
            .disabled(isRefreshing || isRescheduling)
            .accessibilityLabel("Refresh schedule")

            Text("Refresh keeps existing prompt times, fills missing days, and restores scheduled notifications. "
                + "If today has no prompts left, it can add more within your daily limit and time window.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task { await reschedule() }
            } label: {
                if isRescheduling {
                    ProgressView()
                } else {
                    Text("Reschedule")
                }
            }
            .disabled(isRefreshing || isRescheduling)
            .accessibilityLabel("Reschedule all future prompts")

            Text("Choose new random times for all future prompts. Past prompts and answers stay saved. "
                + "Daily limits, time windows, and minimum gaps still apply.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let rescheduleMessage {
                Text(rescheduleMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if DEBUG
    /// Debug builds only: fires a real local notification a few seconds out so a tap can be
    /// exercised on device without waiting for the sampler to pick a time. It borrows the
    /// soonest pending prompt's identifier when there is one, so the tap routes into the
    /// runner exactly as a scheduled prompt would; with no pending prompt it uses a
    /// stand-in identifier and `PromptRouteView` shows its "no longer available" dead end.
    ///
    /// It writes straight to the notification centre rather than through the coordinator:
    /// this is a test affordance, not part of the scheduling contract, and the next
    /// refresh reconciles whatever it left behind.
    private var testSection: some View {
        Section("Debug") {
            Button("Send a test prompt in 15 seconds") {
                Task { await sendTestPrompt() }
            }
            .accessibilityLabel("Send a test prompt in 15 seconds")

            Text("Tap this, then leave the app. Tap the banner when it arrives.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let testMessage {
                Text(testMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sendTestPrompt() async {
        let prompts = (try? appModel.store.prompts(status: .pending)) ?? []
        let soonest = prompts.sorted { $0.scheduledAt < $1.scheduledAt }.first
        let identifier = soonest?.id ?? "debug-test-prompt"

        let content = UNMutableNotificationContent()
        content.title = "Blip Journal"
        content.body = "Test prompt — tap me."
        content.sound = .default
        content.categoryIdentifier = NotificationCoordinator.categoryIdentifier
        content.userInfo = ["promptId": identifier]
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false))

        do {
            try await UNUserNotificationCenter.current().add(request)
            testMessage = soonest == nil
                ? "Scheduled with a stand-in prompt; the tap should reach the dead-end screen."
                : "Scheduled against your next real prompt; the tap should open its survey."
        } catch {
            testMessage = "Couldn't schedule: \(String(describing: error))"
        }
    }
    #endif

    private func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        _ = await appModel.notifications.requestAuthorization()
        await appModel.notifications.refresh(now: Date())
        await loadUpcoming()
    }

    private func refreshSchedule() async {
        guard !isRefreshing, !isRescheduling else { return }
        isRefreshing = true
        rescheduleMessage = nil
        defer { isRefreshing = false }
        await appModel.notifications.refresh(now: Date())
        await loadUpcoming()
    }

    private func reschedule() async {
        guard !isRefreshing, !isRescheduling else { return }
        isRescheduling = true
        rescheduleMessage = nil
        defer { isRescheduling = false }
        let succeeded = await appModel.notifications.reschedule(now: Date())
        await loadUpcoming()
        rescheduleMessage = succeeded
            ? "Schedule reset. New times follow your survey settings."
            : "Couldn’t finish rescheduling. Check notification permission and try Refresh schedule."
    }

    private func loadUpcoming() async {
        let now = Date()
        let prompts = (try? appModel.store.prompts(status: .pending)) ?? []
        upcoming = prompts
            .filter { $0.scheduledAt > now }
            .sorted { $0.scheduledAt < $1.scheduledAt }
            .prefix(5)
            .map { prompt in
                UpcomingPrompt(
                    id: prompt.id,
                    surveyName: appModel.surveysById[prompt.surveyId]?.name ?? "Unknown survey",
                    scheduledAt: prompt.scheduledAt)
            }
    }

    private static func statusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .authorized: "Allowed"
        case .provisional: "Allowed quietly"
        case .ephemeral: "Allowed for this session"
        @unknown default: "Unknown"
        }
    }
}
