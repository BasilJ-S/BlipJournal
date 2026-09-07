import BlipJournalCore
import SwiftUI

/// What a tapped notification opens. Presented by `RootView` as a sheet whenever
/// `AppModel.notifications.pendingRoute` is non-nil.
///
/// Resolves the prompt, its survey, and any entry already linked to it, then decides
/// between resuming a draft, showing a completed entry read-only, opening a fresh runner,
/// or explaining why none of those apply. See `DESIGN.md` for the full decision table.
struct PromptRouteView: View {
    @Environment(AppModel.self) private var appModel
    let promptId: String
    let onFinish: () -> Void

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case resolved(RoutingOutcome)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                NavigationStack {
                    ProgressView()
                        .accessibilityLabel("Loading")
                }
                .task { await resolve() }
            case .resolved(.unavailable(let message)):
                deadEndView(title: "Not available", message: message, survey: nil)
            case .resolved(.runner(let survey, let promptId)):
                NavigationStack {
                    SurveyRunnerView(survey: survey, promptId: promptId, onFinish: onFinish)
                }
            case .resolved(.detail(let entry)):
                NavigationStack { EntryDetailView(entry: entry) }
            case .resolved(.deadEnd(let message, let survey)):
                deadEndView(title: survey.name, message: message, survey: survey)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blipScreenBackground()
    }

    @ViewBuilder
    private func deadEndView(title: String, message: String, survey: Survey?) -> some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "bell.slash")
            } description: {
                Text(message)
            } actions: {
                if let survey {
                    Button("Log an entry anyway") {
                        phase = .resolved(.runner(survey: survey, promptId: nil))
                    }
                }
                Button("Dismiss") { onFinish() }
            }
        }
    }

    private func resolve() async {
        let outcome = Self.route(
            promptId: promptId, now: Date(), store: appModel.store, surveysById: appModel.surveysById)
        try? appModel.refresh()
        phase = .resolved(outcome)
    }

    /// The routing decision, pure of the view layer so it can be unit tested directly.
    /// Mutates the store only to mark a lapsed-but-still-pending prompt missed; every
    /// other case only reads.
    enum RoutingOutcome: Equatable {
        case unavailable(message: String)
        case runner(survey: Survey, promptId: String?)
        case detail(entry: Entry)
        case deadEnd(message: String, survey: Survey)
    }

    static func route(
        promptId: String, now: Date, store: Store, surveysById: [String: Survey]
    ) -> RoutingOutcome {
        guard let prompt = (try? store.prompts(status: nil))?.first(where: { $0.id == promptId }) else {
            return .unavailable(message: "This prompt is no longer available.")
        }
        guard let survey = surveysById[prompt.surveyId] else {
            return .unavailable(message: "This prompt's survey has been deleted.")
        }

        let entries = (try? store.entries(surveyId: survey.id, from: nil, to: nil)) ?? []
        if let entry = entries.first(where: { $0.promptId == prompt.id }) {
            return entry.completedAt == nil
                ? .runner(survey: survey, promptId: prompt.id)
                : .detail(entry: entry)
        }

        if prompt.status == .pending, !prompt.isExpired(at: now) {
            return .runner(survey: survey, promptId: prompt.id)
        }

        if prompt.status == .answered {
            return .deadEnd(
                message: "This prompt was already answered, but its entry was deleted.", survey: survey)
        }

        if prompt.status == .pending {
            // Expired since it was scheduled, but the next refresh hasn't caught up yet.
            try? store.setPromptStatus(prompt.id, .missed, respondedAt: now)
        }
        return .deadEnd(message: "This prompt expired before it was answered.", survey: survey)
    }
}
