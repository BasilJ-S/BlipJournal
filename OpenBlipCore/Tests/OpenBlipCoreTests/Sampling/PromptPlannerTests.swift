import Foundation
import Testing
@testable import OpenBlipCore

@Suite("PromptPlanner")
struct PromptPlannerTests {
    typealias F = SamplingFixtures
    let calendar = F.toronto
    /// A Saturday afternoon.
    let now = F.date(2026, 9, 5, 14, 0)

    func plan(
        _ planner: PromptPlanner = PromptPlanner(),
        now: Date? = nil,
        surveys: [Survey],
        existing: [Prompt] = [],
        seed: UInt64 = 1
    ) -> PromptPlan {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return planner.plan(
            now: now ?? self.now, surveys: surveys, existing: existing, calendar: calendar, using: &rng
        )
    }

    func dayKeys(_ prompts: [Prompt]) -> Set<String> {
        Set(prompts.map(\.day))
    }

    // MARK: Missed

    @Test("overdue pending prompts are missed, answered ones are left alone")
    func overdueIsMissed() {
        let overdue = F.prompt(id: "overdue", survey: "s", at: now.addingTimeInterval(-3600))
        let atExpiry = F.prompt(id: "at-expiry", survey: "s", at: now.addingTimeInterval(-20 * 60))
        let live = F.prompt(id: "live", survey: "s", at: now.addingTimeInterval(-60))
        let answered = F.prompt(id: "answered", survey: "s", at: now.addingTimeInterval(-7200), status: .answered)
        let future = F.prompt(id: "future", survey: "s", at: now.addingTimeInterval(3600))

        let result = plan(surveys: [], existing: [future, live, answered, atExpiry, overdue])
        #expect(result.missedPromptIds == ["overdue", "at-expiry"])
        #expect(result.newPrompts.isEmpty)
    }

    @Test("a pending prompt superseded by a later prompt that has fired is missed")
    func supersededIsMissed() {
        // Long expiry so the older prompt is not simply expired.
        let older = F.prompt(id: "older", survey: "s", at: now.addingTimeInterval(-30 * 60), expiryMinutes: 240)
        let newer = F.prompt(id: "newer", survey: "s", at: now.addingTimeInterval(-5 * 60), expiryMinutes: 240)
        let result = plan(surveys: [], existing: [newer, older])
        #expect(result.missedPromptIds == ["older"])
    }

    @Test("supersession counts prompts of any status but only within the same survey")
    func supersessionScope() {
        let older = F.prompt(id: "older", survey: "s", at: now.addingTimeInterval(-30 * 60), expiryMinutes: 240)
        let answered = F.prompt(id: "answered", survey: "s", at: now.addingTimeInterval(-10 * 60), expiryMinutes: 240, status: .answered)
        let otherSurvey = F.prompt(id: "other", survey: "t", at: now.addingTimeInterval(-30 * 60), expiryMinutes: 240)
        let otherFired = F.prompt(id: "other-fired", survey: "u", at: now.addingTimeInterval(-5 * 60), expiryMinutes: 240)
        let result = plan(surveys: [], existing: [older, answered, otherSurvey, otherFired])
        #expect(result.missedPromptIds == ["older"])
    }

    @Test("a future prompt does not supersede a live one")
    func futureDoesNotSupersede() {
        let live = F.prompt(id: "live", survey: "s", at: now.addingTimeInterval(-5 * 60))
        let future = F.prompt(id: "future", survey: "s", at: now.addingTimeInterval(3600))
        let result = plan(surveys: [], existing: [live, future])
        #expect(result.missedPromptIds.isEmpty)
    }

    @Test("missed IDs are deduplicated and ascending by scheduledAt")
    func missedOrdering() {
        let a = F.prompt(id: "a", survey: "s", at: now.addingTimeInterval(-3 * 3600))
        let b = F.prompt(id: "b", survey: "t", at: now.addingTimeInterval(-2 * 3600))
        let c = F.prompt(id: "c", survey: "s", at: now.addingTimeInterval(-1 * 3600))
        // `c` is both expired and superseded by nothing; `a` is expired and superseded by `c`.
        let result = plan(surveys: [], existing: [c, a, b, a])
        #expect(result.missedPromptIds == ["a", "b", "c"])
    }

    // MARK: Eligibility

