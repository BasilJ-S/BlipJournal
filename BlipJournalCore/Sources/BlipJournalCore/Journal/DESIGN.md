# Journal (core)

Pure filter and sort rules for the Journal list. No store access, clock or formatting;
the app loads entries and the answers a query needs, then calls `JournalQuery.apply`.

## Key types

- `JournalFilter`: survey (nil = all), source (any/prompted/manual), status
  (any/completed/draft) and an optional `JournalAnswerFilter`. The default value shows
  everything; `isActive` is "differs from the default".
- `JournalAnswerFilter`: `.option` (single choice equals, or multi-choice includes, an
  option ID) or `.yesNo`. Conditions reference IDs, never labels.
- `JournalSort`: newest first, oldest first, or by a scale/spectrum answer either way.
- `JournalQuery.questionIds` names the questions whose answers `apply` needs, so the
  caller reads only those (`Store.answers(questionIds:)`).
- What to offer: `isSortable`/`isFilterable` are the one statement of which kinds each
  feature reads (`normalized` uses them too). `pickableSurveys`, `filterableQuestions`,
  `sortableQuestions` and `pickableOptions` list active choices in display order, then
  append the current selection if it is archived, so a picker never loses what is
  filtering the list.

## Invariants

- Date order breaks ties by entry ID, so the list never reshuffles between reloads.
- Answer sort looks each entry's value up once, then sorts: numeric answers first in the chosen direction, ties newest first; entries
  with no numeric answer (unanswered, other kind, non-finite spectrum) last, newest first.
- An entry without an answer to the filter question never matches it.
- `normalized` drops references that no longer resolve against every survey (archived
  included): unknown survey, an answer condition without a survey or naming a missing
  question/option or a wrong kind, a sort question outside the filtered survey or not
  scale/spectrum. A dropped answer sort becomes newest first. Archived questions and
  options still resolve, so a filter survives archiving; hard delete drops it.

## Decisions

- Answer conditions and answer sort require a survey: questions belong to one survey,
  and a cross-survey question picker would mix unrelated scales.
- Scale and spectrum are not filterable, only sortable. Sorting covers "best and worst
  moments" without a range editor.

## Limitations

One answer condition at a time. Text answers are neither searchable nor sortable.
