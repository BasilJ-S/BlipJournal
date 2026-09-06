import Observation

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
}
