# Task C2: Storage

**Status: done, merged in #8.** Kept as the record of what was asked. Where it and the code disagree, the code and the component's `DESIGN.md` are authoritative; the PR description lists the agreed deviations.

Implementation handoff for `BlipJournalCore/Sources/BlipJournalCore/Storage/`. Read `AGENTS.md`,
the "Storage subsystem" section of `README.md`, the C2 section of `docs/PLAN.md` (it is
the authoritative spec for hard delete and byte erasure; this handoff does not repeat all
of it), `Model/DESIGN.md` (especially "Recoverability"), and `Export/ExportSnapshot.swift`.
Do not touch anything under `BlipJournal/`.

## Goal

A `Store` class over GRDB and SQLite that persists the C1 model with insert-only
versioning for definitions, mutable prompts and entries, hard delete as the single
audited exception, an export snapshot loader, and a JSON backup. Every other subsystem
reads and writes through it.

## Branch and delivery

- Branch from `main`: `c2-storage`. Open a draft PR when done. See "Change control" in
  `AGENTS.md` for who reviews and who merges.
- Add `"Storage/DESIGN.md"` to the `exclude:` list in `Package.swift`. Other in-flight
  tasks add their own line; the maintainer resolves that conflict.
- Bump `CoreSchema.version` to `1` in the same PR as the first migration.

## Files to create

```
Storage/Schema.swift          DatabaseMigrator with migration "v1"
Storage/Rows.swift            GRDB record structs, one per table
Storage/Store.swift           Store class, open/inMemory, configuration, current-view resolution
Storage/Store+Definitions.swift
Storage/Store+Prompts.swift
Storage/Store+Entries.swift
Storage/Store+HardDelete.swift
Storage/Store+Export.swift    exportSnapshot and backup
Storage/Backup.swift          Backup, BackupExporter
Storage/DESIGN.md
Tests/BlipJournalCoreTests/Storage/   one test file per Store extension, plus SchemaTests
```

## Schema

Tables from `docs/PLAN.md` C2, with these details fixed here:

- Every ID column is `TEXT PRIMARY KEY`. Timestamps are `TEXT` in GRDB's default UTC
  format, which sorts lexicographically.
- Foreign keys are declared and enforced (GRDB enables them by default), with **no**
  `ON DELETE CASCADE`. Hard delete removes rows explicitly and in dependency order so the
  counts in `DeletionImpact` are the counts that go. Cascades would hide that.
- Indexes: `surveyVersion(surveyId)`, `surveySampling(surveyId)`, `question(surveyId)`,
  `questionVersion(questionId)`, `option(questionId)`, `optionVersion(optionId)`,
  `prompt(surveyId, day)`, `prompt(status)`, `entry(surveyId, startedAt)`,
  `entry(promptId)`, `answer(entryId)`, `answer(questionId)`, `answerOption(optionId)`.
  `answerOption` has a composite primary key `(answerId, optionId)`.
- `answer.kind` stores `QuestionKind.rawValue`. `numericValue` holds scale values,
  `boolValue` yes/no, `textValue` text. Choice answers store nothing in those three
  columns; their selections are `answerOption` rows. An empty multi-choice answer is an
  `answer` row with zero `answerOption` rows.
- `prompt.status` stores `PromptStatus.rawValue`.

Current version of a definition is the version row with the greatest `(createdAt, rowid)`.
Resolve it in Swift: load all version rows for the survey ordered by `createdAt, rowid`
and take the last per parent ID. Volumes are tiny, and one ordering rule in one place
beats correlated subqueries in five.

## Configuration

`Store.open(at directory: URL)`:

1. Create `directory` if missing. On iOS (`#if os(iOS)`) set
   `[.protectionKey: FileProtectionType.complete]` on the directory before the database
   file exists, so the database and any journal inherit it.
2. Open `DatabaseQueue` at `directory/blipjournal.sqlite` with a `Configuration` whose
   `prepareDatabase` runs `PRAGMA secure_delete = ON`. Keep the default rollback journal
   mode; do not switch to WAL.
