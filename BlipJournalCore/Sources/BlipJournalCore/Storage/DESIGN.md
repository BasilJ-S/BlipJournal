# Storage

## Purpose

`Store` is the only door to the SQLite database. It persists the C1 model over GRDB:
insert-only versioning for definitions, mutable prompts and entries, hard delete as the
single audited exception, an `ExportSnapshot` loader, and a JSON `Backup`. Every other
subsystem reads and writes through it. Imports only `Foundation` and `GRDB`.

```
Schema.swift            DatabaseMigrator, migration "v1", tables children-first
Rows.swift              one GRDB record struct per table, no logic
Store.swift             open/inMemory, configuration, StoreError, current-view resolution
Store+Definitions.swift insert-only edits, surveys(), survey(), label histories
Store+Prompts.swift     prompt reads, insert, status, deleteFuturePendingPrompts
Store+Entries.swift     saveEntry upsert, entries(), answers(), deleteEntry
Store+HardDelete.swift  deletionImpact, hardDelete*, eraseEverything, DeletionImpact
Store+Export.swift      exportSnapshot, backup
Backup.swift            Backup, BackupExporter
```

## Schema (v1)

```
survey(id, createdAt)
surveyVersion(id, surveyId, name, isArchived, createdAt)
surveySampling(id, surveyId, promptsPerDay, windowStartMinutes, windowEndMinutes,
               minGapMinutes, expiryMinutes, isEnabled, createdAt)
question(id, surveyId, kind, createdAt)
questionVersion(id, questionId, label, position, isRequired, isArchived,
                scaleMin, scaleMax, scaleMinLabel, scaleMaxLabel, allowsCustomOptions, createdAt)
option(id, questionId, createdAt)
optionVersion(id, optionId, label, position, isArchived, createdAt)
prompt(id, surveyId, day, scheduledAt, expiresAt, status, respondedAt)
entry(id, surveyId, promptId, startedAt, completedAt)
answer(id, entryId, questionId, questionVersionId, answeredAt, kind,
       numericValue, textValue, boolValue)   UNIQUE (entryId, questionId)
answerOption(answerId, optionId)        PRIMARY KEY (answerId, optionId)
```

IDs are `TEXT PRIMARY KEY`. Timestamps are GRDB's default UTC string
(`yyyy-MM-dd HH:mm:ss.SSS`), which sorts lexicographically; precision is one
millisecond. `answer.kind` and `prompt.status` hold the enum raw values. Scale, yes/no and
text answers use `numericValue`, `boolValue` and `textValue` respectively; choice answers
use none of them and keep their selections in `answerOption`, so an empty multi-choice
answer is an `answer` row with no `answerOption` rows. Foreign keys are enforced with no
`ON DELETE CASCADE`: every deletion is written out explicitly, children first, so what a
delete removes is exactly what its code says. Indexes: every foreign key column except
`answer.questionVersionId`, plus `prompt(surveyId, day)`, `prompt(status)`,
`entry(surveyId, startedAt)` and `answerOption(optionId)`.

## Invariants

- **The current version is the last row in `(createdAt, rowid)` order.** That is the one
  ordering rule, `Store.versionOrder`, and it is applied in Swift: `DefinitionRows` loads
  every version list of a survey in that order and takes the last per parent.
  `labelHistory` returns the same order, oldest first, so `label(at:)` tie-breaks the way
  the current view does. Two versions written with the same `now` resolve by insertion.
  The tie-break leans on rowids keeping their relative order across `VACUUM`, which
  holds for these tables because each has a `TEXT PRIMARY KEY` and its own rowid; a
  `WITHOUT ROWID` table would break it.
- **`now` is the caller's clock.** Every method that stamps a timestamp the caller does
  not already supply takes a trailing `now: Date = Date()` and uses it for every
  `createdAt` it writes. Version order depends on it, and tests step it by a second per
  mutation. `saveEntry` takes no `now`: every timestamp it writes comes from the `Entry`
  and `Answer` values, and `setPromptStatus` takes `respondedAt` outright. `backup(now:)`
  uses it as `exportedAt` so the JSON is reproducible.
- **Definitions are insert-only.** Nothing outside `Store+HardDelete.swift` updates or
  deletes a row of `survey`, `surveyVersion`, `surveySampling`, `question`,
  `questionVersion`, `option` or `optionVersion`. `updateQuestion` and `updateOption`
  write a version carrying every field; the caller passes the full intended state.
  Archiving touches only its own level: archiving a question writes nothing to its
  options, so unarchiving it restores exactly the option set that was visible.
