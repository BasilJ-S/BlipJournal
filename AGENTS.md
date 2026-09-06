# AGENTS.md

Guidance for AI coding agents and humans working in this repo. Keep this file short.

## Commands

```
cd OpenBlipCore && swift build          # build core package (no Xcode needed)
cd OpenBlipCore && swift test           # run core tests
xcodegen generate                       # regenerate OpenBlip.xcodeproj from project.yml
xcodebuild -scheme OpenBlip -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Layout

- `OpenBlipCore/` Swift package: model, storage (GRDB), sampling, export. No UIKit or SwiftUI.
- `OpenBlip/` iOS app: SwiftUI only. Depends on OpenBlipCore.
- `project.yml` XcodeGen spec. The `.xcodeproj` is generated and gitignored. Never edit it by hand.
- `docs/PLAN.md` work breakdown. Each task lists scope, interfaces, and acceptance criteria.

## Documentation

- Every component directory (each folder under `OpenBlipCore/Sources/OpenBlipCore/` and each feature folder under `OpenBlip/`) has a `DESIGN.md` next to the code.
- `DESIGN.md` is terse and human readable, one screen at most: purpose, key types, invariants, decisions and why, known limitations. It exists so someone can pick the component up cold.
- A PR that changes a component's behaviour, interface, or invariants must update that component's `DESIGN.md` in the same PR. Reviewers reject PRs where docs and code disagree.
- `README.md` holds the product spec. `docs/PLAN.md` holds the task breakdown. `docs/tasks/` holds per-task handoffs.

## Rules

- All logic that can live in `OpenBlipCore` must live there, with tests. UI files hold view code only.
- Definitions (surveys, questions, options) are insert-only. Never `UPDATE` or `DELETE` a definition row. Add a version row.
- The single exception is hard delete: a person can permanently erase an already-archived definition and every answer to it. It lives in one auditable place in `Store` and refuses anything not archived. Nowhere else deletes a definition row.
- Answers reference IDs, never label text.
- No network calls. No analytics. No third-party dependencies beyond GRDB without discussion.
- Swift 6 language mode with strict concurrency. Fix warnings, do not silence them.
- Light mode only. Use semantic system colors so a later dark mode is cheap.
- Every control needs an accessibility label. Support Dynamic Type.
- Do not add medical, diagnostic, or therapy language to UI strings.
- Tests: Swift Testing (`import Testing`, `@Test`, `#expect`) in `OpenBlipCore/Tests`. XCTest is not available without Xcode. Sampling and export are pure functions; test them with seeded RNGs and fixed dates.
- Commit messages: imperative mood, one line summary, body explains why.

## Change control

- Every change to this repository requires approval from the maintainer (@BasilJ-S) before it is merged or pushed.
- Work on a branch and open a pull request. Never push directly to `main`.
- Agents must not commit, push, or merge without the maintainer's explicit go-ahead for that specific change.

The loop for a task, and the roles in it:

1. The **implementer** branches from `main`, does the work, and opens a **draft** pull request. Deviations from the task go in the PR description under "Deviations from the task", with the reason.
2. The **planner** reviews the PR and posts the review as a PR comment: what to change before merge, and what is accepted as written. It does not merge.
3. The **maintainer** merges, squashing unless asked otherwise, and deletes the branch.

Nobody merges their own work. A task handoff that contradicts this is out of date; this file wins.