3. Run the migrator.

`Store.inMemory()` opens `DatabaseQueue()` with the same configuration and migrator.
Tests use it except where the byte-erasure acceptance needs a real file.

`Store` is `final class Store: Sendable` holding a `let` `DatabaseQueue`. Every method is
synchronous and safe to call from any thread; the queue serialises. No `async` API.

## API

Exactly the `Store` and `DeletionImpact` in `docs/PLAN.md` C2, with these additions and
clarifications. Where this file and PLAN.md differ, this file wins; note the difference
in `DESIGN.md`.

- **Every mutating method takes a trailing `now: Date = Date()` parameter** and uses it
  for every `createdAt`, `respondedAt`, and version timestamp it writes. Version order
  depends on it, and tests need to control it.
- `createSurvey(name:sampling:questions:now:)` inserts the survey, one `surveyVersion`,
  one `surveySampling`, and every question and option in `questions` with their existing
  IDs and one version row each. This is how `SurveyTemplate.makeDefault()` is seeded.
- `updateQuestion` and `updateOption` insert a version row carrying **all** fields, not a
  diff. The caller passes the full intended state.
- `archiveSurvey`, `updateQuestion(isArchived:)` and `updateOption(isArchived:)` touch
  only their own level. Archiving a question writes nothing to its options.
- Add `func currentQuestionVersionIds(surveyId: String) throws -> [String: String]`,
  question ID to current version ID. The runner calls it once when it opens and stamps
  `Answer.questionVersionId` from it.
- Add `func labelHistory(surveyId: String) throws -> [LabelVersion]` for the survey name.
  All three `labelHistory` functions return version order, oldest first, `(createdAt,
  rowid)`. `LabelVersion.validFrom` is the version row's `createdAt`.
- `surveys(includeArchived:)` returns surveys ordered by `createdAt`, each with every
  question and option in its current version, archived included. `Survey.sampling` is
  the newest `surveySampling` row.
- `prompts(status:)` with `nil` returns all prompts. Both `prompts` functions order by
  `scheduledAt`.
- `insertPrompts` is a single transaction. `setPromptStatus` updates only `status` and
  `respondedAt`.
- `deleteFuturePendingPrompts(surveyId:after:)` deletes prompts of that survey with
  `status == pending` and `scheduledAt > after`. Nothing else. This is the one plain
  delete on the prompt table and it does not run vacuum: prompts carry no user text.
- `saveEntry(_:answers:now:)` is an upsert in one transaction. The entry row is replaced
  by value. For answers: rows whose ID is not in `answers` are deleted along with their
  `answerOption` rows; rows that exist keep their stored `answeredAt` and have their
  value and `questionVersionId` replaced; new rows are inserted with the `answeredAt` the
  caller supplied. Replacing an answer's `answerOption` rows is delete-then-insert.
- `entries(surveyId:from:to:)` filters on `startedAt`, inclusive `from`, exclusive `to`,
  ordered ascending. `nil` means unbounded.
- `deleteEntry` deletes the entry, its answers and their `answerOption` rows. It leaves
  the prompt row and its status untouched. It ends with the checkpoint and vacuum step.
- `hardDeleteSurvey`, `hardDeleteQuestion`, `hardDeleteOption`, `eraseEverything`,
  `deletionImpact`: as specified in PLAN.md. Throw `StoreError.notArchived` (define a
  `public enum StoreError: Error, Equatable` with `notArchived`, `notFound`) when the
  target's current version is not archived, or the ID is unknown. `eraseEverything`
  reseeds `SurveyTemplate.makeDefault(now:)` and returns the new `Survey`.
- Checkpoint and vacuum: after the deleting transaction commits, run
  `PRAGMA wal_checkpoint(TRUNCATE)` (a no-op in rollback journal mode, kept so a later
  switch to WAL stays safe) and then `VACUUM`, outside any transaction. Put this in one
  private helper called from every destructive method.
