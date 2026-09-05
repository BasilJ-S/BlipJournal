# Model

## Purpose

The plain value types every other subsystem talks in. Storage, sampling, export and the
app all read and write these; none of them share types with each other directly. Nothing
here imports anything but `Foundation`: no GRDB, no SwiftUI, no formatting for display,
no persistence.

## Type graph

```
Survey ──< Question ──< ChoiceOption          definitions, insert-only upstream
  │          └─ ScaleConfig?                  scale questions only
  └─ SamplingConfig                           this survey's own schedule

Prompt      one scheduled ping: surveyId, day, scheduledAt, expiresAt, status
Entry ──< Answer ─ AnswerValue                one response and its answers
  └─ promptId?                                nil means a manual entry

[LabelVersion].label(at:)                     rename history lookup, used by export
SurveyTemplate.makeDefault()                  the six-question survey a new install gets
```

## Invariants

- **Identity.** Every identifier is a `String` holding a lowercase UUID from `ID.make()`.
  Identifiers are stable across versions of a definition: renaming a question keeps its
  `id` and adds a version row upstream.
- **The current view.** `Survey` and `Question` are the newest version of every
  definition, archived ones included. `activeQuestions` and `activeOptions` are what the
  runner shows: not archived, sorted by `position` with `id` as the tiebreaker so the
  order is stable when positions collide.
- **Answers reference identifiers, never labels.** `AnswerValue` choice cases carry
  option identifiers and `Answer` pins `questionVersionId`, so a later rename cannot
  rewrite history. Storage assigns `questionVersionId`; the model only carries it.
- **`kind` fixes the shape.** `scale` is non-nil only for scale questions; `options` and
  `allowsCustomOptions` are only meaningful when `QuestionKind.usesOptions`. Nothing here
  enforces that — these are value types with no validation hook — so the constructing
  code is responsible.
- **Schedules are minutes, not dates.** `SamplingConfig` stores times of day as minutes
  after local midnight so a schedule means the same thing on every date and across a DST
  transition. Turning them into instants is the sampler's job.
- **Expiry is inclusive.** `Prompt.isExpired(at:)` is true at exactly `expiresAt`, and
  always false once a prompt has an outcome.
- **No mutation helpers.** There is no `rename`, no `archive`, no save. Definitions are
  insert-only and that lives in Storage; these types are values you copy and hand over.

## Decisions

- **`AnswerValue` hand-writes `Codable`.** The synthesised enum encoding is a nested,
  case-name-keyed object that is unreadable in a JSON backup and brittle to reorder. The
  hand-written form is a flat object with a `kind` discriminator and one payload key:
  `{"kind":"scale","value":5}`, `{"kind":"multi","optionIds":["a","b"]}`. Backups are a
  user-facing file, so the shape is a contract; changing it needs a schema version bump.
  The discriminator is the *case* name (`single`, `multi`), not the `QuestionKind` raw
  value (`singleChoice`, `multiChoice`), because it names the shape of the payload rather
  than the question that happens to be answered.
- **Raw values are contracts.** `QuestionKind` and `PromptStatus` raw values are written
  to SQLite and to CSV. Renaming a case is a migration, not a refactor.
- **`validationErrors` returns a list, not a `Bool`.** The editor shows every problem at
  once. The order is fixed, and `gapDoesNotFit` is only evaluated for a well-formed
  window so one mistake does not produce a cascade of errors.
- **`label(at:)` falls back to the earliest version.** An answer can carry a timestamp
  just before the first recorded version (a clock change, or a definition backfilled by a
  migration). Showing the oldest known wording beats showing nothing; only an empty
  history returns `nil`.
- **`Identifier` is an alias for `ID`.** `Identifiable` gives every conforming type an
  `ID` associated type that shadows the `ID` enum inside that type's body, and
  module-qualifying does not help because the `OpenBlipCore` enum shadows the module name.
  Memberwise initialisers therefore default `id` to `Identifier.make()`. It is public
  only because a public default argument cannot reference an internal name; new call
  sites should say `ID.make()`.

## Known limitations

- No validation of a value against its question: nothing checks that a `.scale(9)` fits
  the question's `ScaleConfig`, or that a `.single(optionId:)` names an option that
  exists. The runner and Storage own that.
- `AnswerValue.isEmpty` does not trim whitespace, so `.text(" ")` is not empty. The
  runner decides what to do with whitespace before saving.
- `Prompt.day` is a `yyyy-MM-dd` string the caller supplies; nothing here parses or
  formats it. It is stored rather than derived from `scheduledAt` so the planner can ask
  "does this survey already have prompts for this day?" without redoing time zone
  arithmetic, and so the answer does not drift if the device changes time zone.