- **One answer per question per entry.** `answer(entryId, questionId)` is unique, so
  export and analytics never have to choose between two answers to one question. A
  `saveEntry` call carrying two answers to one question fails and rolls back; replacing a
  question's answer under a new identifier across two calls is fine, because dropped
  answers are deleted before new ones are inserted.
- **Positions of added things.** `addQuestion` and `addOption` append: one past the
  highest current position among their siblings, archived included, or 0.
- **Store methods are synchronous.** `Store` is `final class Store: Sendable` over one
  `DatabaseQueue`; the queue serialises every call, from any thread. There is no async
  API.
- **Unknown identifiers.** Definition mutators, `setPromptStatus`, `deleteEntry`,
  `exportSnapshot` and every hard delete throw `StoreError.notFound`. `insertPrompts` and
  `saveEntry` do not check; a row naming an unknown survey, prompt or question version
  fails its foreign key and surfaces as a GRDB `DatabaseError`. Readers that return a
  collection return it empty; `survey(_:)` returns nil.

## `saveEntry` upsert rules

One transaction. The entry row is replaced by value. Answers are reconciled by identifier
against the entry's stored answers:

| Stored answer | In `answers`? | Result |
|---|---|---|
| yes | no | deleted, with its `answerOption` rows |
| yes | yes | keeps its stored `answeredAt`; every other column replaced; selections deleted then reinserted |
| no | yes | inserted with the caller's `answeredAt` |

Keeping the stored `answeredAt` is what makes option history replayable per answer (see
"Recoverability" in `Model/DESIGN.md`). Selections are stored in the caller's order,
without repeats. An answer whose `entryId` is not `entry.id`, or two answers sharing an
identifier, is a programming error and traps.

## Hard delete

The one place that deletes a definition row. Each of `hardDeleteSurvey`,
`hardDeleteQuestion`, `hardDeleteOption` throws `notArchived` unless the target's current
version is archived, runs in one transaction, and removes rows children-first:

```
answerOption (of doomed answers; at option level also any naming the option)
answer → entry, prompt (survey only)
optionVersion → option → questionVersion → question
surveySampling → surveyVersion → survey (survey only)
```

- **Question:** its versions, options and option versions, every answer to it and their
  selections. Entries stay, including ones left empty; `DeletionImpact.entriesEmptied`
  says how many.
- **Option:** its versions and every selection naming it. An answer left with no
  selection goes too, which is every single-choice answer that named it; multi-choice
  answers keep their other selections. Above option level nothing is pruned by option:
  every selection naming a doomed option belongs to a doomed answer, and a selection
  stored under some other question would fail its foreign key and roll the whole delete
  back rather than vanish from an answer the impact never counted.
- **Survey:** everything belonging to it, never another survey's rows.
- `deletionImpact` collects the same rows the delete would (one private `DoomedRows`
  builder per level feeds both), so the counts shown are the counts that go. It has the
  same preconditions as the delete. At survey level `entries` counts every entry of the
  survey, answerless ones included, and `entriesEmptied` is 0; `versions` counts survey
  versions, sampling rows, question versions and option versions.
- `eraseEverything` deletes every row of every table and reseeds
  `SurveyTemplate.makeDefault(now:)` in the same transaction.
- **Vacuum helper.** Every destructive method (`deleteEntry`, the three hard deletes,
  `eraseEverything`) ends with `Store.checkpointAndVacuum()`: `PRAGMA
  wal_checkpoint(TRUNCATE)` (a no-op in rollback journal mode, kept so a switch to WAL
  stays safe) then `VACUUM`, outside any transaction because SQLite refuses `VACUUM`
  inside one. Because the two are separate steps, a destructive method can throw after
  its delete has committed (disk full during `VACUUM`, say): the rows are gone and the
  error is about the cleanup. Callers should reload rather than assume nothing happened.
  `deleteFuturePendingPrompts` does not vacuum: prompts carry no user text. It also
  skips a pending prompt that already has an entry, because the runner autosaves against
  a prompt before marking it answered and deleting it would orphan that entry.

## Byte erasure

