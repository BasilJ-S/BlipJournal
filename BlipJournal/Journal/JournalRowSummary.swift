import Observation
import BlipJournalCore

/// Presentation state shared by successive revision-driven tasks for one Journal row.
@MainActor @Observable
final class JournalRowSummary {
    private(set) var value: String?

    func load(using read: () async -> String?) async {
        guard !Task.isCancelled else { return }
        value = nil
        let result = await read()
        // SQLite may finish after SwiftUI cancels this revision's task.
        guard !Task.isCancelled else { return }
        value = result
    }

    /// Renders only configured, answered questions, preserving their chosen order.
    nonisolated static func text(answers: [Answer], survey: Survey) -> String? {
        let rendered = survey.journalSummaryQuestions.compactMap { question in
            answers.first(where: { $0.questionId == question.id }).map {
                EntryDetailView.render($0.value, for: question)
            }
        }
        return rendered.isEmpty ? nil : rendered.joined(separator: " · ")
    }
}
