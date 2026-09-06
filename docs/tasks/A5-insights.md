# Task A5: Insights

Implementation handoff for `BlipJournal/Insights/`. Read `AGENTS.md`, the "Insights" bullet
in `README.md`, the A5 section of `docs/PLAN.md`,
`BlipJournalCore/Sources/BlipJournalCore/Analytics/DESIGN.md`, and `BlipJournal/App/DESIGN.md`.
Requires A1 on `main`. Do not modify `BlipJournalCore/` or files outside `Insights/` and
`BlipJournalTests/Insights/`.

## Goal

Charts over the Analytics functions. The view does no arithmetic: every number on screen
comes from `Analytics` in the core package. Replace the A1 stub `InsightsView.swift`
(`init()` reading `AppModel` from the environment).

## Branch and delivery

Branch from `main`: `a5-insights`. Draft PR when done. `xcodebuild` build and test against
the iPhone 17 Pro simulator, zero app-target warnings.

## Files

```
Insights/InsightsView.swift          replaces stub; survey picker, sections
Insights/InsightsModel.swift         @MainActor @Observable; loads snapshot and prompts; picks questions
Insights/MoodOverTimeChart.swift
Insights/HourAndWeekdayCharts.swift
Insights/ByOptionChart.swift
Insights/ComplianceTile.swift
Insights/DESIGN.md
BlipJournalTests/Insights/InsightsModelTests.swift
```

## InsightsModel

```swift
@MainActor @Observable final class InsightsModel {
    init(store: Store, calendar: Calendar = .autoupdatingCurrent)
    var surveys: [Survey]                       // include archived
    var selectedSurveyId: String?               // first active, else first archived, else nil
    var snapshot: ExportSnapshot?
    var prompts: [Prompt]                       // of the selected survey, all statuses
    var scaleQuestion: Question?                // Analytics.defaultScaleQuestion, user-changeable among scale questions
    var choiceQuestion: Question?               // first active choice question by position, user-changeable
    var range: Range                            // 7 days, 30 days, 90 days, all, custom; default 30 days
    var customStart: Date                       // local calendar date
    var customEnd: Date                         // inclusive local calendar date
    func load(now: Date = Date()) throws         // exportSnapshot + prompts(status: nil) filtered by surveyId
    var series: [MoodPoint]                     // scaleSeries filtered to range
    var rolling: [MoodPoint]                    // rollingMean(series, window: 7)
    var byHour: [BucketStat]  var byWeekday: [BucketStat]  var byOption: [BucketStat]
    var compliance: ComplianceStats             // over prompts in range by scheduledAt
}
```

Range filtering uses an injected calendar and `now` passed to `load(now:)`. Presets
are "7 days", "30 days", "90 days", "All", and "Custom"; default to 30 days. A preset
includes today so far and the preceding N-1 local calendar days. Custom exposes start
and end date pickers, both inclusive in the UI: filter from start-of-day on the start
date to (but not including) start-of-day after the end date, capped at `now`. Use calendar
day arithmetic, not fixed 24-hour intervals. Disallow future dates and start after end;
initialise Custom to the current preset's dates, or the last 30 days when leaving All.
Retain the person's custom dates when switching away and back during the session.

Apply the same bounds to all chart inputs, including the entries supplied to by-option
analytics, and to response-rate prompts by `scheduledAt`. Scale points use `MoodPoint.date`;
rolling mean is calculated from the filtered series. All includes historical data up to
`now`; exclude future scheduled prompts from response-rate counts for every range. Date
filtering belongs in the model and is tested; views only select and display the range.
Reload on appear and whenever the selected survey changes. Load surveys with
`includeArchived: true`. Default to the first active survey; if none exists, the first
archived survey; if there are no surveys, use nil and an empty state. Preserve a valid
selection on reload, including when the selected survey becomes archived. If it is
permanently deleted, select the default again and clear its stale chart state.

## Screens

