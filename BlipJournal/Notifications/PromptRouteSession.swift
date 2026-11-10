import BlipJournalCore
import Foundation
import Observation

/// Presentation state shared by route resolution and its runner.
@MainActor @Observable
final class PromptRouteSession {
    private(set) var outcome: PromptRoute.Outcome?
    private(set) var draft: EntryDraft?
    private(set) var promptId: String?

    private var generation = 0

    func resolve(promptId: String, appModel: AppModel, now: Date = Date()) async throws {
        generation += 1
        guard self.promptId != promptId, !appModel.isLocked else { return }
        let request = generation
        do { try await draft?.flush() }
        catch EntryDraft.Error.completed {
            // The stored entry is closed; its rejected edits cannot block another prompt.
        } catch {
            guard request == generation, !Task.isCancelled else { return }
            throw error
        }
        try Task.checkCancellation()
        guard request == generation, !appModel.isLocked else { return }
        let outcome = PromptRoute.resolve(
            promptId: promptId, now: now, store: appModel.store, surveysById: appModel.surveysById)
        var nextDraft: EntryDraft?
        if case .runner(let survey, let id) = outcome {
            nextDraft = try EntryDraft(store: appModel.store, survey: survey, promptId: id, now: now)
        }
        draft = nextDraft
        self.promptId = promptId
        self.outcome = outcome
    }
    func startManual(survey: Survey, store: Store) throws {
        draft = try EntryDraft(store: store, survey: survey, promptId: nil)
        outcome = .runner(survey: survey, promptId: nil)
    }
}
