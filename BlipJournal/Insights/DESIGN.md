# Insights

Charts over the `Analytics` functions in `BlipJournalCore`. `InsightsView` does no
arithmetic itself: every number on screen is either a value `InsightsModel` read
straight from `Analytics`, or a small aggregate (a mean, a count, a percentage)
`InsightsModel` computes for a label or accessibility summary, kept out of the view.

## Sections

- **Survey picker.** Shown when more than one survey exists (a menu); a single
  survey's name and archived status are shown as plain text instead. Active surveys
  sort before archived ones, Store order preserved within each group.
- **Range picker.** Five choices: 7 days, 30 days, 90 days, All, Custom. A segmented
  control, falling back to a menu via `ViewThatFits` when it does not fit at the
  current text size. Custom reveals "Start date" and "End date" pickers, both
  constrained to non-future dates.
- **Mood question picker.** Shown when the survey has more than one active scale or
  spectrum question. Its label becomes every mood-derived section's heading ("{label} — Over
  time", "— By hour", "— By weekday"), so a custom survey's own wording appears
  verbatim; nothing here assumes "Mood" or that a scale measures feelings.
- **Over time.** `MoodOverTimeChart`: prompted points filled, manual points hollow
  (a legend from `.chartSymbolScale`), a secondary rolling-mean line. Y axis is the
  question's own domain, labelled at the two ends; X axis by day. Spectrum answers use
  `0...100` and the first and last zone labels.
- **By hour / By weekday.** `BucketBarChart` (vertical): one bar per non-empty bucket,
  its count annotated at a fixed, non-scaling text size. Bars run from zero to the
  actual mean, including negative means. Their numeric domain is
  `min(0, domain.lowerBound)...max(0, domain.upperBound)`; this is deliberately separate
  from the timeline's mood domain. Endpoint annotations get reserved chart
  space and category labels remain outside the plot area.
- **By option.** A picker over the survey's active choice questions (when more than
  one), then `BucketBarChart` (horizontal) of mean per option, in `Analytics.byOption`'s
  own order. It uses the same zero-baseline rule and positions count annotations on
  the correct side for positive and negative bars.
- **Response rate.** `ComplianceTile`: the rate as a percentage, or "No prompts yet";
  answered/missed/dismissed/pending counts in a row.

Every section title doubles as its `ContentUnavailableView` title when empty, with a
one-line reason: "No mood question in this survey", "No choice question in this
survey", or "No entries in this range".

## InsightsModel

`@MainActor @Observable`, holding a `Store` and a `Calendar`. `load(now:)` is the only
method that touches the store: it reloads `surveys` (`includeArchived: true`, active
sorted before archived, Store order kept within each group), resolves
`selectedSurveyId` (first active, else first archived, else nil; preserved across
reload when it still names a survey, including one just archived; reset to the default
when it no longer does, including after a hard delete), then loads that survey's
`exportSnapshot` and every prompt filtered to it. `moodQuestion`/`choiceQuestion` are
resolved the same way: kept if they still name an active question of the (possibly new)
survey, refreshed to that question's current version; otherwise reset to
`Analytics.defaultMoodQuestion` and the first active choice question. Every other
public property — `series`, `rolling`, `byHour`, `byWeekday`, `byOption`, `compliance`,
and the accessibility summaries — is a computed property over the loaded snapshot,
prompts, selected questions and range, so changing a selection updates every dependent
chart with no separate recompute step.

`load(now:)` captures `now`; it is the instant every range computation uses until the
next `load(now:)`, so a screen left open does not silently drift into "now" instant by
instant.

### Range rule

A range is `(start, exclusiveEnd)` in local calendar days, computed with
`Calendar.date(byAdding:)` rather than fixed intervals so it survives DST. A preset's
`start` is `today` minus `N - 1` days; `exclusiveEnd` is always the day after `today`.
Custom's `start` is `customStart`'s day; `exclusiveEnd` is the day after `customEnd`'s
day. A value is included when `start <= date < exclusiveEnd && date <= now` — the
`<= now` clause is what actually caps every preset (including All) to "so far",
since `exclusiveEnd` for a non-past custom end date is always later than `now`; it
also excludes every future-scheduled prompt from `compliance`, for every range,
without a separate check. `byOption` applies the same bounds by restricting the
snapshot's entries to the ones `series` already kept, so every chart, including
by-option, agrees on one set of entries.

`customStart`/`customEnd` are plain settable properties that validate themselves: a
future date or one that would cross the other bound reverts the assignment. Entering
Custom for the first time in a session seeds the two dates from whichever preset was
showing (or the last 30 days, leaving All); once set, they survive switching to a
preset and back.

### Known limitations

- No correlation, no significance testing, no comparison across surveys — `Analytics`
  does not offer them, so neither does this screen.
- No export of charts.
- Bucket chart accessibility numeric axes use the same zero-inclusive domain as the
  visual bars; the selected question label, actual means, and bucket categories remain
  available through the chart descriptor and accessibility summary.
- `MoodOverTimeChart` has no `accessibilityChartDescriptor`: combining raw and
  rolling-mean series into one cheap descriptor was not worth it next to its
  `accessibilityLabel`. The bar charts (`byHour`, `byWeekday`, `byOption`) each get one.
- `InsightsModel.now` is set by `load(now:)`; nothing here reads the clock between
  reloads, so a session left open on a preset range will not silently roll into a new
  day until the next reload (survey switch, or the view reappearing).
