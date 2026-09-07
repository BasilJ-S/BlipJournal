# Analytics

## Purpose

Pure functions that turn an `ExportSnapshot` (built by Storage, shared with Export) and
a list of prompts into chart-ready series and summary numbers. The Insights screen does
no arithmetic of its own: it draws what these return. Nothing here formats a date, picks
a colour, allocates a formatter, or reads the clock; the only import is `Foundation`.

## Functions

```
Analytics.defaultScaleQuestion(in:)                first active scale question by (position, id)
Analytics.scaleSeries(questionId:snapshot:)        [MoodPoint], one per completed scale answer, by date
Analytics.rollingMean(_:window:)                   trailing mean, same length and order
Analytics.byHour(_:calendar:)                      24 BucketStats, ids "0"..."23"
Analytics.byWeekday(_:calendar:)                   7 BucketStats from calendar.firstWeekday
Analytics.byOption(scaleQuestionId:choiceQuestionId:snapshot:)
                                                   one BucketStat per option of the choice question
Analytics.compliance(prompts:)                     ComplianceStats: counts by status and a rate
```

`MoodPoint` is an answer placed in time: `id` is the answer ID, `date` is
`Answer.answeredAt`, `prompted` is `Entry.isPrompted`. `BucketStat` is a stable `id`, an
axis `label`, a `mean` that is nil exactly when `count` is zero, and the `count`.

## The completed-entry rule

An entry counts only when `entry.completedAt != nil`. Every function except `compliance`
drops partial entries first, so a half-finished autosave never moves a chart.
`compliance` looks at prompts, not entries, and counts every status.

A scale answer is `AnswerValue.scale`; any other value for the scale question is
ignored. There should be one answer per question per entry. If there are several, the
first by answer ID is taken before its shape is checked, so the result depends on the
data and not on the order Storage returned answers in.

## Bucket conventions

- **Fixed axes.** `byHour` always returns 24 buckets and `byWeekday` always 7, empty ones
  with `mean == nil` and `count == 0`, so an axis does not jump as data arrives. Hour
  ids and labels are plain digits. Weekday ids are the `Calendar` weekday number (`"1"`
  is Sunday in the Gregorian calendar), labels come from `shortWeekdaySymbols`, and the
  order starts at `calendar.firstWeekday`. Hour and weekday are taken in the caller's
  calendar, so a 23:30 answer belongs to hour 23 of its local day whatever UTC says.
- **Options are the exception.** `byOption` returns one bucket per option of the choice
  question, ordered by `(position, id)`, labelled with the option's current label. Live
  options are always present; archived ones only when their count is greater than zero.
  An entry that selected several options counts once toward each. An entry with no scale
  value contributes nothing, so `count` is always the number of values behind `mean`.
  Option IDs the question does not define, and an unknown choice question, yield nothing.
- **Means** are plain arithmetic means as `Double`, unrounded. The chart formats.
- **Rolling mean** is trailing: point `i` averages points `max(0, i - window + 1)...i`,
  so the first `window - 1` points average what exists so far. `window <= 1` returns the
  input unchanged; only `value` changes. Each window is summed afresh rather than kept as
  a running total, so a long series cannot accumulate floating-point drift.
- **Rolling-mean points keep their input IDs**, so a chart must not put raw and
  smoothed points in one `ForEach`; draw them as two series.
- **Compliance** counts whatever prompts it is handed. The rate is
  `answered / (answered + missed + dismissed)`, nil when that is zero; pending prompts
  have no outcome yet and stay out of it. The snapshot cannot feed this function: it
  carries only the prompts behind existing entries, never missed or pending ones. The
  caller loads prompts from `Store` and restricts them to one survey (and a date range,
  if it wants one) before calling.

## Decisions

- **Entry-based functions read the snapshot, not the store**, so Insights and an export
  of the same survey never disagree about which entries exist, and every function is
  testable by hand. `compliance` is the one exception, for the reason above.
- **Ties break by identifier**: series order `(date, answer id)`, option order
  `(position, id)`, duplicate answers by answer id. Two runs draw the same chart.
- **No `Date()`.** Every instant comes from the data or the caller.

## Known limitations

- **Spectrum questions are out of scope here, deliberately.** Every function above is
  keyed to `AnswerValue.scale` and `ScaleConfig`'s caller-chosen integer range; a
  spectrum answer is a `Double` in a fixed `0...1`, not on that range, and forcing it
  through `scaleSeries`/`byOption` would average two incompatible units under one mood
  chart. Spectrum questions simply do not appear in any series or bucket here; nothing
  reads `AnswerValue.spectrum`. Charting spectrum answers, if ever wanted, needs its own
  function, not a widened `scaleSeries`.
- No correlation, no significance testing, no confidence intervals: means and counts
  only. A bucket of one point looks as solid as one of a hundred; `count` is there for
  the chart to show.
- No per-survey comparison. A snapshot is one survey.
- Nothing validates a scale value against its `ScaleConfig`; an out-of-range value
  stored upstream is averaged like any other.
- `byOption` uses the option's current label, not the wording on screen at answer time.
  Export owns the rename-history replay.
- The rolling mean is over points, not time: seven points is seven answers, however
  many days they span.
