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
    var surveys: [Survey]                       // active
    var selectedSurveyId: String?               // defaults to first
    var snapshot: ExportSnapshot?
    var prompts: [Prompt]                       // of the selected survey, all statuses
    var scaleQuestion: Question?                // Analytics.defaultScaleQuestion, user-changeable among scale questions
    var choiceQuestion: Question?               // first active choice question by position, user-changeable
    var range: Range                            // enum: week, month, quarter, all; default month
    func load() throws                          // exportSnapshot + prompts(status: nil) filtered by surveyId
    var series: [MoodPoint]                     // scaleSeries filtered to range
    var rolling: [MoodPoint]                    // rollingMean(series, window: 7)
    var byHour: [BucketStat]  var byWeekday: [BucketStat]  var byOption: [BucketStat]
    var compliance: ComplianceStats             // over prompts in range by scheduledAt
}
```

Range filtering is done in the model on `MoodPoint.date` and `Prompt.scheduledAt`
against `now` passed to `load(now:)`; it is the one piece of date arithmetic here and it
is tested. Reload on appear and whenever the selected survey changes.

## Screens

`InsightsView`: a survey picker at the top when more than one active survey exists; a
segmented range control; then sections. Each section has a title and, when its data is
empty, a `ContentUnavailableView` with a one-line reason ("No scale question in this
survey", "No entries in this range").

- **Mood over time**: `Chart` with `PointMark` per point (prompted filled, manual hollow
  with a legend) and a `LineMark` for the rolling mean. Y axis is the scale's
  `min`...`max` with the end labels as axis annotations. X axis by day.
- **By hour** and **By weekday**: two `BarMark` charts of `mean`, bars with `count == 0`
  omitted rather than drawn at zero, `count` in the bar annotation at regular text size.
- **By option**: a picker over the survey's active choice questions, then a horizontal
  `BarMark` chart of `mean` per option label, sorted as returned, with count.
- **Response rate**: a tile with `rate` as a percentage (or "No prompts yet"), and
  answered / missed / dismissed / pending counts in a row.

Colours: semantic accent for prompted, secondary for manual, one hue only. Every chart
has `accessibilityLabel` summarising it in words ("Average mood 4.6 over 31 entries")
and `accessibilityChartDescriptor` where cheap. Charts must render at the largest
accessibility text size without axis labels overlapping: reduce tick counts by
`Dynamic Type` size class rather than shrinking text.

## Tests

`InsightsModelTests` on `Store.inMemory()` seeded with the template and a dozen sample
entries written through `saveEntry` (copy the DEBUG sample generator pattern from
`JournalView` if useful, but keep it in the test target):

- `load` picks the template's scale question and its first multi-choice question.
- Range `week` excludes a point dated 8 days before `now`; `all` includes it.
- Compliance counts only prompts of the selected survey and inside the range.
- Switching `selectedSurveyId` reloads and clears stale selections.
- An empty survey yields empty series and `compliance.rate == nil` without throwing.

## Acceptance

- Build and tests pass, zero app-target warnings.
- With zero, one, and a hundred entries (DEBUG "Add sample entry" repeatedly) every
  section renders without layout breakage; axis labels readable at default size on an
  iPhone SE-class width (use the iPhone 17 Pro at 320-point width via Xcode's
  Previews or a narrow simulator).
- `Insights/DESIGN.md`: the section list, the model's contract, the range rule, and known
  limitations (no correlations, no comparisons across surveys, no export of charts).

## Out of scope

New analytics functions (add a follow-up task instead), export, editing.
