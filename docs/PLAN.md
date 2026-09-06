# Blip Journal build plan

Work is split into tasks that one agent can finish in a single session. Each task lists
scope, the interfaces it must expose or consume, and acceptance criteria. Tasks in the
same phase with no arrow between them can run in parallel. Every task ends with a review
before merge.

Conventions for all tasks: read `AGENTS.md` first. Core tasks must add tests. Every task creates or updates the `DESIGN.md` of the component it touches. App tasks
must compile with zero warnings. Do not widen scope; note follow-ups at the bottom of
this file instead.

## Phase 0: scaffolding (done)

Repo, license, README spec, AGENTS.md, empty core package, XcodeGen spec, app entry point.

## Phase 1: BlipJournalCore (done)

Merged in #2 (C1), #8 (C2), #7 (C3), #6 (C4), #5 (C5). Each `DESIGN.md` under
`BlipJournalCore/Sources/BlipJournalCore/` is authoritative where it and this file disagree.

### C1. Domain model

Scope: `Sources/BlipJournalCore/Model/`. Pure value types, all `Sendable`, `Equatable`,
`Codable`, `Identifiable` where sensible. IDs are `String` UUIDs.

```swift
enum QuestionKind: String { case scale, singleChoice, multiChoice, yesNo, text }
struct ScaleConfig { min: Int; max: Int; minLabel: String; maxLabel: String }
struct SamplingConfig { promptsPerDay: Int; windowStartMinutes: Int; windowEndMinutes: Int;
                        minGapMinutes: Int; expiryMinutes: Int; isEnabled: Bool }
struct ChoiceOption { id; label; position: Int; isArchived: Bool }
struct Question { id; kind; label; position; isRequired; isArchived;
                  scale: ScaleConfig?; allowsCustomOptions: Bool; options: [ChoiceOption] }
struct Survey { id; name; createdAt; isArchived; sampling: SamplingConfig; questions: [Question] }
enum PromptStatus: String { case pending, answered, missed, dismissed }
struct Prompt { id; surveyId; day: String /* yyyy-MM-dd local */; scheduledAt; expiresAt; status; respondedAt: Date? }
struct Entry { id; surveyId; promptId: String?; startedAt; completedAt }
enum AnswerValue { case scale(Int), single(String), multi([String]), yesNo(Bool), text(String) }
struct Answer { id; entryId; questionId; questionVersionId; answeredAt: Date; value: AnswerValue }
struct LabelVersion { label: String; validFrom: Date }
enum SurveyTemplate { static func makeDefault(now: Date = Date()) -> Survey }   // sampling rides on the survey
```

`Survey` and `Question` are the *current view*: latest version of every definition,
including archived ones. Defaults from README: 3 per day, 09:00 to 23:00, 60 min gap,
20 min expiry.

Acceptance: compiles under Swift 6 strict concurrency; `SurveyTemplate.makeDefault()`
matches the six default questions in README; round-trips through `JSONEncoder`.

### C2. Storage

Scope: `Sources/BlipJournalCore/Storage/`. GRDB schema with `DatabaseMigrator`, a `Store`
class wrapping `DatabaseQueue`, and all queries. Depends on C1.

Tables, all IDs `TEXT PRIMARY KEY`, all timestamps stored as GRDB default UTC strings:

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
answer(id, entryId, questionId, questionVersionId, answeredAt, kind, numericValue, textValue, boolValue)
answerOption(answerId, optionId)   -- one row per selected option
```

Current version of a definition = the row with the greatest `(createdAt, rowid)`.
Definition tables are insert-only: the `Store` exposes no update or delete for them.
Prompts and entries are mutable (status changes).

Public API:

```swift
final class Store: Sendable {
    static func open(at directory: URL) throws -> Store    // creates dir, applies migrations
    static func inMemory() throws -> Store

