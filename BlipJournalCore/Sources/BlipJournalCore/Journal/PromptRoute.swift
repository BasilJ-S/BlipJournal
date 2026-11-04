import Foundation

/// Resolves a notification tap against current stored data.
public enum PromptRoute {
    /// The routing decision, pure of the view layer so it can be unit tested directly.
    /// Mutates the store only to mark a lapsed-but-still-pending prompt missed; every
    /// other case only reads.
    public enum Outcome: Equatable {
        case unavailable(message: String)
        case runner(survey: Survey, promptId: String?)
        case detail(entry: Entry)
        case deadEnd(message: String, survey: Survey)
    }

    public static func resolve(
        promptId: String, now: Date, store: Store, surveysById: [String: Survey]
    ) -> Outcome {
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
