# Export

## Purpose

Pure functions that turn an `ExportSnapshot` into CSV text. No file I/O, no database,
no UI: the app writes the string to a file and hands it to the share sheet. Imports only
`Foundation`. JSON backup is a dump of table rows and lives in Storage.

## Key types

- `ExportSnapshot` / `ExportEntry` — the input, built by `Store.exportSnapshot(surveyId:)`.
- `CSVExporter.wide(_:calendar:)` — one row per entry, one column per question.
- `CSVExporter.long(_:calendar:)` — one row per answer, or per selected option.
- `CSV` (internal) — RFC 4180 `escape(_:)` and `row(_:)`.

## Shapes

**Wide.** Fixed columns, then one column per question in `(position, id)` order,
archived questions included:

```
entry_id, survey, prompted, prompt_scheduled_at, started_at, completed_at, latency_seconds,
<one column per question, header = current label>
```

`survey` is the survey's current name. `prompted` is `yes` when `entry.promptId` is set;
`prompt_scheduled_at` and `latency_seconds` are empty for manual entries. If two
questions share a label, every duplicate gets ` [` + the first 8 characters of its ID +
`]` appended. Cells: scale as the integer; single choice as the current option label;
multi choice as current option labels joined with `; ` in option `(position, id)` order;
yes/no as `yes`/`no`; text verbatim; unanswered or empty multi as empty.

**Long.** One row per answer; choice answers produce one row per selected option, and an
empty multi-choice answer one row with empty option columns:

```
entry_id, prompted, prompt_scheduled_at, started_at, completed_at, answered_at,
question_id, question_kind, question_label_at_time, question_label_current,
option_id, option_label_at_time, option_label_current,
numeric_value, bool_value, text_value
```

Rows are ordered by entry order, then question `(position, id)`, then selected option
`(position, id)`. `question_kind` is the question's `QuestionKind.rawValue` (the value's
kind only when the question is unknown). At most one of `numeric_value`, `bool_value`,
`text_value` is non-empty, the one matching the value's case; all three are empty on
choice rows and on an empty text answer.

## Label-at-time resolution

Question, in order: `questionVersionLabels[answer.questionVersionId]`, then
`questionLabelHistory[questionId].label(at: answer.answeredAt)`, then the current label.
Option: `optionLabelHistory[optionId].label(at: answer.answeredAt)`, then the current
label. Current label is `Question.label` or `ChoiceOption.label` from the snapshot's
survey. An option ID the survey no longer has is written with the ID as its label.

## Invariants

- UTF-8, header row, CRLF line endings, no byte-order mark.
- Timestamps: `ISO8601DateFormatter` with `.withInternetDateTime` in `calendar.timeZone`,
  second precision, e.g. `2026-09-05T14:03:00-04:00` (UTC prints as `Z`). Built once per
  call.
- Booleans `yes`/`no`. Integers without separators. `latency_seconds` is
  `completedAt - prompt.scheduledAt` in whole seconds, rounded toward zero.
- Empty means unanswered or not applicable. Never `nil`, `null` or `-`.
- Every entry in `snapshot.entries` is written, in the order given. Partial entries have
  an empty `completed_at` (and `latency_seconds`); consumers filter.
- A field is quoted when it contains a comma, a double quote, CR or LF, or has leading or
  trailing whitespace; quotes inside are doubled. Escaping works on Unicode scalars, not
  `Character`s (see `CSV.swift`).
- Same snapshot, same output: nothing depends on dictionary order or on the order of
  `survey.questions`, `Question.options`, `ExportEntry.answers` or a multi selection.

## Decisions

- **Robust to bad references.** Answers whose `questionId` is not in the survey are
  skipped in wide and written in long with both question label columns empty, after the
  entry's known questions; their option columns resolve as usual. Unknown option IDs are
  written as their ID. A duplicate question or option ID keeps the first in
  `(position, id, input order)`. `prompted` follows `entry.promptId`; the prompt columns
  are taken from the joined `Prompt` only when `promptId` is set, so a dangling reference
  gives `yes` with empty prompt columns and a stray `Prompt` on a manual entry is ignored.
  None of these should exist after C2, but the exporter never crashes on them.
- **Answers to one question are sorted by `(answeredAt, id)`**; wide takes the first,
  long writes all. Unknown-question answers sort by `(questionId, answeredAt, id)`.
- **Multi-choice selections are deduplicated** and ordered by the question's options;
  selected IDs the question lacks follow in the order given.
- **Question kind mismatches are not policed.** A cell is formatted from the
  `AnswerValue` case, whatever the question's kind says.

## Known limitations

- No byte-order mark; the app decides whether to prepend one for Excel.
- No locale number formatting: `.` is never used, integers only.
- Partial entries are included, not filtered. In long format an entry with no answers
  at all produces no rows, since there is nothing to write a row per.
- An empty text answer is indistinguishable from an unanswered question in both shapes.
- A question label equal to a fixed column name (`entry_id`, ...) yields a duplicate
  header; only collisions between question labels are disambiguated, and two questions
  with the same label and the same 8-character ID prefix would still collide.