`Store.open` runs `PRAGMA secure_delete = ON` on every connection, so SQLite zeroes freed
content instead of leaving it in free pages, and the vacuum step rebuilds the file so
freed pages leave it. `VACUUM` works by copying the surviving rows into a temporary
database and back; with `PRAGMA temp_store = MEMORY`, also set on every connection, that
copy stays in memory rather than landing in SQLite's temp directory, which on iOS is
outside the protected database directory. The journal mode is SQLite's default rollback
journal, which is unlinked at commit. Together these remove the deleted bytes from the
database file, its journal, and (should WAL ever be enabled) the write-ahead log. On iOS
the database directory carries `FileProtectionType.complete`, which the file and any
journal inherit.

What it does not do: guarantee erasure from the flash underneath, which wear levelling
puts outside any application's control, or scrub text that an autosave overwrote in
place without a delete (see limitations). iOS Data Protection covers the residue, and the
README promises no more than that.

## Decisions

- **Rows are `public` and `Codable`** only so `Backup` can carry them verbatim; they have
  no behaviour. `QuestionKind` and `PromptStatus` get `DatabaseValueConvertible` from
  GRDB's `RawRepresentable` support, so rows hold the enums and the JSON shows raw values.
  Those two conformances are declared here, in `Rows.swift`, on purpose: Model stays
  free of GRDB, and the conformance is only visible to a client that imports GRDB.
- **Version resolution in Swift, not SQL.** Volumes are tiny; one ordering rule in one
  place beats correlated subqueries in five.
- **Backups are reproducible.** `BackupExporter.json` uses sorted keys, pretty printing
  and ISO 8601 dates with millisecond fractions (the database's precision); versioned
  tables are listed in `(createdAt, rowid)` order, the rest in primary-key order.
  `BackupExporter.decode` is the exact inverse: it builds every `Date` through GRDB's own
  parser, the path a row takes out of SQLite, and `backup(now:)` rounds `exportedAt` the
  same way, so `decode(json(b)) == b`. Importing into a store is not built, and the row
  structs have no public initialiser until it is.
- **No `ON DELETE CASCADE`.** Cascades would hide the counts `DeletionImpact` promises.

## Deviations from the C2 handoff

- `saveEntry(_:answers:)` has no `now` parameter; it would be unused.
- `backup(now:)` takes `now` for `exportedAt`; the handoff's `backup()` could not be
  byte-identical across calls.
- `DeletionImpact.entries` at survey level counts every entry of the survey, not only
  those holding a doomed answer: answerless entries go too and the confirmation should
  say so. `versions` includes `surveySampling` rows, which PLAN.md's "definition version
  rows" does not spell out.
- `BackupExporter.decode` exists (tests need it). Import remains out of scope.
- `setPromptStatus` takes `respondedAt` as in PLAN.md rather than a `now`.
- `deleteFuturePendingPrompts` keeps a pending prompt that has an entry.
- `Store.databaseFileName` is public so a caller can find the file.

## Known limitations

- Timestamps round-trip at millisecond precision; a `Date` with finer fractions comes back
  rounded to the nearest millisecond, both from SQLite and from the backup JSON. A
  `Date()` taken at runtime therefore does not compare equal to its stored form.
- Autosave overwrites (`saveEntry` replacing a text answer) are plain updates without a
  vacuum, so the previous text may linger in the file until the next destructive call.
- There is no `unarchiveSurvey`; a survey, once archived, is hidden until hard-deleted.
- `entriesEmptied` is a preview; nothing removes an emptied entry later.
- **What the Store does not check.** Foreign keys reject unknown identifiers and
  duplicate keys, and that is all. The Store accepts, unchecked: a value outside its
  question's scale or option set; an answer whose `kind` (taken from the value) differs
  from its question's; an answer to a question of another survey than its entry; an
  entry whose prompt belongs to another survey; a `questionVersionId` of a different
  question; a selection naming another question's option. The runner and the planner
  own those invariants. On such data an export can lack a label key, and a hard delete
  fails with a GRDB `DatabaseError` rather than a `StoreError`. A row whose `kind`
  disagrees with its value columns fails to load with a `DatabaseError`; an answer
  identifier already used by another entry fails its primary key.
- The byte-erasure test proves the outcome, not each safeguard: `secure_delete` alone or
  `VACUUM` alone would also pass it. `SchemaTests` pins the pragmas separately.
- Single-connection `DatabaseQueue`: readers wait for writers. Fine for one person and one
  screen; a later switch to `DatabasePool` would need WAL, which the vacuum helper already
  anticipates.