    // Definitions (every mutation inserts a version row)
    func createSurvey(name: String, sampling: SamplingConfig, questions: [Question]) throws -> Survey
    func renameSurvey(_ id: String, to name: String) throws
    func archiveSurvey(_ id: String) throws
    func updateSampling(surveyId: String, _ config: SamplingConfig) throws
    func addQuestion(surveyId: String, kind: QuestionKind, label: String, isRequired: Bool,
                     scale: ScaleConfig?, allowsCustomOptions: Bool) throws -> Question
    func updateQuestion(_ id: String, label: String, position: Int, isRequired: Bool,
                        isArchived: Bool, scale: ScaleConfig?, allowsCustomOptions: Bool) throws
    func addOption(questionId: String, label: String) throws -> ChoiceOption
    func updateOption(_ id: String, label: String, position: Int, isArchived: Bool) throws
    func surveys(includeArchived: Bool) throws -> [Survey]
    func survey(_ id: String) throws -> Survey?
    func labelHistory(questionId: String) throws -> [LabelVersion]
    func labelHistory(optionId: String) throws -> [LabelVersion]

    // Prompts
    func prompts(status: PromptStatus?) throws -> [Prompt]
    func prompts(surveyId: String, day: String) throws -> [Prompt]
    func insertPrompts(_ prompts: [Prompt]) throws
    func setPromptStatus(_ id: String, _ status: PromptStatus, respondedAt: Date?) throws
    func deleteFuturePendingPrompts(surveyId: String, after: Date) throws

    // Entries
    func saveEntry(_ entry: Entry, answers: [Answer]) throws   // upsert; used for autosave
    func entries(surveyId: String?, from: Date?, to: Date?) throws -> [Entry]
    func answers(entryId: String) throws -> [Answer]
    func deleteEntry(_ id: String) throws

    // Hard delete: the one exception to insert-only. Archived targets only.
    func deletionImpact(surveyId: String) throws -> DeletionImpact
    func deletionImpact(questionId: String) throws -> DeletionImpact
    func deletionImpact(optionId: String) throws -> DeletionImpact
    func hardDeleteSurvey(_ id: String) throws
    func hardDeleteQuestion(_ id: String) throws
    func hardDeleteOption(_ id: String) throws
    func eraseEverything() throws   // every row in every table, then reseed the default survey

    // Export
    func exportSnapshot(surveyId: String) throws -> ExportSnapshot
    func backup() throws -> Backup   // every table, for JSON export
}