- `exportSnapshot(surveyId:)` builds `ExportSnapshot` as documented in
  `Export/ExportSnapshot.swift`: current-view survey, all entries ascending by
  `startedAt` with their prompt and answers, both label-history maps with a key for every
  question and option, and `questionVersionLabels` for every question version row of the
  survey. Throws `notFound` for an unknown survey.
- `backup()` returns a `Backup`.

## Backup

```swift
public struct Backup: Sendable, Equatable, Codable {
    public var schemaVersion: Int          // CoreSchema.version
    public var exportedAt: Date
    public var surveys: [SurveyRow]        // and one array per table, in schema order
    public var surveyVersions: [SurveyVersionRow]
    ...
    public var answerOptions: [AnswerOptionRow]
}
public enum BackupExporter {
    public static func json(_ backup: Backup) throws -> Data
}
```

The row structs are the GRDB records, made `public` and `Codable` for this purpose, with
one property per column and no logic. Rows appear in `(createdAt, rowid)` order for
versioned tables and primary-key order otherwise. `json` uses ISO 8601 dates, sorted keys,
and pretty printing, so two backups of the same database are byte-identical and
diffable. Import is out of scope.

## Tests

Swift Testing. Use `Store.inMemory()` and pass explicit `now` values, stepping them by
one second between mutations. Cover everything in the PLAN.md C2 acceptance list, plus:

- Migration runs on an empty database; opening the same file twice does not re-run it.
- `createSurvey` from the template reads back equal to the template (compare after
  normalising `createdAt`).
- Rename a question three times with ascending `now` and get four label versions in
  order; `survey(_:)` shows the last. Two versions written with the same `now` resolve by
  insertion order.
- `updateSampling` twice; `Survey.sampling` is the second.
- `currentQuestionVersionIds` changes for exactly the renamed question after a rename.
- Archive a question that has one archived option; other options remain unarchived;
  unarchive the question and the same option set is active.
- `saveEntry` twice with the same entry ID: one entry row; an answer present both times
  keeps its first `answeredAt` but takes the second value; an answer dropped the second
  time is gone with its `answerOption` rows; a new answer appears.
- Multi-choice answer with zero selections round-trips as `.multi(optionIds: [])`.
- `entries(surveyId:from:to:)` bounds are inclusive-exclusive.
- `deleteFuturePendingPrompts` keeps past pending, future answered, and other surveys'
  prompts.
- `deleteEntry` leaves the prompt `answered`.
- Every hard delete refuses an unarchived target and an unknown ID with the right error.
- `deletionImpact` counts equal the row-count deltas measured across the delete, at all
  three levels, including `entriesEmptied`, `oldest` and `newest`.
- Deleting an option removes a single-choice answer and prunes a multi-choice one.
- Deleting a survey leaves a second survey's rows untouched at every table.
- `eraseEverything` leaves exactly the reseeded template and nothing else.
- Byte erasure: open a store in a temporary directory, write a sentinel label and a
  sentinel free-text answer, delete each through every destructive path in turn, then
  read the `.sqlite`, `-journal`, `-wal` and `-shm` files if present as `Data` and assert
  the sentinel bytes do not occur.
- `exportSnapshot` has a history key for every question and option, entries in
  `startedAt` order, and a `questionVersionLabels` entry for every version.
- `backup()` then `BackupExporter.json` is deterministic across two calls and decodes
  back to an equal `Backup`.

## Acceptance

- `swift build` and `swift test` pass with zero warnings.
- `Storage/` imports only `Foundation` and `GRDB`.
- No `UPDATE` or `DELETE` statement touches a definition table outside
  `Store+HardDelete.swift`. Reviewer greps for it.
- `Storage/DESIGN.md`: purpose, schema in one block, the current-version rule, the
  `now` convention, the upsert rules of `saveEntry`, the hard delete ordering and the
  vacuum helper, what byte erasure does and does not guarantee, and known limitations.
- PLAN.md C2 acceptance list fully covered by tests.

## Out of scope

Sampling, CSV, analytics, anything in the app target, SQLCipher, backup import. If a
Store method is needed that is not listed here, add it, list it under "Deviations from
the task" in the PR, and say which consumer needs it.
