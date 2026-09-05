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

- **Identity.** Every identifier is a `String` holding a lowercase UUID from
  `Identifier.make()`. Identifiers are stable across versions of a definition: renaming a
  question keeps its `id` and adds a version row upstream.
- **The current view.** `Survey` and `Question` are the newest version of every
  definition, archived ones included. `activeQuestions` and `activeOptions` are what the
  runner shows: not archived, sorted by `position` with `id` as the tiebreaker so the
  order is stable when positions collide.
- **Answers reference identifiers, never labels.** `AnswerValue` choice cases carry
  option identifiers and `Answer` pins `questionVersionId`, so a later rename cannot
  rewrite history. Storage assigns `questionVersionId`; the model only carries it.
- **Recoverability.** Every answer must remain enough to reconstruct exactly what the
  person saw. See below.
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

## Recoverability

Definitions are insert-only, so nothing a person ever saw is deleted. Given one `Answer`,
this is how each part of the moment is recovered, and what each part depends on:

| What was on screen | Recovered from | Exact, or replayed? |
|---|---|---|
| Question wording, position, required flag, scale bounds | `Answer.questionVersionId` | Exact: a direct pin |
| Whether custom options were offered | `Answer.questionVersionId` (`allowsCustomOptions`) | Exact |
| The options offered, their labels and their order | every option of that question, each at its version current at `Answer.answeredAt`, archived ones dropped, sorted by that version's `position` | Replayed by timestamp |
| Which options the person chose | `AnswerValue.single` / `.multi` option identifiers | Exact |
| The survey's name at the time | `surveyVersion` history at `Answer.answeredAt` | Replayed by timestamp |
| The prompt behind it | `Entry.promptId` to a `Prompt`: `scheduledAt`, `expiresAt`, `status`, `day`. Nil means manual | Exact |
| The schedule that produced the prompt | `surveySampling` history at `Prompt.scheduledAt` | Replayed by timestamp |

Three things have to hold for the replayed rows to be exact, and all three are somebody
else's job to keep true:

1. **`Answer.answeredAt` is the only key.** It is per answer, not per entry, because an
   entry is autosaved over minutes and a custom option added at question four must not
   show up in the reconstructed choices for question two. Storage sets it on insert and
   must not rewrite it when an autosave overwrites the entry.
2. **Storage returns history in version order.** `label(at:)` breaks a `validFrom` tie by
   the receiver's order, so history must arrive ordered by `(createdAt, rowid)` — the
   same ordering that decides the current version. Otherwise an export can disagree with
   itself between runs.
3. **Options are only ever added or archived, never removed**, and an option added mid
   entry gets a `createdAt` at the moment it was added, so it does not leak backwards
   into earlier answers.

Options are replayed rather than pinned deliberately: an answer stores no
`optionVersionId`. Pinning the offered set per answer would mean a row per offered option
per answer, which is a lot of rows to record something the version history already
implies. The replay is only ambiguous if a definition is edited while an entry is open,
which a single-user app with one screen at a time does not allow.

## Decisions

- **`AnswerValue` hand-writes `Codable`.** The synthesised enum encoding is a nested,
  case-name-keyed object that is unreadable in a JSON backup and brittle to reorder. The
  hand-written form is a flat object with a `kind` discriminator and one payload key:
  `{"kind":"scale","value":5}`, `{"kind":"multiChoice","optionIds":["a","b"]}`. Backups
  are a user-facing file, so the shape is a contract; changing it needs a schema version
  bump. The discriminator is the `QuestionKind` raw value rather than the enum's own case
  name, so a backup names question kinds in exactly one vocabulary; `AnswerValue.kind`
  is the single mapping between the two.
- **Raw values are contracts.** `QuestionKind` and `PromptStatus` raw values are written
  to SQLite and to CSV. Renaming a case is a migration, not a refactor.
- **`validationErrors` returns a list, not a `Bool`.** The editor shows every problem at
  once. The order is fixed, and `gapDoesNotFit` is only evaluated once the window and the
  gap are each well formed, so one mistake does not produce a cascade of errors. A gap of
  zero is legal and means "no minimum"; a negative one is not, because the sampler would
  then be free to place prompts in any order.
- **`label(at:)` falls back to the earliest version.** An answer can carry a timestamp
  just before the first recorded version (a clock change, or a definition backfilled by a
  migration). Showing the oldest known wording beats showing nothing; only an empty
  history returns `nil`.
- **The ID helper is called `Identifier`, not `ID`.** `Identifiable` gives every
  conforming type an `ID` associated type, which would shadow an enum of that name inside
  the body of every type here, so `id: String = ID.make()` would not compile. One name
  avoids the question of which spelling to use.

## Known limitations

- No validation of a value against its question: nothing checks that a `.scale(9)` fits
  the question's `ScaleConfig`, or that a `.single(optionId:)` names an option that
  exists. The runner and Storage own that.
- `AnswerValue.isEmpty` does not trim whitespace, so `.text(" ")` is not empty. The
  runner decides what to do with whitespace before saving.
- Nothing here enforces the recoverability rules above; they are constraints on Storage
  and Export. In particular `Answer.answeredAt` defaults to `Date()`, so a caller that
  backdates an entry has to set it deliberately.
- `Prompt.day` is a `yyyy-MM-dd` string the caller supplies; nothing here parses or
  formats it. It is stored rather than derived from `scheduledAt` so the planner can ask
  "does this survey already have prompts for this day?" without redoing time zone
  arithmetic, and so the answer does not drift if the device changes time zone.