struct DeletionImpact {
    var answers: Int          // answer rows that will go
    var entries: Int          // entries holding at least one of them
    var entriesEmptied: Int   // of those, entries left holding nothing
    var options: Int          // option definitions that will go
    var versions: Int         // definition version rows that will go
    var prompts: Int          // survey-level delete only
    var oldest: Date?         // answeredAt of the oldest answer that will go
    var newest: Date?
}
```

**Hard delete.** Archiving is how a person removes a question or an option, and it is
insert-only like every other edit. Erasing for good is a separate, deliberate second
step, and it is the only place in the app that deletes a definition row.

- Every `hardDelete` throws unless the target's current version has `isArchived == true`.
  The safety property is structural, not a UI convention: nothing in use can be erased,
  because it has to leave the survey first.
- One transaction each. A half-applied delete would leave answers pointing at definitions
  that no longer exist.
- **Question.** Deletes the question, its versions, its options and their versions, every
  answer to it, and those answers' `answerOption` rows. Entries are kept, including any
  left holding no answers: an entry records that a prompt was answered, so removing it
  would quietly rewrite the compliance numbers. `DeletionImpact.entriesEmptied` exists so
  the confirmation can say this is about to happen.
- **Option.** Deletes the option, its versions, and every `answerOption` row naming it.
  An answer left with no selection at all goes too, which is every single-choice answer
  that named it; multi-choice answers keep their other selections. This is the one rule
  worth a second opinion, since the alternative — delete every answer that touched the
  option — loses more but is easier to say in one sentence.
- **Survey.** Deletes everything belonging to it: definitions, sampling history, prompts,
  entries, answers. Never touches another survey.
- `deletionImpact` runs the same queries the delete will and counts what they match, so
  the number shown to a person is the number that goes. It takes no lock; a single-user
  app has nobody to race with.
- Once it commits, the erased text is gone from later exports and backups. Files already
  exported are outside the app; the export screen already says as much.

**Erasing the bytes.** A `DELETE` unlinks a row but leaves its bytes in free pages, and
the write-ahead log keeps a copy until it is checkpointed. For a delete whose whole
purpose is privacy that is not good enough.

- `Store.open` sets `PRAGMA secure_delete = ON` in the GRDB `Configuration.prepareDatabase`
  closure, so freed pages are overwritten as they are freed. It costs writes; this app
  does not write enough for that to matter.
- Every `hardDelete`, `deleteEntry` and `eraseEverything` ends with
  `PRAGMA wal_checkpoint(TRUNCATE)` then `VACUUM`, in that order, after the deleting
  transaction has committed. `VACUUM` cannot run inside a transaction, so it is a
  separate step rather than part of the delete.
- Say plainly what this does and does not buy. It removes the bytes from the database,
  its WAL and its journal. It cannot guarantee erasure from the flash underneath, because
  wear levelling means no application controls that. iOS Data Protection is what covers
  the residue, and the README should not promise more than that.
- `eraseEverything` reseeds the default survey afterwards, so the app comes back in its
  first-launch state rather than a broken empty one.

Acceptance for erasure, at every level and for `deleteEntry`: give the thing a label or a
free-text answer that is a unique sentinel string, delete it, then byte-search the
database file, the `-wal` and the `-shm` for that string and find nothing.

File protection: `open(at:)` sets `.protectionKey: .complete` on the directory before
creating the database, guarded by `#if os(iOS)`.

Archiving a question does not touch its options: their own `isArchived` stays as it was,
so unarchiving the question restores the option set that was visible before rather than
bringing everything back at once. The same holds for a survey and its questions.

Acceptance: tests cover create survey from template and read it back; rename a question
twice and see three label versions with the newest as current; archive an option and see
it still present in the current view with `isArchived == true`; archive a question that
has one archived option and see its other options still unarchived, then unarchive it and
get the same set back; save an entry then overwrite it with `saveEntry` and see one
entry; `saveEntry` does not rewrite an existing answer's `answeredAt`;
`deleteFuturePendingPrompts` leaves past and non-pending prompts alone; migration runs
cleanly on an empty database. For hard delete: it refuses an unarchived target at every
level; `deletionImpact` counts match what the delete actually removes; deleting a
question leaves its entries in place and its sibling questions' answers untouched;
deleting an option drops a single-choice answer but only prunes a multi-choice one;
deleting a survey leaves a second survey's rows alone; a backup taken afterwards contains
no trace of the deleted text.

### C3. Sampling

Scope: `Sources/BlipJournalCore/Sampling/`. Pure functions, generic over
`RandomNumberGenerator`. Depends on C1 only. Runs in parallel with C2.

```swift
struct DaySampler {
    func sample<G: RandomNumberGenerator>(day: Date, config: SamplingConfig,
                                          calendar: Calendar, using rng: inout G) -> [Date]
}
struct PromptPlan { var newPrompts: [Prompt]; var expiredPromptIds: [String] }
struct PromptPlanner {
    static let maxPending = 60
    var maxHorizonDays = 7
    func plan<G: RandomNumberGenerator>(now: Date, surveys: [Survey], existing: [Prompt],
                                        calendar: Calendar, using rng: inout G) -> PromptPlan
}
```

Sampler rules: split `[windowStart, windowEnd)` into `promptsPerDay` equal blocks; pick a
uniform random time in each; the lower bound of each block is raised to
`previous + minGap` when needed; if that pushes past the block end, place at the lower
bound if still inside the window, else drop the prompt. Use `calendar.date(byAdding:)`
for window edges so DST days are correct. Round results down to the minute.

