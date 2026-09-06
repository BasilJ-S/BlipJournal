import Foundation
import Testing
@testable import OpenBlipCore

@Suite("DaySampler")
struct DaySamplerTests {
    typealias F = SamplingFixtures
    let sampler = DaySampler()
    let day = F.date(2026, 9, 5)

    func sample(
        _ config: SamplingConfig, seed: UInt64 = 1, day: Date? = nil, calendar: Calendar = F.toronto
    ) -> [Date] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return sampler.sample(day: day ?? self.day, config: config, calendar: calendar, using: &rng)
    }

    /// Asserts the invariants every valid sample must hold, in elapsed time.
    func check(
        _ times: [Date], config: SamplingConfig, day: Date, calendar: Calendar = F.toronto,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let window = DaySampler.window(of: day, config: config, calendar: calendar)!
        for time in times {
            #expect(time >= window.start && time < window.end, "\(time) outside window", sourceLocation: sourceLocation)
            #expect(calendar.component(.second, from: time) == 0, sourceLocation: sourceLocation)
            #expect(calendar.component(.nanosecond, from: time) == 0, sourceLocation: sourceLocation)
        }
        for (a, b) in zip(times, times.dropFirst()) {
            #expect(b.timeIntervalSince(a) >= TimeInterval(config.minGapMinutes * 60),
                    "gap violated between \(a) and \(b)", sourceLocation: sourceLocation)
        }
    }

    @Test("the same seed gives the same output; different seeds differ")
    func deterministic() {
        #expect(sample(.default, seed: 9) == sample(.default, seed: 9))
        #expect(sample(.default, seed: 9) != sample(.default, seed: 10))
    }

    @Test("default config: full count, in window, ascending, gapped, whole minutes, over 1000 seeds")
    func defaultConfigInvariants() {
        for seed in 0..<1000 {
            let times = sample(.default, seed: UInt64(seed))
            #expect(times.count == 3, "seed \(seed)")
            check(times, config: .default, day: day)
        }
    }

    @Test("times fall in every block over many seeds, so sampling is stratified")
    func stratified() {
        var blocksHit: Set<Int> = []
        for seed in 0..<200 {
            let times = sample(.default, seed: UInt64(seed))
            // Window 09:00–23:00 is 840 minutes; blocks are 280 minutes each.
            for time in times {
                blocksHit.insert((F.minuteOfDay(time) - 540) / 280)
            }
            #expect(times.map { (F.minuteOfDay($0) - 540) / 280 } == [0, 1, 2], "seed \(seed)")
        }
        #expect(blocksHit == [0, 1, 2])
    }

    @Test("a window too narrow for the gap yields fewer prompts, never a gap violation")
    func narrowWindow() {
        // 5 prompts, 100 minute window, gap 24: (5-1)*24 = 96 < 100 so it validates,
        // but the blocks are 20 minutes, so gaps push later prompts out of their blocks.
        let config = SamplingConfig(
            promptsPerDay: 5, windowStartMinutes: 600, windowEndMinutes: 700, minGapMinutes: 24
        )
        #expect(config.validationErrors.isEmpty)
        var counts: Set<Int> = []
        for seed in 0..<300 {
            let times = sample(config, seed: UInt64(seed))
            check(times, config: config, day: day)
            counts.insert(times.count)
        }
        #expect(counts.contains { $0 < 5 })
        #expect(counts.allSatisfy { $0 >= 1 && $0 <= 5 })
    }

    @Test("a squeezed block places the prompt at the raised bound when still inside the window")
    func squeezedBlockUsesBound() {
        // 3 prompts in 60 minutes (12:00 to 13:00) with gap 29: blocks are 20 minutes.
        // Block 2 is [20, 40): once the first prompt lands at minute 11 or later,
        // first + 29 reaches the block end and the second prompt must sit exactly there.
        // The third block is [40, 60): if second + 29 reaches 60 the third is dropped.
        let config = SamplingConfig(
            promptsPerDay: 3, windowStartMinutes: 720, windowEndMinutes: 780, minGapMinutes: 29
        )
        #expect(config.validationErrors.isEmpty)
        var sawSqueezedSecond = false
        var sawDroppedThird = false
        for seed in 0..<300 {
            let times = sample(config, seed: UInt64(seed))
            check(times, config: config, day: day)
            #expect(times.count >= 2, "seed \(seed)")
            let first = F.minuteOfDay(times[0]) - 720
            if first >= 11 {
                sawSqueezedSecond = true
                #expect(times[1] == times[0].addingTimeInterval(29 * 60), "seed \(seed)")
            }
            let second = F.minuteOfDay(times[1]) - 720
            if second + 29 >= 60 {
                sawDroppedThird = true
                #expect(times.count == 2, "seed \(seed)")
            } else {
                #expect(times.count == 3, "seed \(seed)")
                #expect(times[2] >= times[1].addingTimeInterval(29 * 60))
            }
        }
        #expect(sawSqueezedSecond)
        #expect(sawDroppedThird)
    }

    @Test("a zero gap never puts two prompts on the same minute")
    func zeroGapDistinctMinutes() {
        // Two prompts in a one-minute window: only one minute exists, so one is dropped.
        let tiny = SamplingConfig(promptsPerDay: 2, windowStartMinutes: 600, windowEndMinutes: 601, minGapMinutes: 0)
        #expect(tiny.validationErrors.isEmpty)
        #expect(sample(tiny) == [F.date(2026, 9, 5, 10, 0)])

        // Nine blocks of 93.3 minutes are not minute-aligned, so adjacent draws can
        // round onto the same minute; seed 9045 did before the post-rounding push.
        let nine = SamplingConfig(promptsPerDay: 9, minGapMinutes: 0)
        for seed in [UInt64(9045)] + (0..<3000).map(UInt64.init) {
            let times = sample(nine, seed: seed)
            check(times, config: nine, day: day)
            for (a, b) in zip(times, times.dropFirst()) {
                #expect(b.timeIntervalSince(a) >= 60, "seed \(seed): \(a) and \(b)")
            }
        }
    }

    @Test("a zero gap allows adjacent minutes and still stays in window")
    func zeroGap() {
        let config = SamplingConfig(promptsPerDay: 20, minGapMinutes: 0)
        for seed in 0..<100 {
            let times = sample(config, seed: UInt64(seed))
            #expect(times.count == 20)
            check(times, config: config, day: day)
            #expect(times == times.sorted())
        }
    }

    @Test("zero prompts per day yields nothing")
    func zeroCount() {
        var config = SamplingConfig.default
        config.promptsPerDay = 0
        #expect(config.validationErrors.isEmpty)
        #expect(sample(config).isEmpty)
    }

    @Test("a disabled config yields nothing")
    func disabled() {
        var config = SamplingConfig.default
        config.isEnabled = false
        #expect(sample(config).isEmpty)
    }

    @Test("an invalid config yields nothing and does not trap")
    func invalid() {
        var window = SamplingConfig.default
        window.windowEndMinutes = window.windowStartMinutes
        #expect(!window.validationErrors.isEmpty)
        #expect(sample(window).isEmpty)

        var gap = SamplingConfig.default
        gap.minGapMinutes = 1000
        #expect(gap.validationErrors == [.gapDoesNotFit])
        #expect(sample(gap).isEmpty)

        var count = SamplingConfig(windowStartMinutes: 0, windowEndMinutes: 1440, minGapMinutes: 1)
        count.promptsPerDay = -3
        #expect(sample(count).isEmpty)
    }

    @Test("an rng that is never consulted when nothing is sampled")
    func rngUntouchedWhenEmpty() {
        var config = SamplingConfig.default
        config.promptsPerDay = 0
        var rng = SeededRandomNumberGenerator(seed: 5)
        var reference = SeededRandomNumberGenerator(seed: 5)
        _ = sampler.sample(day: day, config: config, calendar: F.toronto, using: &rng)
        #expect(rng.next() == reference.next())
    }

    @Test("the window is built from wall-clock minutes", arguments: [
        F.date(2026, 9, 5), F.date(2026, 3, 8), F.date(2026, 11, 1),
    ])
    func windowEdgesAreWallClock(day: Date) {
        let window = DaySampler.window(of: day, config: .default, calendar: F.toronto)!
        #expect(F.minuteOfDay(window.start) == 540)
        #expect(F.minuteOfDay(window.end) == 1380)
        #expect(F.toronto.isDate(window.start, inSameDayAs: day))
        #expect(F.toronto.isDate(window.end, inSameDayAs: day))
    }

    @Test("DST transition days keep every time in the local window with the same count", arguments: [
        F.date(2026, 3, 8), F.date(2026, 11, 1),
    ])
    func dstDays(day: Date) {
        for seed in 0..<200 {
            let times = sample(.default, seed: UInt64(seed), day: day)
            #expect(times.count == 3, "seed \(seed)")
            check(times, config: .default, day: day)
            for time in times {
                let minute = F.minuteOfDay(time)
                #expect(minute >= 540 && minute < 1380, "seed \(seed): \(time)")
                #expect(F.toronto.isDate(time, inSameDayAs: day))
            }
        }
    }

    @Test("a full-day window 0...1440 works, including on DST days", arguments: [
        F.date(2026, 9, 5), F.date(2026, 3, 8), F.date(2026, 11, 1),
    ])
    func fullDayWindow(day: Date) {
        let config = SamplingConfig(promptsPerDay: 4, windowStartMinutes: 0, windowEndMinutes: 1440)
        #expect(config.validationErrors.isEmpty)
        let window = DaySampler.window(of: day, config: config, calendar: F.toronto)!
        #expect(window.start == F.toronto.startOfDay(for: day))
        #expect(window.end == F.toronto.date(byAdding: .day, value: 1, to: window.start))

        for seed in 0..<200 {
            let times = sample(config, seed: UInt64(seed), day: day)
            #expect(times.count == 4, "seed \(seed)")
            check(times, config: config, day: day)
            for time in times {
                #expect(F.toronto.isDate(time, inSameDayAs: day), "seed \(seed): \(time)")
            }
        }
    }

    @Test("a window edge inside the skipped DST hour moves forward to the first real instant")
    func edgeInsideSkippedHour() {
        let springForward = F.date(2026, 3, 8)
        let config = SamplingConfig(promptsPerDay: 1, windowStartMinutes: 150, windowEndMinutes: 600, minGapMinutes: 0)
        let window = DaySampler.window(of: springForward, config: config, calendar: F.toronto)!
        #expect(F.minuteOfDay(window.start) == 180, "02:30 does not exist; 03:00 EDT is the first real instant")
        #expect(F.minuteOfDay(window.end) == 600)
        for seed in 0..<50 {
            let times = sample(config, seed: UInt64(seed), day: springForward)
            #expect(times.count == 1)
            check(times, config: config, day: springForward)
        }
    }

    @Test("a window lying wholly inside the skipped DST hour yields nothing and does not trap")
    func windowInsideSkippedHour() {
        let springForward = F.date(2026, 3, 8)
        let config = SamplingConfig(promptsPerDay: 1, windowStartMinutes: 120, windowEndMinutes: 180, minGapMinutes: 0)
        #expect(config.validationErrors.isEmpty)
        #expect(DaySampler.window(of: springForward, config: config, calendar: F.toronto) == nil)
        #expect(sample(config, day: springForward).isEmpty)
        // The same window on an ordinary day is fine.
        #expect(sample(config).count == 1)
    }

    @Test("a 30-minute DST shift keeps window edges inside the day")
    func halfHourShift() {
        // Lord Howe Island springs forward 02:00 to 02:30 on 2026-10-04. Foundation
        // resolves 02:00 through 02:29 to the next day; the sampler must not follow it.
        var lordHowe = Calendar(identifier: .gregorian)
        lordHowe.timeZone = TimeZone(identifier: "Australia/Lord_Howe")!
        let day = F.date(2026, 10, 4, calendar: lordHowe)
        let nextDay = F.date(2026, 10, 5, calendar: lordHowe)

        // An edge inside the skipped half hour lands on the transition, 02:30.
        let insideGap = SamplingConfig(promptsPerDay: 1, windowStartMinutes: 120, windowEndMinutes: 600, minGapMinutes: 0)
        let window = DaySampler.window(of: day, config: insideGap, calendar: lordHowe)!
        #expect(window.start == F.date(2026, 10, 4, 2, 30, calendar: lordHowe))
        #expect(F.minuteOfDay(window.end, calendar: lordHowe) == 600)

        // A window whose end is inside the skipped half hour stays inside the day.
        let endInGap = SamplingConfig(promptsPerDay: 3, windowStartMinutes: 0, windowEndMinutes: 120, minGapMinutes: 30)
        let early = DaySampler.window(of: day, config: endInGap, calendar: lordHowe)!
        #expect(early.start == day)
        #expect(early.end == F.date(2026, 10, 4, 2, 30, calendar: lordHowe))
        for seed in 0..<100 {
            let times = sample(endInGap, seed: UInt64(seed), day: day, calendar: lordHowe)
            #expect(times.count == 3, "seed \(seed)")
            check(times, config: endInGap, day: day, calendar: lordHowe)
            for time in times {
                #expect(time < nextDay && lordHowe.isDate(time, inSameDayAs: day), "seed \(seed): \(time)")
            }
        }

        // A full-day window still ends at the next midnight.
        let fullDay = SamplingConfig(promptsPerDay: 2, windowStartMinutes: 0, windowEndMinutes: 1440)
        #expect(DaySampler.window(of: day, config: fullDay, calendar: lordHowe)?.end == nextDay)
    }

    @Test("the day argument can be any instant inside the day")
    func anyInstantInDay() {
        let evening = F.date(2026, 9, 5, 22, 45, 30)
        #expect(sample(.default, seed: 3, day: evening) == sample(.default, seed: 3, day: day))
    }

    @Test("a single prompt in a one-minute window lands on that minute")
    func oneMinuteWindow() {
        let config = SamplingConfig(promptsPerDay: 1, windowStartMinutes: 600, windowEndMinutes: 601)
        for seed in 0..<20 {
            #expect(sample(config, seed: UInt64(seed)) == [F.date(2026, 9, 5, 10, 0)])
        }
    }

    @Test("results honour the calendar passed in, not the process time zone")
    func honoursCalendar() {
        let utcDay = F.date(2026, 9, 5, calendar: F.utc)
        let times = sample(.default, seed: 4, day: utcDay, calendar: F.utc)
        #expect(times.count == 3)
        for time in times {
            let minute = F.minuteOfDay(time, calendar: F.utc)
            #expect(minute >= 540 && minute < 1380)
        }
    }
}
