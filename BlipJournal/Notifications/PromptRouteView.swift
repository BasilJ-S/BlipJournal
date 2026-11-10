import BlipJournalCore
import SwiftUI

/// What a tapped notification opens. Presented by `RootView` as a sheet whenever
/// `AppModel.notifications.pendingRoute` is non-nil.
///
/// Resolves the prompt, its survey, and any entry already linked to it, then decides
/// between resuming a draft, showing a completed entry read-only, opening a fresh runner,
/// or explaining why none of those apply. See Core `Prompts/DESIGN.md` for the full decision table.
struct PromptRouteView: View {
    @Environment(AppModel.self) private var appModel
    let promptId: String
    let onFinish: () -> Void

    @State private var session = PromptRouteSession()
    @State private var errorMessage: String?
    @State private var manualStartFailed = false
    private static let routeFailureMessage = "Your entry couldn’t be saved or opened. Try again, or keep the current entry open."

    var body: some View {
        Group {
            switch session.outcome {
            case nil:
                NavigationStack {
                    ProgressView()
                        .accessibilityLabel("Loading")
                }
            case .unavailable(let message):
                deadEndView(title: "Not available", message: message, survey: nil)
            case .runner:
                NavigationStack {
                    if let draft = session.draft {
                        SurveyRunnerView(draft: draft, onFinish: onFinish)
                            .id(draft.entry.id)
                    }
                }
            case .detail(let entry):
                NavigationStack { EntryDetailView(entry: entry).id(entry.id) }
            case .deadEnd(let message, let survey):
                deadEndView(title: survey.name, message: message, survey: survey)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .blipScreenBackground()
        .disabled(session.promptId != promptId)
        .interactiveDismissDisabled(session.promptId != promptId)
        .task(id: promptId) { await resolve() }
        .alert(manualStartFailed ? "Could not start entry" : "Could not open prompt", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            if manualStartFailed {
                Button("OK", role: .cancel) { }
            } else {
                Button("Retry") { Task { await resolve() } }
                Button(session.promptId == nil ? "Dismiss" : "Keep current entry", role: .cancel) {
                    if let previous = session.promptId { appModel.notifications.pendingRoute = previous }
                    else { onFinish() }
                }
            }
        } message: { Text(errorMessage ?? "") }
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
                        do { try session.startManual(survey: survey, store: appModel.store) }
                        catch {
                            manualStartFailed = true
                            errorMessage = "Couldn’t start an entry. Try again."
                        }
                    }
                }
                Button("Dismiss") { onFinish() }
            }
        }
    }

    private func resolve() async {
        do {
            try await session.resolve(promptId: promptId, appModel: appModel)
            try? appModel.refresh()
        } catch is CancellationError {
            // A newer route owns the next resolution.
        } catch {
            manualStartFailed = false
            errorMessage = Self.routeFailureMessage
        }
    }

}
