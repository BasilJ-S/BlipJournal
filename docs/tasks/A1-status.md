# A1 implementation status — 2026-09-06

Branch: `a1-app-shell`; worktree: `.claude/worktrees/a1-app-shell`.
Changes are uncommitted. No push, PR, or merge has been performed.

## Implemented

AppModel opens the protected store and seeds once, including archived surveys in the
check. Cold launch and background grace enforce the lock. Journal lists entries with
detail and confirmed deletion. Three tabs and all A2–A6 stub signatures are present,
with Settings links in handoff order. DEBUG sample-entry generation and an app unit
test target are included. Product strings use Blip Journal.

## Recovered round-two review

- Fixed authentication bypass: only explicit passcode-not-set allows continuing.
- Fixed stale prompt detail and answer summaries after refresh.
- Added `JournalRowSummary` cancellation guards and two controlled overlapping-load
  tests so a cancelled database read cannot restore an older summary.
- Moved detail reads, prompt fallback scan, and deletion/vacuum off the main actor.
  Full model refresh remains synchronous, documented as a limitation.
- Fixed sample answer timestamps and future completion dates; injected a seeded RNG
  for deterministic tests and guarded sample tests with DEBUG.
- Retained fatal launch errors: a retry contradicts the explicit A1 requirement.
- Replaced bounded Task.yield polling in the coordinator test with a continuation.
- Added missing feature DESIGN files and shortened App/Journal documentation.

## Validation

Xcode 26.3, iPhone 17 Pro simulator (iOS 26.3):
- Debug build and all 17 Swift Testing tests pass.
- Release build passes after the cancellation fix; no SampleEntry symbol in the Release
  executable checked.
- No Swift compiler warnings. Xcode emits “Metadata extraction skipped. No
  AppIntents.framework dependency found.” This warning has not been suppressed.
- Final app launches behind Face ID; simulated matching Face ID opens the Journal.
- Existing simulator entries show manual, prompted, and draft badges. Largest Dynamic
  Type wraps row text without truncation.
- On an isolated simulator, all five Settings rows opened their expected stubs.
- The real DEBUG “Add sample entry” menu action created a prompted entry. Detail showed
  prompt provenance, scale and choice answers, and the delete confirmation reported
  five answers and preserved the prompt's answered status.
- Confirming deletion of that only entry returned Journal to “No entries yet”. A
  read-only database check found zero entries and answers and one answered prompt.
- Returning after 35 seconds in background reopens Face ID with the same process
  (PID 33389), confirming a relock rather than a cold launch.
- Whitespace check passes; no temporary UI probe remains in the source.

Logs: `/private/tmp/blip-a1-final.log`, `/private/tmp/blip-a1-release.log`.
Screenshots: `/private/tmp/blip-a1-{lock,journal,journal-accessibility,relock}.png`.

## Remaining acceptance and delivery

Complete Data Protection must be checked on a physical device, not inferred from
simulator attributes. The app-switcher snapshot remains visible as documented.

Maintainer approval is required by AGENTS.md before committing or pushing. After
approval, open a draft PR and have the planner review; do not merge your own work.

## Deviations from the task (for the draft PR)

- Missing-passcode fallback checks the actual LAError instead of treating every
  unavailable authentication policy as a missing passcode.
- AppModel exposes all-survey lookup, entries, and a refresh revision to support the
  Journal and invalidate answer displays after writes.
- The prompt-survival sentence is shown only for prompted entry deletion.
- LockPolicy and debug sample generation remain in the app as explicitly specified
  by A1, despite the repository's general preference for core logic.
- No launch retry was added, following A1's explicit fatal-error requirement.