    @Test("an archived, disabled, invalid, or zero-count survey gets nothing")
    func ineligibleSurveys() {
        var disabled = SamplingConfig.default
        disabled.isEnabled = false
        var invalid = SamplingConfig.default
        invalid.windowEndMinutes = 100
        var zero = SamplingConfig.default
        zero.promptsPerDay = 0

        let surveys = [
            F.survey(id: "archived", isArchived: true),
            F.survey(id: "disabled", sampling: disabled),
            F.survey(id: "invalid", sampling: invalid),
            F.survey(id: "zero", sampling: zero),
        ]
        let result = plan(surveys: surveys)
        #expect(result.newPrompts.isEmpty)
        #expect(result.missedPromptIds.isEmpty)
    }

    // MARK: Generation

    @Test("one default survey with nothing existing gets a week of prompts")
    func defaultSurveyWeek() {
        let result = plan(surveys: [F.survey(id: "s")])
        let keys = dayKeys(result.newPrompts)
        #expect(keys == Set((0..<7).map { offset in
            DayKey.string(for: calendar.date(byAdding: .day, value: offset, to: now)!, calendar: calendar)
        }))
        // Six future days at 3 each, plus whatever of today is still ahead of 14:01.
        let future = result.newPrompts.filter { $0.day != "2026-09-05" }
        #expect(future.count == 18)
        for prompt in result.newPrompts {
            #expect(prompt.status == .pending)
            #expect(prompt.surveyId == "s")
            #expect(prompt.respondedAt == nil)
            #expect(prompt.expiresAt == prompt.scheduledAt.addingTimeInterval(20 * 60))
            #expect(prompt.day == DayKey.string(for: prompt.scheduledAt, calendar: calendar))
        }
    }

    @Test("today only yields times after now + 60s")
    func todayIsFutureOnly() {
        // 09:00 so most of the window is still ahead; check across many seeds.
        let morning = F.date(2026, 9, 5, 9, 0, 30)
        for seed in 0..<100 {
            let result = plan(now: morning, surveys: [F.survey(id: "s")], seed: UInt64(seed))
            let today = result.newPrompts.filter { $0.day == "2026-09-05" }
            for prompt in today {
                #expect(prompt.scheduledAt > morning.addingTimeInterval(60), "seed \(seed): \(prompt.scheduledAt)")
            }
        }
        // Late at night nothing is left of today, but tomorrow onward is full.
        let late = F.date(2026, 9, 5, 22, 59, 30)
        let result = plan(now: late, surveys: [F.survey(id: "s")])
        #expect(result.newPrompts.filter { $0.day == "2026-09-05" }.isEmpty)
        #expect(result.newPrompts.filter { $0.day == "2026-09-06" }.count == 3)
    }

    @Test("days already present in existing are skipped, whatever the status")
    func existingDaysSkipped() {
        let tomorrow = F.date(2026, 9, 6, 12, 0)
        let dayAfter = F.date(2026, 9, 7, 12, 0)
        let existing = [
            F.prompt(survey: "s", at: F.date(2026, 9, 5, 9, 30), status: .answered),
            F.prompt(survey: "s", at: tomorrow, status: .missed),
            F.prompt(survey: "s", at: dayAfter),
            F.prompt(survey: "t", at: tomorrow),
        ]
        let result = plan(surveys: [F.survey(id: "s"), F.survey(id: "t")], existing: existing)
        let sDays = dayKeys(result.newPrompts.filter { $0.surveyId == "s" })
        let tDays = dayKeys(result.newPrompts.filter { $0.surveyId == "t" })
        #expect(!sDays.contains("2026-09-05"))
        #expect(!sDays.contains("2026-09-06"))
        #expect(!sDays.contains("2026-09-07"))
        #expect(sDays.count == 4)
        #expect(!tDays.contains("2026-09-06"))
        #expect(tDays.contains("2026-09-05"))
        #expect(tDays.count == 6)
    }

    @Test("days before today are never generated even if the horizon is wide")
    func neverPast() {
        let result = plan(PromptPlanner(maxHorizonDays: 30), surveys: [F.survey(id: "s")])
        for prompt in result.newPrompts {
            #expect(prompt.day >= "2026-09-05")
            #expect(prompt.scheduledAt > now)
        }
    }

    @Test("two surveys with different windows each get their own prompts and expiry")
    func twoSurveys() {
        let morning = SamplingConfig(
            promptsPerDay: 2, windowStartMinutes: 480, windowEndMinutes: 720, minGapMinutes: 30, expiryMinutes: 10
        )
        let evening = SamplingConfig(
            promptsPerDay: 1, windowStartMinutes: 1080, windowEndMinutes: 1320, minGapMinutes: 0, expiryMinutes: 45
        )
        let result = plan(surveys: [F.survey(id: "m", sampling: morning), F.survey(id: "e", sampling: evening)])

        let m = result.newPrompts.filter { $0.surveyId == "m" }
        let e = result.newPrompts.filter { $0.surveyId == "e" }
        #expect(m.count == 2 * 6, "today's morning window is already over at 14:00")
        #expect(e.count == 1 * 7)
        for prompt in m {
            let minute = F.minuteOfDay(prompt.scheduledAt)
            #expect(minute >= 480 && minute < 720)
            #expect(prompt.expiresAt == prompt.scheduledAt.addingTimeInterval(10 * 60))
        }
        for prompt in e {
            let minute = F.minuteOfDay(prompt.scheduledAt)
            #expect(minute >= 1080 && minute < 1320)
            #expect(prompt.expiresAt == prompt.scheduledAt.addingTimeInterval(45 * 60))
        }
    }

    // MARK: Horizon

    @Test("horizon shrinks as dailyTotal grows and never exceeds maxHorizonDays")
    func horizon() {
        func days(perDay: Int, surveys: Int = 1, maxHorizonDays: Int = 7) -> Int {
            let config = SamplingConfig(promptsPerDay: perDay, windowStartMinutes: 0, windowEndMinutes: 1440, minGapMinutes: 1)
            let list = (0..<surveys).map { F.survey(id: "s\($0)", sampling: config) }
            // Plan from early morning so today counts as a full day.
            let result = plan(PromptPlanner(maxHorizonDays: maxHorizonDays), now: F.date(2026, 9, 5, 0, 30), surveys: list)
            return dayKeys(result.newPrompts).count
        }
        #expect(days(perDay: 3) == 7)             // 60/3 = 20, capped at 7
        #expect(days(perDay: 8) == 7)             // 60/8 = 7
        #expect(days(perDay: 9) == 6)             // 60/9 = 6
        #expect(days(perDay: 15) == 4)            // 60/15 = 4
        #expect(days(perDay: 20) == 3)            // 60/20 = 3
        #expect(days(perDay: 20, surveys: 3) == 1) // 60/60 = 1
        #expect(days(perDay: 20, surveys: 4) == 1) // 60/80 = 0, raised to 1
        #expect(days(perDay: 3, maxHorizonDays: 3) == 3)
        #expect(days(perDay: 1, maxHorizonDays: 10) == 10)
    }

    @Test("a zero or negative horizon yields nothing and does not trap")
    func nonPositiveHorizon() {
        #expect(plan(PromptPlanner(maxHorizonDays: 0), surveys: [F.survey(id: "s")]).newPrompts.isEmpty)
        #expect(plan(PromptPlanner(maxHorizonDays: -1), surveys: [F.survey(id: "s")]).newPrompts.isEmpty)
    }

    @Test("ineligible surveys do not count toward dailyTotal")
    func ineligibleNotInTotal() {
        var disabled = SamplingConfig(promptsPerDay: 20, windowStartMinutes: 0, windowEndMinutes: 1440, minGapMinutes: 1)
        disabled.isEnabled = false
        let result = plan(
            now: F.date(2026, 9, 5, 0, 30),
            surveys: [F.survey(id: "s"), F.survey(id: "off", sampling: disabled), F.survey(id: "gone", isArchived: true)]
        )
        #expect(dayKeys(result.newPrompts).count == 7)
    }

    // MARK: Cap

    @Test("total pending never exceeds maxPending, dropping the latest new prompts first")
    func capDropsLatest() {
        let config = SamplingConfig(promptsPerDay: 20, windowStartMinutes: 0, windowEndMinutes: 1440, minGapMinutes: 1)
        let surveys = (0..<4).map { F.survey(id: "s\($0)", sampling: config) }
        let early = F.date(2026, 9, 5, 0, 30)
        let result = plan(now: early, surveys: surveys)
        #expect(result.newPrompts.count == PromptPlanner.maxPending)

        // 4 surveys x 20 = 80 candidates on day one alone; the 60 kept are the earliest.
        let times = result.newPrompts.map(\.scheduledAt)
        #expect(times == times.sorted())
        #expect(dayKeys(result.newPrompts) == ["2026-09-05"])
        // 80 candidates spread over 24 hours: the 60th cannot land in the last three hours.
        #expect(times.last! < F.date(2026, 9, 5, 21, 0), "the tail of the day was dropped")
    }

    @Test("existing live pending prompts count against the cap")
    func capCountsExistingPending() {
        // 58 live pending prompts on days the planner will not touch.
        let farFuture = F.date(2026, 10, 1, 12, 0)
        let existing = (0..<58).map { index in
            F.prompt(survey: "other", at: farFuture.addingTimeInterval(Double(index) * 60))
        }
        let result = plan(surveys: [F.survey(id: "s")], existing: existing)
        #expect(result.newPrompts.count == 2)
        #expect(result.missedPromptIds.isEmpty)
    }

    @Test("prompts about to be missed free up room under the cap")
    func missedFreeRoom() {
        let farFuture = F.date(2026, 10, 1, 12, 0)
        let live = (0..<58).map { index in
            F.prompt(survey: "other", at: farFuture.addingTimeInterval(Double(index) * 60))
        }
        let overdue = (0..<10).map { index in
            F.prompt(id: "overdue-\(index)", survey: "other", at: F.date(2026, 9, 1, 12, index))
        }
        let result = plan(surveys: [F.survey(id: "s")], existing: live + overdue)
        #expect(result.missedPromptIds.count == 10)
        #expect(result.newPrompts.count == 2)
    }

    @Test("existing already at or over the cap yields no new prompts")
    func capAlreadyFull() {
        let farFuture = F.date(2026, 10, 1, 12, 0)
        let existing = (0..<65).map { index in
            F.prompt(survey: "other", at: farFuture.addingTimeInterval(Double(index) * 60))
        }
        let result = plan(surveys: [F.survey(id: "s")], existing: existing)
        #expect(result.newPrompts.isEmpty)
    }

    // MARK: Ordering and determinism

    @Test("output is ascending by scheduledAt and deterministic for a seed")
    func orderedAndDeterministic() {
        let surveys = [F.survey(id: "b"), F.survey(id: "a")]
        let first = plan(surveys: surveys, seed: 11)
        let second = plan(surveys: surveys, seed: 11)
        let other = plan(surveys: surveys, seed: 12)

        func shape(_ plan: PromptPlan) -> [(String, String, Date, Date)] {
            plan.newPrompts.map { ($0.surveyId, $0.day, $0.scheduledAt, $0.expiresAt) }
        }
        #expect(shape(first).elementsEqual(shape(second), by: ==))
        #expect(!shape(first).elementsEqual(shape(other), by: ==))

        let times = first.newPrompts.map(\.scheduledAt)
        #expect(times == times.sorted())
        #expect(Set(first.newPrompts.map(\.id)).count == first.newPrompts.count)
    }

    @Test("ties on scheduledAt break by survey ID")
    func tieBreak() {
        // One-minute windows force both surveys onto the same instant each day.
        let config = SamplingConfig(promptsPerDay: 1, windowStartMinutes: 600, windowEndMinutes: 601)
        let result = plan(now: F.date(2026, 9, 5, 0, 30), surveys: [F.survey(id: "z", sampling: config), F.survey(id: "a", sampling: config)])
        #expect(result.newPrompts.count == 14)
        for pair in stride(from: 0, to: 14, by: 2) {
            #expect(result.newPrompts[pair].scheduledAt == result.newPrompts[pair + 1].scheduledAt)
            #expect(result.newPrompts[pair].surveyId == "a")
            #expect(result.newPrompts[pair + 1].surveyId == "z")
        }
    }

    @Test("planning across a DST transition keeps every prompt in its local window")
    func acrossDST() {
        let before = F.date(2026, 3, 6, 8, 0)
        let result = plan(now: before, surveys: [F.survey(id: "s")])
        #expect(dayKeys(result.newPrompts).contains("2026-03-08"))
        for prompt in result.newPrompts {
            let minute = F.minuteOfDay(prompt.scheduledAt)
            #expect(minute >= 540 && minute < 1380, "\(prompt.scheduledAt)")
            #expect(prompt.day == DayKey.string(for: prompt.scheduledAt, calendar: calendar))
        }
    }
}