Planner rules: expired = pending prompts with `expiresAt <= now`. Horizon =
`min(maxHorizonDays, max(1, maxPending / sum(promptsPerDay over enabled surveys)))`.
For each enabled survey and each day in the horizon, if the survey has no prompts for
that `day` key at all, sample and create pending prompts, keeping only times later than
`now + 60s`. If existing pending plus new would exceed `maxPending`, drop the latest
scheduled new prompts until it fits. Disabled or archived surveys get nothing.

Acceptance: seeded RNG produces deterministic output; every sampled time is inside the
window; times are ascending with gaps of at least `minGap`; count equals
`promptsPerDay` when the window comfortably fits; a window too small for the gap yields
fewer prompts rather than violating the gap; planner never returns more than
`maxPending` total pending; planner skips days already generated; planner marks overdue
prompts expired; today only yields future times; a DST transition day still yields times
within the local window.

### C4. Export

Scope: `Sources/BlipJournalCore/Export/`. Pure functions over an `ExportSnapshot`.
JSON backup lives in C2 (Storage), since it is a dump of table rows.
Depends on C1. The `ExportSnapshot` loader lives in C2; agree the struct shape here
first.

```swift
struct ExportSnapshot {
    var survey: Survey                              // current view, archived included
    var entries: [ExportEntry]
    var questionLabelHistory: [String: [LabelVersion]]
    var optionLabelHistory: [String: [LabelVersion]]
}
struct ExportEntry { var entry: Entry; var prompt: Prompt?; var answers: [Answer] }
enum CSVExporter {
    static func wide(_ s: ExportSnapshot, calendar: Calendar) -> String
    static func long(_ s: ExportSnapshot, calendar: Calendar) -> String
}
```

Column sets are in README under "Export formats". Timestamps in ISO 8601 with local
offset. `label(at:)` picks the newest history entry with `validFrom <= date`.

Acceptance: RFC 4180 escaping of commas, quotes, and newlines; wide CSV has exactly one
row per entry and one column per question in position order; long CSV has one row per
selected option for multi-choice; label-at-time differs from current label after a
rename; unprompted entries have an empty prompt column and `prompted = no`.

### C5. Analytics queries

Scope: `Sources/BlipJournalCore/Analytics/`. Pure functions that turn `[ExportEntry]` into
chart-ready series. Depends on C1 and C4's snapshot shape.

```swift
struct MoodPoint { date: Date; value: Double; prompted: Bool }
struct BucketStat { label: String; mean: Double; count: Int }
enum Analytics {
    static func series(question: String, entries: [ExportEntry]) -> [MoodPoint]
    static func rollingMean(_ points: [MoodPoint], window: Int) -> [MoodPoint]
    static func byHour(_ points: [MoodPoint], calendar: Calendar) -> [BucketStat]
    static func byWeekday(_ points: [MoodPoint], calendar: Calendar) -> [BucketStat]
    static func byOption(scaleQuestion: String, choiceQuestion: String,
                         entries: [ExportEntry], survey: Survey) -> [BucketStat]
    static func compliance(prompts: [Prompt]) -> (answered: Int, missed: Int, pending: Int)
}
```

Acceptance: hand-computed fixtures for each function; empty input yields empty output.

## Phase 2: Blip Journal app

Sequencing: **A1 runs alone first.** It builds the shell and, for every later screen, a
stub file with a fixed signature (see "Extension points" in `docs/tasks/A1-app-shell.md`).
**A2, A3, A4, A5 and A6 then run in parallel**, each replacing only its own stubs and
adding its own folder; none edits a shared file. A7 runs last. Handoffs: `docs/tasks/A1-app-shell.md`,
`A2-notifications.md`, `A3-survey-runner.md`, `A4-survey-editor.md`, `A5-insights.md`,
`A6-export-and-settings.md`. The app layout gains `BlipJournal/Journal/` (entries list and
detail, owned by A1). Where a handoff and this file disagree, the handoff wins.

