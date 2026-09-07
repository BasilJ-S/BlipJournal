import BlipJournalCore
import SwiftUI
import UserNotifications

/// Reached from Settings → Notifications. Never requests system permission on its own;
/// only the explicit "Enable notifications" button does.
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isRequesting = false
    @State private var isRefreshing = false
    @State private var upcoming: [UpcomingPrompt] = []

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
            .disabled(isRefreshing)
            .accessibilityLabel("Refresh schedule")
        }
    }

    private func requestAuthorization() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        _ = await appModel.notifications.requestAuthorization()
        await appModel.notifications.refresh(now: Date())
        await loadUpcoming()
    }

    private func refreshSchedule() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await appModel.notifications.refresh(now: Date())
        await loadUpcoming()
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
