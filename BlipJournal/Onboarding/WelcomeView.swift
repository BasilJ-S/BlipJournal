import BlipJournalCore
import SwiftUI
import UserNotifications

/// Shown once, the first time the app is unlocked: what Blip Journal does, and the only
/// place outside Settings → Notifications that asks for notification permission. The
/// system prompt only ever follows the explanation here, never cold. A second step offers
/// the survey template gallery, once.
struct WelcomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isRequesting = false
    @State private var isChoosingSurvey = false
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        if isChoosingSurvey { surveyStep } else { welcome }
    }

    private var welcome: some View {
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
                Text(permissionText)
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

    /// Someone updating from an earlier build may already have decided; asking again
    /// would show a button that visibly does nothing.
    private var permissionDecided: Bool {
        appModel.notifications.canDeliverPrompts || appModel.notifications.authorizationStatus == .denied
    }

    private var permissionText: String {
        if appModel.notifications.canDeliverPrompts {
            "Notifications are on, so prompts will arrive on schedule."
        } else if appModel.notifications.authorizationStatus == .denied {
            "Notifications are off for Blip Journal. You can allow them any time in the Settings app; until then, log entries yourself from the Journal."
        } else {
            "Prompts arrive as notifications, so Blip Journal needs permission to send them."
        }
    }

    @ViewBuilder
    private var buttons: some View {
        // Keep the permission buttons up while a request is in flight, so granting does
        // not swap them for Continue under the person's finger.
        if permissionDecided && !isRequesting {
            Button {
                isChoosingSurvey = true
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Continue")
            .padding(24)
            .background(BlipBrand.paper)
        } else {
            permissionButtons
        }
    }

    private var permissionButtons: some View {
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
                isChoosingSurvey = true
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
        isChoosingSurvey = true
    }

    private var galleryIntro: String {
        let start = "Blip Journal starts you with a survey about mood and feelings. To look into something else as well, add a template"
        if appModel.notifications.canDeliverPrompts {
            return start + ". It starts right away, and its prompts come on top of the mood survey's. A blank survey starts paused until you add questions."
        }
        return start + " or a blank survey. Surveys you add start paused: to turn one on, go to Settings → Surveys → the survey → Sampling → Enable sampling."
    }

    private func startSampling(_ survey: Survey) async {
        // If this fails the survey simply stays paused, as every new survey starts.
        _ = try? await EditorModel(store: appModel.store, notifications: appModel.notifications)
            .startSamplingAfterOnboarding(surveyId: survey.id)
        try? appModel.refresh()
        onFinish()
    }

    /// The gallery, without the template a fresh install already has. Adding a survey or
    /// skipping finishes the welcome; a template added here starts sampling when prompts
    /// can arrive (`EditorModel.startSamplingAfterOnboarding`).
    private var surveyStep: some View {
        NavigationStack {
            TemplateGalleryView(
                intro: galleryIntro,
                excluding: [SurveyTemplateGallery.defaultSurveyTemplateId],
                onAdded: { survey in Task { await startSampling(survey) } })
                .blipScreen("Add a survey?")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Skip") { onFinish() }
                            .accessibilityHint("Keeps just the mood and feelings survey.")
                    }
                }
        }
    }
}