### A1. App shell and lock

Scope: `BlipJournal/App/`. `AppModel` (`@Observable`, `@MainActor`) that opens the `Store`
in `Application Support/BlipJournal/`, seeds the default survey on first launch, and
exposes it to views via the environment. `LockView` using `LAContext` with
`.deviceOwnerAuthentication` (biometrics with passcode fallback), shown at launch and
after the app has been in the background for more than 30 seconds. `RootView` with three
tabs: Journal, Insights, Settings. Force light mode. Replace `PlaceholderView`.

The Journal tab lists entries newest first, showing the date, whether the entry was
prompted or manual, and a one-line summary. Tapping one opens a detail view of its
answers, which carries a **Delete entry** action. Free text is the other place private
words land, so an entry has to be destroyable on its own, not only as collateral of
deleting a question.

- The confirmation follows the same rules as a definition delete in A4: destructive
  styling, an explicit confirm, no swipe gesture, no typed string, and it says what
  survives.
- Deleting an entry leaves its prompt's status as `answered`. The person did answer at
  the time, and rewriting that would move the compliance numbers, which is the same
  reason a hard-deleted question leaves its emptied entries in place.
- It goes through `Store.deleteEntry`, so it gets the checkpoint and vacuum with
  everything else.

Acceptance: app launches in the simulator, lock appears, unlocking shows tabs; entering
background and returning after the grace period re-locks; store file exists under the
protected directory; the Journal lists prompted and manual entries distinguishably;
deleting an entry removes it from the list, leaves its prompt `answered`, and leaves no
trace of a sentinel free-text answer in the database files.

### A2. Notifications

Scope: `BlipJournal/Notifications/`. `NotificationManager` that on every foreground:
runs `PromptPlanner`, persists the plan through `Store`, then reconciles
`UNUserNotificationCenter` so pending requests match pending prompts exactly (request
identifier = prompt id, category `PROMPT`, `interruptionLevel = .timeSensitive`,
trigger = `UNCalendarNotificationTrigger` at `scheduledAt`). Permission is requested from
an explanation screen, never cold. `UNUserNotificationCenterDelegate` routes a tap to the
runner with the prompt id, or to a "this prompt expired" sheet that marks it missed and
offers a manual entry. Sampling changes call `deleteFuturePendingPrompts` then re-plan.

Anything that destroys prompts must be followed by a reconcile pass: a survey hard delete
and `eraseEverything` both remove prompt rows, and their pending notification requests
have to go with them. The reconcile handles it by construction, since it makes the centre
match the store exactly, but it does not run by itself. The caller triggers it, and that
is the easy thing to forget, which is why it is written down here.

Acceptance: after launch, `UNUserNotificationCenter.pendingNotificationRequests` equals
the store's pending prompts; hard-deleting a survey that has pending prompts leaves no
notification requests for it, and neither does erasing all data; a delivered notification tapped within expiry opens the
runner for that prompt; tapped after expiry shows the expired sheet and the prompt is
`missed`.

### A3. Survey runner

Scope: `BlipJournal/Survey/Runner/`. Renders any `Survey` on one scrolling screen. Scale as
a labelled slider with end labels; single and multi choice as wrapping chips; an inline
"Add" chip when `allowsCustomOptions` that calls `addOption`; yes/no as two buttons; text
as one line. Autosaves through `saveEntry` on every change with `promptId` set when
launched from a prompt. "Done" completes the entry and sets the prompt `answered`.
Required questions block Done until answered. Manual entries launch from a Journal
button with `promptId == nil`.

Acceptance: default survey completes in under 30 seconds by hand; killing the app
mid-entry leaves a partial entry that reopens; VoiceOver reads every chip with its
selection state; Dynamic Type at the largest accessibility size does not clip.

