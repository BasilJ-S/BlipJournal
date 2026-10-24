import SwiftUI

/// Shown once, the first time the app is unlocked: what Blip Journal does, and the only
/// place outside Settings → Notifications that asks for notification permission. The
/// system prompt only ever follows the explanation here, never cold.
struct WelcomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isRequesting = false
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BlipMark(size: 72)
                Text("Welcome to Blip Journal")
                    .blipFont(.title, size: 30, relativeTo: .largeTitle)
                    .foregroundStyle(BlipBrand.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 16) {
                    point("bell", "A few times a day, at random moments, Blip Journal asks a short survey about how you are and what you are doing.")
                    point("slider.horizontal.3", "Answering takes a few seconds. Change the questions and the schedule any time in Settings.")
                    point("lock", "Everything stays on this iPhone. Nothing is sent anywhere, and you can export or erase it whenever you like.")
                }
                Text("Prompts arrive as notifications, so Blip Journal needs permission to send them.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .fontDesign(.rounded)
        .blipScreenBackground()
    }

    private func point(_ systemImage: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(BlipBrand.violet)
                .accessibilityHidden(true)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await enable() }
            } label: {
                Group {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Text("Enable notifications")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
            .accessibilityLabel("Enable notifications")

            Button {
                onFinish()
            } label: {
                Text("Not now")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(isRequesting)
            .accessibilityLabel("Not now")
            .accessibilityHint("You can turn on prompts later in Settings, Notifications.")
        }
        .padding(24)
        .background(BlipBrand.paper)
    }

    private func enable() async {
        guard !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        _ = await appModel.notifications.requestAuthorization()
        await appModel.notifications.refresh(now: Date())
        try? appModel.refresh()
        onFinish()
    }
}
