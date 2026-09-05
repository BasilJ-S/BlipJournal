# Task C4: CSV export

Implementation handoff for `OpenBlipCore/Sources/OpenBlipCore/Export/`. Read `AGENTS.md`,
the "Export formats" section of `README.md`, the C4 section of `docs/PLAN.md`,
`Model/DESIGN.md` ("Recoverability"), and `Export/ExportSnapshot.swift`, which already
exists on `main` and is the input type for everything here. Do not touch anything under
`OpenBlip/` or `Storage/`.

## Goal

Pure functions that turn an `ExportSnapshot` into wide and long CSV text. No file I/O, no
database, no UI. The app writes the string to a file and hands it to the share sheet.

JSON backup is **not** in this task; it lives in Storage (C2), because it is a dump of
table rows.

## Branch and delivery

- Branch from `main`: `c4-export`. Open a draft PR when done. See "Change control" in
  `AGENTS.md`.
- Add `"Export/DESIGN.md"` to the `exclude:` list in `Package.swift`.
- Do not modify `Export/ExportSnapshot.swift`. If it lacks something you need, say so
  under "Deviations from the task" in the PR and work around it; changing the seam is a
  cross-task decision.

## Files to create

```
Export/CSV.swift              Field escaping and row joining
Export/CSVExporter.swift      wide(_:calendar:) and long(_:calendar:)
Export/DESIGN.md
Tests/OpenBlipCoreTests/Export/   CSVTests, CSVExporterWideTests, CSVExporterLongTests
```

## Types

```swift
enum CSV {
    /// RFC 4180: a field is quoted when it contains a comma, a double quote, CR or LF,
    /// or leading or trailing whitespace; quotes inside are doubled. Empty stays empty.
    static func escape(_ field: String) -> String
    /// Fields joined by commas, terminated by CRLF.
    static func row(_ fields: [String]) -> String
}

public enum CSVExporter {
    public static func wide(_ snapshot: ExportSnapshot, calendar: Calendar) -> String
    public static func long(_ snapshot: ExportSnapshot, calendar: Calendar) -> String
}
```

`CSV` is internal. Tests reach it through `@testable import OpenBlipCore` for that file
only; the exporter tests use the public API.

## Shared formatting rules

- Output is UTF-8 text with a header row and CRLF line endings. No byte-order mark; the
  app decides whether to prepend one for Excel.
- Timestamps are ISO 8601 with the offset of `calendar.timeZone`, second precision, no
  fractional seconds: `2026-09-05T14:03:00-04:00`. Use `ISO8601DateFormatter` with
  `.withInternetDateTime` and that time zone. Build the formatter once per call.
- Booleans are `yes` and `no`. Integers have no thousands separators. Latency is whole
  seconds.
- Empty means unanswered or not applicable. Never write `nil`, `null` or `-`.
- Partial entries (`completedAt == nil`) are included with an empty `completed_at`.
  Consumers filter.
- Every entry in `snapshot.entries` produces output in the order given.
- Questions appear in `snapshot.survey.questions` sorted by `(position, id)`, archived
  included, since archived questions still have answers.
- "Current label" is `Question.label` or `ChoiceOption.label` from the snapshot's survey.
- "Label at time" for a question is `snapshot.questionVersionLabels[answer.questionVersionId]`,
  falling back to `snapshot.questionLabelHistory[questionId].label(at: answer.answeredAt)`
  when the version ID is unknown. For an option it is
  `snapshot.optionLabelHistory[optionId].label(at: answer.answeredAt)`. If neither
  resolves, use the current label.
- An option ID in an answer that no longer exists in the survey (should not happen after
  C2, but the exporter must not crash) is written with its ID as the label.

## Wide format

One row per entry. Fixed columns first, then one column per question.

```
entry_id, survey, prompted, prompt_scheduled_at, started_at, completed_at, latency_seconds, <question columns...>
```

- `survey` is the survey's current name.
- `prompted` is `yes` when `entry.promptId != nil`.
- `prompt_scheduled_at` is empty for manual entries.
- `latency_seconds` is `completedAt - prompt.scheduledAt`, empty for manual or
  incomplete entries.
- Question column header is the question's current label. If two questions share a
  label, every duplicate gets ` [` + first 8 characters of its ID + `]` appended so
  headers stay unique.
- Cell values: scale as the integer; single choice as the current option label; multi
  choice as current option labels joined with `; ` in the order the options appear in
  `Question.options` sorted by `(position, id)`; yes/no as `yes`/`no`; text verbatim;
  unanswered as empty. An empty multi-choice answer is empty.

## Long format

One row per answer, except choice answers, which produce one row per selected option. An
empty multi-choice answer produces one row with empty option columns.

```
entry_id, prompted, prompt_scheduled_at, started_at, completed_at, answered_at,
question_id, question_kind, question_label_at_time, question_label_current,
option_id, option_label_at_time, option_label_current,
numeric_value, bool_value, text_value
```

- Rows are ordered by entry order, then question `(position, id)`, then option
  `(position, id)` of the selected options.
- `question_kind` is `QuestionKind.rawValue`.
- Exactly one of `numeric_value`, `bool_value`, `text_value` is non-empty for scale,
  yes/no and text; all three are empty for choice rows.
- Answers to questions that are not in the survey (unknown `questionId`) are skipped in
  wide format and written in long format with empty label columns. They should not
  exist; the exporter must not crash on them.

## Tests

Swift Testing. Build snapshots by hand from the C1 types; do not depend on Storage.
Include one fixture that exercises everything: two prompted entries, one manual, one
partial; a scale, single, multi, yes/no and text question; an archived question with an
old answer; a renamed question and a renamed option with answers on both sides of the
rename; a multi-choice answer with zero selections; labels containing commas, quotes,
and newlines; a time zone other than UTC.

Cover:

- `CSV.escape` on plain, comma, quote, CRLF, LF, leading space, empty, and unicode.
- `CSV.row` terminates with CRLF and joins with commas.
- Wide: header count equals fixed columns plus question count; exactly one row per entry;
  duplicate labels get suffixed; multi-choice order follows option position; manual
  entries have empty prompt columns and `prompted = no`; partial entries have empty
  `completed_at` and `latency_seconds`; latency is correct for a prompted, completed
  entry; timestamps carry the calendar's offset.
- Long: one row per non-choice answer; one per selected option; one for an empty multi;
  `question_label_at_time` differs from `question_label_current` after a rename for the
  older answer and equals it for the newer; same for options; the version-ID path is
  used when present and the history path when it is not; ordering is stable.
- Both: an empty snapshot (survey with questions, no entries) yields only the header
  row; a snapshot with an unknown option ID in an answer does not crash.
- Parse the output back with a minimal CSV reader in the test and assert the field
  counts match the header on every row, including rows with embedded newlines.

## Acceptance

- `swift build` and `swift test` pass with zero warnings.
- `Export/` imports only `Foundation`.
- `Export/DESIGN.md`: purpose, the two shapes with their column lists, the label-at-time
  resolution order, the formatting rules, and known limitations (no BOM, no locale
  number formatting, partial entries included).

## Out of scope

JSON backup, writing files, share sheet, charts, any UI. Do not add columns beyond the
lists above without listing them under "Deviations from the task" with the reason.
