import Foundation
import Testing
@testable import BlipJournalCore

@Suite("RunningOutWarning")
struct RunningOutWarningTests {
    typealias F = SamplingFixtures
    let start = F.date(2026, 9, 5, 9, 0)

    /// A pending prompt `hours` after `start`.
    func prompt(_ id: String, survey: String = "s", hours: Double) -> Prompt {
        F.prompt(id: id, survey: survey, at: start.addingTimeInterval(hours * 3600))
    }

    // MARK: Selection

    @Test("one survey: the last three by fire time count down to one")
    func oneSurvey() {
        let prompts = (0..<6).map { prompt("p\($0)", hours: Double($0)) }
        // Shuffled input: order comes from fire time, not from the array.
        let result = RunningOutWarning.remainingCounts(scheduled: Array(prompts.reversed()))
        #expect(result == ["p3": 3, "p4": 2, "p5": 1])
    }

    @Test("several surveys: the last three are picked across every survey")
    func severalSurveys() {
        let prompts = [
            prompt("a0", survey: "a", hours: 0),
            prompt("b0", survey: "b", hours: 1),
            prompt("a1", survey: "a", hours: 2),
            prompt("b1", survey: "b", hours: 3),
            prompt("c0", survey: "c", hours: 4),
            prompt("a2", survey: "a", hours: 5),
        ]
        let result = RunningOutWarning.remainingCounts(scheduled: prompts)
        #expect(result == ["b1": 3, "c0": 2, "a2": 1])
    }

    @Test("fewer than three pending: every prompt is marked", arguments: [0, 1, 2, 3])
    func fewerThanThree(count: Int) {
        let prompts = (0..<count).map { prompt("p\($0)", hours: Double($0)) }
        let result = RunningOutWarning.remainingCounts(scheduled: prompts)
        #expect(result.count == count)
        for index in 0..<count {
            #expect(result["p\(index)"] == count - index)
        }
    }

    @Test("a reschedule that adds later prompts moves the warning onto them")
    func rescheduleMovesWarning() {
        let before = (0..<4).map { prompt("old\($0)", hours: Double($0)) }
        #expect(RunningOutWarning.remainingCounts(scheduled: before) == ["old1": 3, "old2": 2, "old3": 1])

        // Opening the app schedules more; old0 has fired and is no longer scheduled.
        let after = Array(before.dropFirst()) + (0..<3).map { prompt("new\($0)", hours: 24 + Double($0)) }
        let result = RunningOutWarning.remainingCounts(scheduled: after)
        #expect(result == ["new0": 3, "new1": 2, "new2": 1])
        #expect(result["old3"] == nil)
    }

    @Test("prompts at the same instant are ordered by identifier")
    func tiesBreakByIdentifier() {
        let prompts = [
            prompt("z", survey: "a", hours: 2),
            prompt("y", survey: "b", hours: 2),
            prompt("x", survey: "c", hours: 1),
            prompt("w", survey: "a", hours: 0),
        ]
        let result = RunningOutWarning.remainingCounts(scheduled: prompts)
        #expect(result == ["x": 3, "y": 2, "z": 1])
    }

    // MARK: Wording

    @Test("the count says how many remain including itself, and how to get more")
    func countdownMessage() {
        #expect(RunningOutWarning.message(remaining: 3) == "3 check-ins left. Open Blip Journal to schedule more.")
        #expect(RunningOutWarning.message(remaining: 2) == "2 check-ins left. Open Blip Journal to schedule more.")
    }

    @Test("the last prompt says it is the last one scheduled")
    func lastMessage() {
        #expect(RunningOutWarning.message(remaining: 1) == "Last check-in scheduled. Open Blip Journal to schedule more.")
    }

    @Test("the warning keeps the preview's title and body and adds a line")
    func contentKeepsPreview() {
        let base = NotificationPreview.custom(message: "How's it going?").content(surveyName: "Secret")
        let warned = RunningOutWarning.content(base, remaining: 2)
        #expect(warned.title == "Blip Journal")
        #expect(warned.body == "How's it going?\n2 check-ins left. Open Blip Journal to schedule more.")
        #expect(!warned.body.contains("Secret"))
    }

    @Test("matches accepts the plain content and every warned variant, nothing else")
    func matches() {
        let base = NotificationPreview.private.content(surveyName: "s")
        #expect(RunningOutWarning.matches(base, base: base))
        for remaining in 1...RunningOutWarning.promptCount {
            #expect(RunningOutWarning.matches(RunningOutWarning.content(base, remaining: remaining), base: base))
        }
        let renamed = NotificationPreview.surveyName.content(surveyName: "Mood")
        #expect(!RunningOutWarning.matches(renamed, base: base))
        #expect(!RunningOutWarning.matches(RunningOutWarning.content(renamed, remaining: 1), base: base))
    }
}
