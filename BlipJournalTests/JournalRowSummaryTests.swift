import Testing
import BlipJournalCore
@testable import BlipJournal

@MainActor
struct JournalRowSummaryTests {
    @Test func rendersTwoConfiguredAnswersInOrderAndOmitsAnUnansweredChoice() {
        let mood = Question(
            id: "mood", kind: .scale, label: "Mood", position: 0,
            scale: ScaleConfig(min: 1, max: 7, minLabel: "Low", maxLabel: "High"))
        let activity = Question(
            id: "activity", kind: .singleChoice, label: "Activity", position: 1,
            options: [ChoiceOption(id: "work", label: "Working", position: 0)])
        let survey = Survey(
            name: "Check-in", journalSummaryQuestionIds: [activity.id, mood.id],
            questions: [mood, activity])
        let answers = [
            Answer(
                entryId: "entry", questionId: mood.id, questionVersionId: "mv",
                value: .scale(5)),
            Answer(
                entryId: "entry", questionId: activity.id, questionVersionId: "av",
                value: .single(optionId: "work")),
        ]

        #expect(JournalRowSummary.text(answers: answers, survey: survey) == "Working · 5 of 7")
        #expect(JournalRowSummary.text(answers: [answers[0]], survey: survey) == "5 of 7")
        #expect(JournalRowSummary.text(answers: [], survey: survey) == nil)
    }

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
