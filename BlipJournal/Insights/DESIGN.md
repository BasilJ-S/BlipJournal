# Insights

SwiftUI charts over a loaded survey snapshot. `InsightsModel` owns selections and
range filtering; statistical calculations live in core `Analytics`.

- Survey picker includes archived surveys, active first. Scale/spectrum and choice
  pickers use active questions, preserving selections by ID on reload.
- Ranges: 7/30/90 calendar days, All, or Custom. Bounds use local calendar arithmetic,
  inclusive start and exclusive next-day end, capped to `load(now:)`. Custom dates
  cannot cross or be future dates. All charts share the same bounded entry IDs;
  response rate instead filters prompts by scheduled time.
- Timeline shows individual answers and a labelled trailing **7-entry** mean;
  prompted/manual symbols differ. Hour/weekday bars show means and counts.
- **Explore by option** names both questions and shows horizontal distributions on
  the selected question's full numeric domain, with labelled endpoints. Rounded boxes
  show the middle half, the heavy line the median, whiskers the full min/max range.
  Under five answers, separate lanes show individual marks, including repeated values.
  Five is a display threshold, not a claim of statistical reliability. Empty live
  options remain visible; archived options appear only with data.
- Tapping an option opens a comparison sheet: selected vs explicitly answered without
  selecting it. Missing/invalid choice answers stay out; explicit empty multi-choice
  enters the latter group. Multiple-choice entries can belong to several overview
  rows, but comparison groups are disjoint. Both groups may contain other options.
- Comparison groups disclose the exact contributing entries, newest first, linking
  to existing entry details. Sheets calculate from the live model; app write revisions
  reload that model so entry deletion updates distributions and drill-downs.
- Distribution summaries expose count, median, min/max and quartiles to VoiceOver.
  Visible text supports Dynamic Type; colour is not the sole encoding. Hour/weekday
  charts retain chart descriptors; the timeline retains its accessibility summary.
- Response rate excludes pending outcomes from its denominator.

Limitations: descriptive exploration only, no automatic highlights or causal claims.
Current option labels are used. Historical scale configuration changes are not
normalised or split; the current question domain is used. No cross-survey comparison
or chart export. `now` advances only on reload. Legacy mean-by-option model/core APIs
remain available but no longer draw the option chart.
