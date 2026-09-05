# OpenBlip build plan

Work is split into tasks that one agent can finish in a single session. Each task lists
scope, the interfaces it must expose or consume, and acceptance criteria. Tasks in the
same phase with no arrow between them can run in parallel. Every task ends with a review
before merge.

Conventions for all tasks: read `AGENTS.md` first. Core tasks must add tests. Every task creates or updates the `DESIGN.md` of the component it touches. App tasks
must compile with zero warnings. Do not widen scope; note follow-ups at the bottom of
this file instead.

## Phase 0: scaffolding (done)

Repo, license, README spec, AGENTS.md, empty core package, XcodeGen spec, app entry point.

## Phase 1: OpenBlipCore

### C1. Domain model

Scope: `Sources/OpenBlipCore/Model/`. Pure value types, all `Sendable`, `Equatable`,
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
struct Answer { id; entryId; questionId; questionVersionId; value: AnswerValue }
struct LabelVersion { label: String; validFrom: Date }
enum SurveyTemplate { static func makeDefault() -> (survey: Survey, sampling: SamplingConfig) }
```

`Survey` and `Question` are the *current view*: latest version of every definition,
including archived ones. Defaults from README: 3 per day, 09:00 to 23:00, 60 min gap,
20 min expiry.

Acceptance: compiles under Swift 6 strict concurrency; `SurveyTemplate.makeDefault()`
matches the six default questions in README; round-trips through `JSONEncoder`.

### C2. Storage

Scope: `Sources/OpenBlipCore/Storage/`. GRDB schema with `DatabaseMigrator`, a `Store`
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
answer(id, entryId, questionId, questionVersionId, kind, numericValue, textValue, boolValue)
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

    // Export
    func exportSnapshot(surveyId: String) throws -> ExportSnapshot
    func backup() throws -> Backup   // every table, for JSON export
}
```

File protection: `open(at:)` sets `.protectionKey: .complete` on the directory before
creating the database, guarded by `#if os(iOS)`.

Acceptance: tests cover create survey from template and read it back; rename a question
twice and see three label versions with the newest as current; archive an option and see
it still present in the current view with `isArchived == true`; save an entry then
overwrite it with `saveEntry` and see one entry; `deleteFuturePendingPrompts` leaves past
and non-pending prompts alone; migration runs cleanly on an empty database.

### C3. Sampling

Scope: `Sources/OpenBlipCore/Sampling/`. Pure functions, generic over
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

Scope: `Sources/OpenBlipCore/Export/`. Pure functions over an `ExportSnapshot`.
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
struct Backup: Codable { var schemaVersion: Int; var exportedAt: Date; /* every table */ }
enum BackupExporter { static func json(_ b: Backup) throws -> Data }
```

Column sets are in README under "Export formats". Timestamps in ISO 8601 with local
offset. `label(at:)` picks the newest history entry with `validFrom <= date`.

Acceptance: RFC 4180 escaping of commas, quotes, and newlines; wide CSV has exactly one
row per entry and one column per question in position order; long CSV has one row per
selected option for multi-choice; label-at-time differs from current label after a
rename; unprompted entries have an empty prompt column and `prompted = no`.

### C5. Analytics queries

Scope: `Sources/OpenBlipCore/Analytics/`. Pure functions that turn `[ExportEntry]` into
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

## Phase 2: OpenBlip app

Every app task depends on C2. Interfaces below are what the app consumes.

### A1. App shell and lock

Scope: `OpenBlip/App/`. `AppModel` (`@Observable`, `@MainActor`) that opens the `Store`
in `Application Support/OpenBlip/`, seeds the default survey on first launch, and
exposes it to views via the environment. `LockView` using `LAContext` with
`.deviceOwnerAuthentication` (biometrics with passcode fallback), shown at launch and
after the app has been in the background for more than 30 seconds. `RootView` with three
tabs: Journal, Insights, Settings. Force light mode. Replace `PlaceholderView`.

Acceptance: app launches in the simulator, lock appears, unlocking shows tabs; entering
background and returning after the grace period re-locks; store file exists under the
protected directory.

### A2. Notifications

Scope: `OpenBlip/Notifications/`. `NotificationManager` that on every foreground:
runs `PromptPlanner`, persists the plan through `Store`, then reconciles
`UNUserNotificationCenter` so pending requests match pending prompts exactly (request
identifier = prompt id, category `PROMPT`, `interruptionLevel = .timeSensitive`,
trigger = `UNCalendarNotificationTrigger` at `scheduledAt`). Permission is requested from
an explanation screen, never cold. `UNUserNotificationCenterDelegate` routes a tap to the
runner with the prompt id, or to a "this prompt expired" sheet that marks it missed and
offers a manual entry. Sampling changes call `deleteFuturePendingPrompts` then re-plan.

Acceptance: after launch, `UNUserNotificationCenter.pendingNotificationRequests` equals
the store's pending prompts; a delivered notification tapped within expiry opens the
runner for that prompt; tapped after expiry shows the expired sheet and the prompt is
`missed`.

### A3. Survey runner

Scope: `OpenBlip/Survey/Runner/`. Renders any `Survey` on one scrolling screen. Scale as
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

Scope: `OpenBlip/Survey/Editor/`. Survey list with add and archive. Per-survey editor:
reorder, rename, archive questions; add questions of each kind; edit scale range and end
labels; option list with add, rename, archive; sampling settings form with validation
(`windowEnd > windowStart`, `promptsPerDay * minGap` fits in the window, expiry > 0).
Every write goes through the versioning API. Saving sampling triggers A2's re-plan.

Acceptance: renaming a question then viewing `labelHistory` shows both labels;
archived items disappear from the runner but remain in the editor under "Archived";
invalid sampling cannot be saved.

### A5. Insights

Scope: `OpenBlip/Insights/`. Swift Charts over C5. Survey picker, then: line chart of
the first scale question with a 7-point rolling mean, prompted and manual entries
distinguished; bar charts by hour and by weekday; bar chart of mean scale value per
option for a user-chosen choice question; compliance tile. Respects Dynamic Type.

Acceptance: renders with zero, one, and one hundred entries without layout breakage;
axis labels are readable at default text size on an iPhone SE-sized screen.

### A6. Export and settings

Scope: `OpenBlip/Settings/`. Settings screen linking to surveys (A4), notifications
status, and export. Export screen: pick a survey, pick wide or long CSV or JSON backup,
show the "exported files are not encrypted" warning, then `ShareLink` to a temp file in
the protected directory. About screen with license and repo link.

Acceptance: exported CSV opens in Numbers with correct columns; temp file is removed
after the share sheet closes.

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