### A4. Survey editor

Scope: `BlipJournal/Survey/Editor/`. Survey list with add and archive. Per-survey editor:
reorder, rename, archive questions; add questions of each kind; edit scale range and end
labels; option list with add, rename, archive; sampling settings form with validation
(`windowEnd > windowStart`, `promptsPerDay * minGap` fits in the window, expiry > 0).
Every write goes through the versioning API. Saving sampling triggers A2's re-plan.

The verb in the UI is **Archive**, never Delete. Archived questions and options live on an
Archived screen, where each one offers **Delete permanently**. That flow is the only way
to destroy data, and it is designed so nobody erases more than they meant to:

- Reachable only from Archived, so it is never next to an everyday action. No swipe
  gesture anywhere; a swipe archives at most.
- One item at a time. No "empty archive", no multi-select. v0 accepts the tedium.
- The confirmation is built from `deletionImpact`, not from boilerplate. It names the item
  in full, gives real counts, and dates the oldest answer that will go: "Delete
  “What are you doing?” permanently. This erases 47 answers, the oldest from 3 March, and
  10 options. It cannot be undone."
- It says what survives, in the same breath: "Your other questions and their answers are
  not affected." Being told what is safe is what stops someone over-deleting; a warning
  alone does not.
- Warn separately when `entriesEmptied > 0`: some entries will be left with nothing in
  them, and they stay, so the compliance numbers do not move.
- Destructive styling and an explicit confirm. No typed confirmation string: it teaches
  people to type past the words rather than read them.

Acceptance: renaming a question then viewing `labelHistory` shows both labels;
archived items disappear from the runner but remain in the editor under "Archived";
invalid sampling cannot be saved; Delete permanently appears only under Archived and its
confirmation counts match what the store actually removes; deleting a question leaves the
rest of the survey and its entries intact; VoiceOver reads the confirmation as one
message rather than as scattered labels.

### A5. Insights

Scope: `BlipJournal/Insights/`. Swift Charts over C5. Survey picker, then: line chart of
the first scale question with a 7-point rolling mean, prompted and manual entries
distinguished; bar charts by hour and by weekday; bar chart of mean scale value per
option for a user-chosen choice question; compliance tile. Respects Dynamic Type.

Acceptance: renders with zero, one, and one hundred entries without layout breakage;
axis labels are readable at default text size on an iPhone SE-sized screen.

### A6. Export and settings

Scope: `BlipJournal/Settings/`. Settings screen linking to surveys (A4), notifications
status, and export. Export screen: pick a survey, pick wide or long CSV or JSON backup,
show the "exported files are not encrypted" warning, then `ShareLink` to a temp file in
the protected directory. About screen with license and repo link.

**Delete all data**, backed by `Store.eraseEverything()`. It is the simplest privacy
promise the app can make and the first thing people look for, so it is a plain item in
Settings rather than something buried. It gets the strongest confirmation in the app and
the same style as every other one: it names what goes in counts drawn from the store, it
says the app will return to its first-launch state with the default survey back, and it
says the deletion cannot be undone and does not reach files already exported. After it
runs, trigger A2's reconcile so no notification requests survive.

Acceptance: exported CSV opens in Numbers with correct columns; temp file is removed
after the share sheet closes; Delete all data empties every table, leaves the default
survey seeded and nothing else, leaves no pending notification requests, and leaves no
trace of a sentinel string in the database files.

### A7. Release readiness

Scope: app icon, launch appearance, accessibility audit with Xcode's Accessibility
Inspector, privacy manifest review, App Store listing copy with no medical claims,
TestFlight build. Depends on everything above.

## Follow-ups (not v0)

- Dark mode.
- Conditional questions.
- HealthKit State of Mind write-through.
- Backup import.
- SQLCipher option.
- Lock Screen widget for manual entries.
