# Task C5: Analytics

**Status: done, merged in #5.** Kept as the record of what was asked. Where it and the code disagree, the code and the component's `DESIGN.md` are authoritative; the PR description lists the agreed deviations.

Implementation handoff for `BlipJournalCore/Sources/BlipJournalCore/Analytics/`. Read
`AGENTS.md`, the "Insights" bullet under "UI subsystem" in `README.md`, the C5 and A5
sections of `docs/PLAN.md`, and `Export/ExportSnapshot.swift`, which already exists on
`main` and is the input type for everything here. Do not touch anything under
`BlipJournal/`, `Storage/` or `Export/`.

## Goal

Pure functions that turn an `ExportSnapshot` and a list of prompts into chart-ready
series and summary numbers. The Insights screen (A5) does no arithmetic of its own; it
only draws what these return. No dates are formatted here, no colours chosen, no UI.

## Branch and delivery

- Branch from `main`: `c5-analytics`. Open a draft PR when done. See "Change control" in
  `AGENTS.md`.
- Add `"Analytics/DESIGN.md"` to the `exclude:` list in `Package.swift`.
- Do not modify `Export/ExportSnapshot.swift`.

## Files to create

```
Analytics/AnalyticsTypes.swift    MoodPoint, BucketStat, ComplianceStats
Analytics/Analytics.swift         the functions below
Analytics/DESIGN.md
Tests/BlipJournalCoreTests/Analytics/AnalyticsTests.swift
```

## Types

```swift
public struct MoodPoint: Sendable, Equatable, Identifiable {
    public var id: String          // the answer ID
    public var entryId: String
    public var date: Date          // Answer.answeredAt
    public var value: Double
    public var prompted: Bool      // Entry.isPrompted
}

public struct BucketStat: Sendable, Equatable, Identifiable {
    public var id: String          // stable key: "0"..."23" for hours, weekday number, option ID
    public var label: String       // what the chart shows on the axis
    public var mean: Double?       // nil when count == 0
    public var count: Int
}

public struct ComplianceStats: Sendable, Equatable {
    public var answered: Int
    public var missed: Int
    public var dismissed: Int
    public var pending: Int
    /// answered / (answered + missed + dismissed), nil when that denominator is 0.
    public var rate: Double?
}

public enum Analytics {
    /// The first active scale question by (position, id), or nil. What Insights charts by default.
    public static func defaultScaleQuestion(in survey: Survey) -> Question?

    /// One point per completed entry that answered `questionId` with a scale value,
    /// ascending by date. Partial entries are excluded.
    public static func scaleSeries(questionId: String, snapshot: ExportSnapshot) -> [MoodPoint]

    /// Trailing mean over the previous `window` points including the current one.
    /// The first `window - 1` points average what is available so far. Same length and
    /// order as the input; `prompted` and IDs are carried through unchanged.
    public static func rollingMean(_ points: [MoodPoint], window: Int) -> [MoodPoint]

    /// Exactly 24 buckets, id "0"..."23", label the hour as "0"..."23", ordered by hour,
    /// using the hour of `date` in `calendar`.
    public static func byHour(_ points: [MoodPoint], calendar: Calendar) -> [BucketStat]

    /// Exactly 7 buckets ordered from `calendar.firstWeekday`, id the weekday number as
    /// a string, label from `calendar.shortWeekdaySymbols`.
    public static func byWeekday(_ points: [MoodPoint], calendar: Calendar) -> [BucketStat]

    /// One bucket per option of `choiceQuestionId`, ordered by (position, id), archived
    /// options included only when their count is greater than zero. The mean is over the
    /// scale value of `scaleQuestionId` in every completed entry whose answer to the
    /// choice question selected that option. An entry that selected several options
    /// counts toward each of them.
    public static func byOption(scaleQuestionId: String, choiceQuestionId: String,
                                snapshot: ExportSnapshot) -> [BucketStat]

    /// Counts by status over the given prompts.
    public static func compliance(prompts: [Prompt]) -> ComplianceStats
}
```

## Rules

- "Completed entry" means `entry.completedAt != nil`. Everything except `compliance`
  ignores partial entries.
- A scale answer is `AnswerValue.scale`. Any other value for the scale question is
  ignored. There is at most one answer per question per entry; if there are more, take
  the first by answer ID for determinism.
- Means are plain arithmetic means as `Double`. No rounding here; the chart formats.
- `rollingMean` with `window <= 1` returns the input unchanged. With an empty input
  returns empty.
- Bucket functions always return the full bucket set (24 or 7) so charts have a stable
  axis, with `mean == nil` and `count == 0` where empty. `byOption` is the exception:
  it returns the option list, and drops archived options with no data.
- Nothing here allocates a `DateFormatter`. Labels for hours are plain digits, weekday
  labels come from the calendar's symbols.
- No `Date()` call anywhere in `Analytics/`.

## Tests

Swift Testing. Build snapshots by hand from the C1 types with a fixed
`Calendar` (`TimeZone(identifier: "America/Toronto")`, `firstWeekday = 2`). Cover:

- `defaultScaleQuestion` picks the lowest-position active scale question and skips
  archived ones; nil when none.
- `scaleSeries` excludes partial entries, ignores non-scale values, orders ascending,
  and sets `prompted` correctly for prompted and manual entries.
- `rollingMean` against hand-computed values for window 3 over five points, the
  window-of-one identity, empty input, and that IDs and `prompted` pass through.
- `byHour` returns 24 buckets in order; a point at 23:30 local lands in "23" even when
  its UTC hour is the next day; empty buckets have `mean == nil`.
- `byWeekday` returns 7 buckets starting from `firstWeekday`; labels match
  `shortWeekdaySymbols` rotated to match; a Sunday point lands in the right bucket.
- `byOption`: an entry selecting two options counts toward both; unselected options
  have count 0 and `mean == nil`; an archived option with data is present, without data
  is absent; order follows position.
- `compliance` over a mixed list, and `rate == nil` when there are only pending prompts.
- Every function returns empty or zeroed output for an empty snapshot without crashing.

## Acceptance

- `swift build` and `swift test` pass with zero warnings.
- `Analytics/` imports only `Foundation`.
- `Analytics/DESIGN.md`: purpose, the list of functions in one block, the completed-entry
  rule, the bucket conventions, and known limitations (no correlation, no significance,
  no per-survey comparison).

## Out of scope

Charts, colours, date formatting, any UI, statistics beyond means and counts. If A5
turns out to need a function that is not here, it gets added in a follow-up task, not
by the Insights view doing arithmetic.