`InsightsView`: a survey picker at the top when more than one survey exists; a
range picker; then sections. Use a menu picker if the five choices do not fit at the
current text size. Custom reveals labelled "Start date" and "End date" pickers. Include archived surveys in the picker with
an "Archived" suffix; archiving must not hide their historical insights. Order active
surveys before archived surveys, preserving Store order within each group. Show the
archived status beside the survey name even when only one survey exists and the picker
is hidden. Each section has a title and, when its data is
empty, a `ContentUnavailableView` with a one-line reason ("No scale question in this
survey", "No entries in this range").

Provide a scale-question picker when the survey has more than one scale question.
Default to `Analytics.defaultScaleQuestion`; changing the selection updates every
scale-derived chart and its labels. Use the selected question's current label as the
visible chart heading, with "Over time", "By hour", "By weekday", and "By option" as
section context. Do not hard-code "Mood" or assume a scale measures feelings. Show the
question label even when only one scale question exists and the picker is hidden.

- **Over time**: `Chart` with `PointMark` per point (prompted filled, manual hollow
  with a legend) and a `LineMark` for the rolling mean. Y axis is the scale's
  `min`...`max` with the end labels as axis annotations. X axis by day.
- **By hour** and **By weekday**: two `BarMark` charts of `mean`, bars with `count == 0`
  omitted rather than drawn at zero, `count` in the bar annotation at regular text size.
- **By option**: a picker over the survey's active choice questions, then a horizontal
  `BarMark` chart of `mean` per option label, sorted as returned, with count.
- **Response rate**: a tile with `rate` as a percentage (or "No prompts yet"), and
  answered / missed / dismissed / pending counts in a row.

Colours: semantic accent for prompted, secondary for manual, one hue only. Every chart
has `accessibilityLabel` summarising it in words (for example, "How focused are you? Average 4.6 over 31 entries")
and `accessibilityChartDescriptor` where cheap. Charts must render at the largest
accessibility text size without axis labels overlapping: reduce tick counts by
`Dynamic Type` size class rather than shrinking text.

## Tests

`InsightsModelTests` on `Store.inMemory()` seeded with the template and a dozen sample
entries written through `saveEntry` (copy the DEBUG sample generator pattern from
`JournalView` if useful, but keep it in the test target):

- `load` picks the template's scale question and its first multi-choice question.
- Selecting another scale question updates the series, rolling mean, hour/weekday/option
  aggregates, scale bounds, visible question label, and accessibility summaries. Custom
  survey questions are never described as "Mood" unless that is their actual label.
- The 7-day preset includes today and the previous six local dates; All includes older
  points. Test exact start boundaries, `now`, and exclusion of future values.
- Custom includes both selected dates and excludes the following day; test a single-day
  range and DST transitions with the injected calendar. Invalid or future dates cannot
  be applied, and custom dates survive switching presets.
- Every chart, including by-option, and response-rate counts use the selected bounds;
  future scheduled prompts are excluded from response rate even for All.
- Compliance counts only prompts of the selected survey and inside the range.
- Switching `selectedSurveyId` reloads and clears stale selections.
- Archived surveys remain selectable and their historical data loads. Initial selection
  prefers an active survey, falls back to archived when necessary, and is nil when empty.
- Reload preserves the selected survey after archive; permanent deletion clears stale
  data and chooses the next default.
- An empty survey yields empty series and `compliance.rate == nil` without throwing.

## Acceptance

- Build and tests pass, zero app-target warnings.
- With zero, one, and a hundred entries (DEBUG "Add sample entry" repeatedly) every
  section renders without layout breakage; axis labels readable at default size on an
  iPhone SE-class width (use the iPhone 17 Pro at 320-point width via Xcode's
  Previews or a narrow simulator).
- `Insights/DESIGN.md`: the section list, the model's contract, the range rule, archived-survey visibility and selection fallback, and known
  limitations (no correlations, no comparisons across surveys, no export of charts).

## Out of scope

New analytics functions (add a follow-up task instead), export, editing.
