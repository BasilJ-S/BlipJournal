import Testing
@testable import OpenBlip

@MainActor
struct JournalRowSummaryTests {
    @Test func cancelledOlderLoadCannotOverwriteNewerSummary() async {
        let summary = JournalRowSummary()
        let oldRead = ControlledRead()
        let newRead = ControlledRead()

        let oldTask = Task { await summary.load { await oldRead.read() } }
        await oldRead.waitUntilStarted()
        oldTask.cancel()

        let newTask = Task { await summary.load { await newRead.read() } }
        await newRead.waitUntilStarted()
        newRead.finish("7 of 7")
        await newTask.value
        #expect(summary.value == "7 of 7")

        // The cancelled database read still completes, after the replacement task.
        oldRead.finish("2 of 7")
        await oldTask.value
        #expect(summary.value == "7 of 7")
    }

    @Test func cancelledOlderLoadCannotRestoreSummaryAfterNewerNil() async {
        let summary = JournalRowSummary()
        let oldRead = ControlledRead()
        let oldTask = Task { await summary.load { await oldRead.read() } }
        await oldRead.waitUntilStarted()
        oldTask.cancel()

        await summary.load { nil }
        oldRead.finish("2 of 7")
        await oldTask.value
        #expect(summary.value == nil)
    }
}

/// Explicit barriers control completion order without sleeps or scheduler assumptions.
@MainActor
private final class ControlledRead {
    private var result: CheckedContinuation<String?, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func read() async -> String? {
        await withCheckedContinuation { continuation in
            result = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if result != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ value: String?) {
        precondition(result != nil)
        result?.resume(returning: value)
        result = nil
    }
}
