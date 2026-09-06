import Foundation

/// Turns one survey's ``SamplingConfig`` into random prompt times for one day.
///
/// Stratified sampling: the window is split into `promptsPerDay` equal blocks and one
/// time is drawn uniformly from each, so prompts are spread across the day but never
/// land at predictable moments. The minimum gap is enforced by raising the lower bound
/// of each draw; a block that has been squeezed shut yields a prompt at the bound if
/// that is still inside the window, and nothing otherwise.
///
/// Pure: no clock, no persistence. Time comes in as `day` and randomness as `rng`.
public struct DaySampler: Sendable {
    public init() {}

    /// Prompt times for the day containing `day`, ascending, rounded down to the minute.
    ///
    /// Returns `[]` when the config is invalid, disabled, or asks for zero prompts.
    public func sample<G: RandomNumberGenerator>(
        day: Date, config: SamplingConfig, calendar: Calendar, using rng: inout G
    ) -> [Date] {
        guard config.validationErrors.isEmpty,
              config.isEnabled,
              config.promptsPerDay > 0,
              let window = Self.window(of: day, config: config, calendar: calendar)
        else { return [] }

        let count = config.promptsPerDay
        let windowStart = window.start
        let windowEnd = window.end
        let minGap = TimeInterval(config.minGapMinutes * 60)
        // Results are whole minutes, so two prompts are only distinct when a full
        // minute apart. A gap of zero still means "no two prompts at the same minute".
        let distinctGap = max(minGap, 60)
        let blockLength = windowEnd.timeIntervalSince(windowStart) / Double(count)

        var results: [Date] = []
        results.reserveCapacity(count)

        for index in 0..<count {
            let blockStart = windowStart.addingTimeInterval(blockLength * Double(index))
            let blockEnd = index == count - 1
                ? windowEnd
                : windowStart.addingTimeInterval(blockLength * Double(index + 1))

            var lower = blockStart
            if let previous = results.last {
                lower = max(lower, previous.addingTimeInterval(minGap))
            }

            let drawn: Date
            if lower >= blockEnd {
                guard lower < windowEnd else { continue }
                drawn = lower
            } else {
                let offset = Double.random(in: 0..<blockEnd.timeIntervalSince(lower), using: &rng)
                drawn = lower.addingTimeInterval(offset)
            }

            var time = Self.floorToMinute(drawn, calendar: calendar)
            if let previous = results.last, time.timeIntervalSince(previous) < distinctGap {
                time = previous.addingTimeInterval(distinctGap)
            }
            // The push above can reach the window end, and so can a draw that lands a
            // floating-point hair below the last block's end and rounds onto it.
            guard time < windowEnd else { continue }
            results.append(time)
        }

        return results
    }

    /// The instants at which the window opens and closes on the day containing `day`,
    /// or nil if the window collapses to nothing on that day.
    ///
    /// Built from wall-clock hour and minute, not by adding minutes to midnight:
    /// `Calendar.date(byAdding: .minute)` adds elapsed time, so on a day that springs
    /// forward it would turn 09:00 into 10:00. A closing minute of 1440 is the start of
    /// the following day. An edge that falls inside a skipped DST period moves forward
    /// to the first instant that exists, so a window lying wholly inside the skipped
    /// period has no length and yields nil.
    static func window(of day: Date, config: SamplingConfig, calendar: Calendar) -> DateInterval? {
        let startOfDay = calendar.startOfDay(for: day)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay).map(calendar.startOfDay(for:)),
              let start = wallClock(minutes: config.windowStartMinutes, of: startOfDay, before: nextDay, calendar: calendar),
              let end = wallClock(minutes: config.windowEndMinutes, of: startOfDay, before: nextDay, calendar: calendar),
              start < end
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// The instant `minutes` after midnight on the day starting at `startOfDay`.
    ///
    /// `Calendar.date(bySettingHour:)` usually resolves a skipped wall-clock time to the
    /// end of the skipped period, but for a shift that is not a whole hour (Lord Howe
    /// Island moves by 30 minutes) it can roll into the next day instead. An edge that
    /// leaves the day is replaced by the day's DST transition instant, which is the
    /// first instant after the skipped period.
    private static func wallClock(minutes: Int, of startOfDay: Date, before nextDay: Date, calendar: Calendar) -> Date? {
        if minutes >= 1440 {
            return nextDay
        }
        guard let edge = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: startOfDay)
        else { return nil }
        if edge >= startOfDay && edge < nextDay {
            return edge
        }
        if let transition = calendar.timeZone.nextDaylightSavingTimeTransition(after: startOfDay),
           transition < nextDay {
            return transition
        }
        return nextDay
    }

    private static func floorToMinute(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }
}
