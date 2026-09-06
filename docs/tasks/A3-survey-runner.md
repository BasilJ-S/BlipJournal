# Task A3: Survey runner

Implementation handoff for `OpenBlip/Survey/Runner/`. Read `AGENTS.md`, the "UI
subsystem" section of `README.md` (the runner bullet), the A3 section of `docs/PLAN.md`,
`Model/DESIGN.md` ("Recoverability"), `Storage/DESIGN.md` (the `saveEntry` rules), and
`OpenBlip/App/DESIGN.md`. Requires A1 on `main`. Do not modify `OpenBlipCore/` or any file
outside `Survey/Runner/` and `OpenBlipTests/Runner/`.

## Goal

The screen a person answers a survey on. It must be fast: one scrolling screen, big
targets, autosave on every change, no confirmation. Replace the A1 stub
`SurveyRunnerView.swift`, keeping its signature exactly:

```swift
struct SurveyRunnerView: View {
    init(survey: Survey, promptId: String?, onFinish: @escaping () -> Void)
}
```

## Branch and delivery

Branch from `main`: `a3-survey-runner`. Draft PR when done. `xcodebuild` build and test
against the iPhone 17 Pro simulator, zero app-target warnings.

## Files

```
Survey/Runner/SurveyRunnerView.swift     replaces stub; layout only
Survey/Runner/EntryDraft.swift           @MainActor @Observable; all logic; testable
Survey/Runner/ScaleInput.swift           row of tappable numbers with end labels
Survey/Runner/ChipGrid.swift             wrapping chips; single and multi; inline Add
Survey/Runner/YesNoInput.swift
Survey/Runner/TextInput.swift
Survey/Runner/DESIGN.md
OpenBlipTests/Runner/EntryDraftTests.swift
```

## EntryDraft

```swift
@MainActor @Observable
final class EntryDraft {
    private(set) var survey: Survey
    private(set) var entry: Entry
    private(set) var values: [String: AnswerValue]      // questionId → value
    var canComplete: Bool                                // every required active question answered and not isEmpty
    var missingRequired: [Question]

    init(store: Store, survey: Survey, promptId: String?, now: Date = Date()) throws
    func set(_ value: AnswerValue?, for questionId: String, now: Date = Date()) throws  // nil clears; saves
    func addOption(label: String, to questionId: String, now: Date = Date()) throws -> ChoiceOption
    func complete(now: Date = Date()) throws             // sets completedAt, marks prompt answered
}
```

Rules:

- **Resume.** If `promptId` is non-nil and an entry for it exists, load it and its
  answers. Otherwise create a new `Entry(surveyId:promptId:startedAt: now)` and save it
  immediately, so a draft exists from the first second (the Journal shows it as Draft).
- **Version stamps.** Call `store.currentQuestionVersionIds(surveyId:)` once in `init`
  and use it for every `Answer.questionVersionId`.
- **Autosave.** Every `set` writes through `store.saveEntry(entry, answers:)` with the
  full answer list. Keep answer IDs stable per question across saves (a dictionary
  questionId → answerId created on first set), so Storage preserves `answeredAt`. A
  cleared answer is removed from the list, which deletes it.
- **Empty is nothing.** `.multi([])` and `.text("")` are treated as cleared: not saved.
  Trim whitespace on text before deciding.
- **Add option.** `store.addOption` then reload `survey` from the store so the new chip
  appears; select it immediately. The runner is the only place this happens at answer
  time, so the option's `createdAt` is later than earlier answers' `answeredAt`, which
  is what keeps recoverability exact.
- **Complete.** Requires `canComplete`. Sets `entry.completedAt = now`, saves, and if
  `promptId` is set calls `setPromptStatus(promptId, .answered, respondedAt: now)`.
- Errors from the store surface as an alert in the view; the draft does not swallow them.

## Layout

One `ScrollView` with a `LazyVStack` of question cards for `survey.activeQuestions`,
each: label in headline style, a small "Required" caption when required, then the input.
A sticky bottom bar with a "Done" button, disabled until `canComplete`, with the missing
required labels shown in a caption when it is disabled. A "Close" toolbar button that
keeps the draft and calls `onFinish` (a partial entry is fine; the Journal shows it).

Inputs:

- `ScaleInput`: one horizontal row of equal-width tappable numbers from `min` to `max`,
  the selected one filled; `minLabel` under the left end, `maxLabel` under the right.
  At the largest Dynamic Type size the row may wrap to two lines rather than shrink.
- `ChipGrid`: wrapping layout (`Layout` protocol) of capsule chips for
  `question.activeOptions`; single choice deselects the previous; multi toggles. When
  `allowsCustomOptions`, a trailing "Add…" chip opens an alert with a text field; empty
  or duplicate labels (case-insensitive against active options) are rejected inline.
- `YesNoInput`: two equal buttons "Yes" and "No"; tapping the selected one clears.
- `TextInput`: single-line `TextField`, saves on submit and on focus loss.

Target size at least 44 points. Every chip has an accessibility label with its selection
state via `.accessibilityAddTraits(.isSelected)`.

## Tests

`EntryDraftTests` on `Store.inMemory()` seeded with the template:

- `init` with no prompt creates and saves one draft entry; the Journal query sees it.
- `init` with a prompt that already has an entry resumes it, values populated.
- Two `set` calls on one question produce one answer row whose `answeredAt` is from the
  first call and whose value is from the second.
- Setting `.multi([])` or `.text("  ")` removes the answer.
- `canComplete` is false until the required scale question is set; `complete()` sets
  `completedAt` and, with a prompt, marks it `answered` with `respondedAt`.
- `addOption` inserts the option, reloads the survey, and the new option is active.
- `questionVersionId` on saved answers equals the current version at init.

## Acceptance

- Build and tests pass, zero app-target warnings.
- Completing the default survey by hand takes under 30 seconds.
- Kill the app mid-entry; the Journal shows a Draft; opening it from a prompt route
  resumes it (A2 does the routing; verify with `New entry` and the same prompt ID in a
  test if A2 is not merged yet).
- VoiceOver reads each chip with its state; the largest accessibility text size does not
  clip any control.
- `Survey/Runner/DESIGN.md`: the draft's rules above, the answer-ID stability trick, the
  add-option ordering guarantee, and known limitations (no conditional questions, no
  undo).

## Out of scope

Editing surveys, notifications, charts. Any change to the stub signature is a deviation
to be listed in the PR.
