# Analytics

Pure Foundation functions over `ExportSnapshot` and prompts. No store access, clock,
formatting or randomness. The caller supplies calendar and date-filtered input.

## Series and summaries

- `defaultMoodQuestion`: first active scale/spectrum question by (position, ID).
- `moodSeries`: completed entries only, one answer per question (lowest answer ID wins
  before shape validation), ordered by (answer date, ID). Scale values remain numeric;
  spectrum values convert from 0…1 to 0…100. `MoodPoint` retains entry ID and provenance.
- `moodAxis`: current scale domain/endpoints, or 0…100 and spectrum endpoint labels.
- `rollingMean`: trailing N answers, including the current one; leading windows use
  available answers. N ≤ 1 is identity. Each sum is computed afresh to avoid drift;
  point IDs/provenance remain unchanged, so draw raw and smoothed series separately.
- `byHour`/`byWeekday`: fixed 24/7 buckets using the caller's calendar, weekday order
  starting at `firstWeekday`. `BucketStat.mean` is nil exactly when count is zero.
- Legacy `byOption`: arithmetic mean per defined option, ordered by (position, ID).
  Live options always appear; archived options appear only with data. Multi-choice
  contributes once per selected option. Missing mood values contribute nothing.
- `compliance`: answered / (answered + missed + dismissed); nil with no outcomes.
  Pending prompts are counted separately. Caller must load all survey prompts because
  snapshots only contain prompts attached to entries.

## Distributions and comparison

`optionDistributions` retains `MoodPoint`s per option for entry drill-down, with the
same option ordering/archived visibility rules. `optionComparison` partitions eligible
entries into selected/not-selected groups for one defined option. Both share series
completion/duplicate-answer rules, deduplicate selected IDs, and exclude missing,
non-choice or unknown-option answers. Explicit empty multi-choice counts as answered
and belongs in not-selected. Both comparison groups may contain other choices.
Non-finite mood values are excluded. Callers supply a range-filtered snapshot.

`AnswerDistribution` sorts finite points by (value, answer ID), exposes count, min/max,
and quartiles interpolated at `(count - 1) * p`. Empty quantiles are nil; singleton
quantiles equal that answer. `showsBox` starts at five answers; smaller samples draw
individually. This is a display convention, not significance. Whiskers represent the
full range, not a 1.5-IQR outlier rule. Entry IDs link plots to contributing entries.

## Limitations

Descriptive only: no correlation, significance tests, confidence intervals or
cross-survey comparisons. Labels and axis configurations use current definitions;
historical scale changes are not normalised or split. Legacy means do not validate
stored values against their configured domain. Rolling windows count answers, not days.
