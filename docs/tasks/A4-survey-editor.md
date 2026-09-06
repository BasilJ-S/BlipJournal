# Task A4: Survey editor and Archived

Implementation handoff for `BlipJournal/Survey/Editor/`. Read `AGENTS.md`, the "UI subsystem"
section of `README.md` (editor bullet), the A4 section of `docs/PLAN.md` including its
"Archive, then erase" rules, `Storage/DESIGN.md` (versioning and hard delete),
`Model/SamplingConfig.swift` (validation), and `BlipJournal/App/DESIGN.md`. Requires A1 on
`main`. Do not modify `BlipJournalCore/` or files outside `Survey/Editor/` and
`BlipJournalTests/Editor/`.

## Goal

Everything a person does to a survey definition: create, rename, archive surveys; add,
rename, reorder, archive questions and options; set the sampling schedule; and, from the
Archived screen only, delete permanently. Replace the A1 stub `SurveyListView.swift`
(`init()` reading `AppModel` from the environment). Every write goes through the Store's
versioning API; the only deletes are the `hardDelete` calls behind the Archived screen.

## Branch and delivery

Branch from `main`: `a4-survey-editor`. Draft PR when done. `xcodebuild` build and test
against the iPhone 17 Pro simulator, zero app-target warnings.

## Files

```
Survey/Editor/SurveyListView.swift          replaces stub: active surveys, add, archive; link to Archived
Survey/Editor/SurveyEditorView.swift        name, questions (reorder, archive), sampling link, Archived link
Survey/Editor/QuestionEditorView.swift      label, required, scale config, custom options toggle, options list
Survey/Editor/NewQuestionSheet.swift        kind picker, label, initial config
Survey/Editor/SamplingSettingsView.swift    form with live validation
Survey/Editor/ArchivedView.swift            archived surveys, questions, options; Unarchive; Delete permanently
Survey/Editor/DeletionConfirmation.swift    builds the confirmation text from DeletionImpact
Survey/Editor/EditorModel.swift             @MainActor @Observable; all writes and reorder maths; testable
Survey/Editor/DESIGN.md
BlipJournalTests/Editor/EditorModelTests.swift
```

## EditorModel

One model for the whole editor, holding `store`, `notifications` (from `AppModel`), and
a reload of the survey after every write:

```swift
@MainActor @Observable final class EditorModel {
    init(store: Store, notifications: any NotificationCoordinating)
    func createSurvey(name: String, now: Date = Date()) throws -> Survey   // empty questions, .default sampling
    func rename(surveyId:to:)  archive(surveyId:)  unarchive(surveyId:)
    func addQuestion(surveyId:kind:label:isRequired:scale:allowsCustomOptions:)
    func updateQuestion(_ question: Question)              // full state; inserts a version
    func moveQuestions(surveyId:, from: IndexSet, to: Int)  // renumbers positions 0..n-1 over active questions
    func addOption(questionId:label:)  updateOption(_ option: ChoiceOption)
    func moveOptions(questionId:, from:, to:)
    func saveSampling(surveyId:, _ config: SamplingConfig) async throws   // validates, updateSampling, notifications.scheduledChanged
    func deletionImpact(for target: ArchivedTarget) throws -> DeletionImpact
    func hardDelete(_ target: ArchivedTarget) async throws               // survey: then notifications.promptsDestroyed
}
enum ArchivedTarget { case survey(Survey), question(Question, in: Survey), option(ChoiceOption, in: Question, Survey) }
```

Reorder writes one version row per question whose position changed, not per question.
Unarchive is `updateQuestion` / `updateOption` / a survey version with `isArchived:
false`. Archiving never touches children (Store already guarantees this; do not add
cascading writes).

## Screens

**SurveyListView**: active surveys with name and a summary line ("3 prompts a day,
09:00 to 23:00"). Add button → alert for a name → `createSurvey`, then push the editor.
Swipe archives (with an "Archive" label, never "Delete"). Bottom row "Archived" →
`ArchivedView(scope: .all)`.

**SurveyEditorView**: editable name (commits on submit → rename). Questions section
lists `activeQuestions` with kind icon and required marker; `EditMode` supports move
and a swipe-to-archive; tapping opens `QuestionEditorView`; an Add button opens
`NewQuestionSheet`. A "Sampling" row → `SamplingSettingsView`. An "Archived in this
survey" row → `ArchivedView(scope: .survey(id))`.

**NewQuestionSheet**: kind picker (five kinds with one-line descriptions), label,
required toggle; for scale, the `ScaleConfig` fields with `isValid` gating; for choice
kinds, an "Allow adding options while answering" toggle and an initial options editor.

**QuestionEditorView**: label, required, scale fields (scale kinds), custom-options
toggle (choice kinds), options list with move, rename (inline text), swipe-to-archive,
and Add. Kind is shown but not editable; the caption explains why (answers depend on it).

**SamplingSettingsView**: enabled toggle, prompts per day stepper 0 to 20, window start
and end as `DatePicker` hour-and-minute (convert to minutes after midnight, `1440`
displayed as "midnight"), minimum gap and expiry steppers in minutes. Live
`validationErrors` rendered as red captions under the relevant fields. Save disabled
while invalid; Save calls `saveSampling` which also triggers the re-plan. Show a footer
explaining the 60-prompt cap in one sentence.

**ArchivedView**: three sections, Surveys, Questions, Options (with their survey and
question named), filtered by scope. Each row: Unarchive button and a destructive "Delete
permanently" button. No swipe actions here at all. Delete opens `DeletionConfirmation`.

**DeletionConfirmation**: a `confirmationDialog` or alert whose message is built from
`deletionImpact`, following PLAN.md's A4 wording exactly:

- Names the item in full.
- Real counts: answers, the oldest answer's date (medium style), options (question
  level), entries and prompts (survey level).
- What survives: "Your other questions and their answers are not affected." (question
  and option), "Your other surveys are not affected." (survey).
- When `entriesEmptied > 0`: "N entries will be left with no answers. They stay, so your
  response rate does not change."
- Ends with "It cannot be undone." Destructive confirm button, plain Cancel, no typed
  string.

After a survey delete, `hardDelete` awaits `notifications.promptsDestroyed`. After any
delete, `appModel.refresh()`.

## Tests

`EditorModelTests` on `Store.inMemory()` with `NoopNotificationCoordinator`, fixed `now`
values:

- `moveQuestions` renumbers to a contiguous 0..n-1 and writes versions only for moved
  questions; label history of an unmoved question is unchanged.
- `updateQuestion` twice yields three label versions with the last current.
- `archive` then `unarchive` of a question leaves its options' flags untouched.
- `saveSampling` with an invalid config throws before writing; a valid one writes and
  is the survey's sampling.
- `hardDelete` of an unarchived target throws `StoreError.notArchived` and nothing
  changes; of an archived option prunes multi answers; of an archived survey leaves a
  second survey intact.
- `deletionImpact` for a question matches the row deltas of the delete.

## Acceptance

- Build and tests pass, zero app-target warnings.
- Rename a question then check `labelHistory` (via a test) shows both labels; archived
  items vanish from the runner and appear under Archived; invalid sampling cannot be
  saved; Delete permanently is reachable only from Archived; its numbers match what the
  store removes; VoiceOver reads the confirmation as one message.
- `Survey/Editor/DESIGN.md`: the screen map, the reorder rule, the Archive/erase rules,
  the confirmation recipe, and known limitations (no drag reorder outside EditMode, no
  question kind change, no survey duplication).

## Out of scope

Answering surveys, notifications (beyond calling the two coordinator methods), charts,
export. Any change to the stub signature is a deviation to be listed in the PR.
