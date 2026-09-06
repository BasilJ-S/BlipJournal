# Task A1: App shell, lock, and Journal

Implementation handoff for the iOS app target `OpenBlip/`. Read `AGENTS.md`, the "UI
subsystem" section of `README.md`, the A1 section of `docs/PLAN.md`, and
`OpenBlipCore/Sources/OpenBlipCore/Storage/DESIGN.md`. The core package is complete; do
not modify anything under `OpenBlipCore/`.

## Goal

The first runnable app: opens the encrypted store, seeds the default survey, locks
behind Face ID, shows the three-tab root, and gives the Journal tab a real entries list
with entry detail and delete. Everything else is a stub screen with a fixed file name,
so the five tasks that follow (A2 to A6) can each replace their own stubs in parallel
without editing shared files.

## Branch and delivery

- Branch from `main`: `a1-app-shell`. Open a draft PR when done. See "Change control"
  in `AGENTS.md`.
- The Xcode project is generated: edit `project.yml`, run `xcodegen generate`, never
  commit `OpenBlip.xcodeproj`.
- Build and test with `xcodebuild -scheme OpenBlip -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
  (`build` and `test`). Zero warnings from the app target; ignore warnings from
  `SourcePackages/checkouts`.

## Files

Delete `PlaceholderView` from `OpenBlipApp.swift` and the `.gitkeep` files. Create:

```
OpenBlip/App/OpenBlipApp.swift                 @main; creates AppModel; scenePhase → lock policy
OpenBlip/App/AppModel.swift                    @MainActor @Observable; owns Store and surveys
OpenBlip/App/LockPolicy.swift                  pure struct, testable
OpenBlip/App/LockView.swift                    LocalAuthentication
OpenBlip/App/RootView.swift                    TabView: Journal, Insights, Settings
OpenBlip/App/DESIGN.md
OpenBlip/Journal/JournalView.swift             entries list, New entry button
OpenBlip/Journal/EntryDetailView.swift         answers read-only, Delete
OpenBlip/Journal/DESIGN.md
OpenBlip/Settings/SettingsView.swift           list of rows linking to the stubs below
OpenBlip/Settings/DESIGN.md
Stubs (one screen each, see "Extension points"):
OpenBlip/Survey/Runner/SurveyRunnerView.swift          A3
OpenBlip/Survey/Editor/SurveyListView.swift            A4
OpenBlip/Notifications/NotificationCoordinator.swift   A2 (protocol + no-op)
OpenBlip/Notifications/NotificationSettingsView.swift  A2
OpenBlip/Insights/InsightsView.swift                   A5
OpenBlip/Settings/ExportView.swift                     A6
OpenBlip/Settings/DeleteAllDataView.swift              A6
OpenBlip/Settings/AboutView.swift                      A6
OpenBlipTests/                                 new unit test target
project.yml                                    add OpenBlipTests target and test action
```

Add `Journal/` to the layout in `README.md` "Architecture" and to `AGENTS.md`
"Documentation" if it lists folders.

## AppModel

```swift
@MainActor @Observable
final class AppModel {
    let store: Store
    let notifications: any NotificationCoordinating
    private(set) var surveys: [Survey]          // active only, from store.surveys(includeArchived: false)
    private(set) var isLocked: Bool             // true at init
    var lockPolicy: LockPolicy

    init(store: Store, notifications: any NotificationCoordinating, now: Date = Date()) throws
    static func live() throws -> AppModel       // Store.open(at: Application Support/OpenBlip)

    func refresh() throws                       // reload surveys; call after any write
    func unlock()
    func didEnterBackground(at: Date)
    func willEnterForeground(at: Date)          // applies lockPolicy; then Task { await notifications.refresh(now:) }
}
```

`init` seeds: if `store.surveys(includeArchived: true)` is empty, create the survey from
`SurveyTemplate.makeDefault(now:)` via `store.createSurvey`. Seeding happens once, ever.

`live()` opens the store in `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]/OpenBlip`.
Every store error at launch is fatal and shown as a full-screen message with the error
text; there is no recovery path in v0 and hiding the error would be worse.

## Lock

```swift
struct LockPolicy: Equatable {
    var gracePeriod: TimeInterval = 30
    /// True when the app should lock on returning to the foreground.
    func shouldLock(backgroundedAt: Date?, now: Date) -> Bool   // nil → false; elapsed >= grace → true
}
```

`LockView` covers the whole window while `isLocked`. On appear it calls
`LAContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason:)`, which offers
Face ID with passcode fallback. On success `appModel.unlock()`. On failure or cancel it
shows an "Unlock" button to retry. If `canEvaluatePolicy` is false (no passcode set), show
"Your device has no passcode. Blip Journal cannot protect your journal until you set one." and
an "Continue anyway" button; Data Protection is also absent in that state, so pretending
otherwise would be dishonest. The app locks on every cold launch and whenever
`LockPolicy.shouldLock` says so. Never bypass the lock in `DEBUG`.

## RootView and tabs

`TabView` with three tabs: Journal (`JournalView`), Insights (`InsightsView` stub),
Settings (`SettingsView`). SF Symbols `book.closed`, `chart.xyaxis.line`, `gearshape`.
`.preferredColorScheme(.light)` on the root. `AppModel` is injected with `.environment`.

## Journal

`JournalView`: every entry from `store.entries(surveyId: nil, from: nil, to: nil)`,
newest first, sectioned by local day (section header is the date, relative style:
"Today", "Yesterday", else medium date). Each row: time of `startedAt`, survey name,
a "Prompted" or "Manual" badge, the first scale answer's value if the entry has one, and
a "Draft" badge when `completedAt == nil`. Tapping a row pushes `EntryDetailView`.
Toolbar: a "New entry" button that presents `SurveyRunnerView(survey:promptId:onFinish:)`
in a sheet. With one active survey it opens directly; with several, a menu picks one.
Empty state: a short line saying prompts will appear here once notifications are on,
with a "Log an entry now" button doing the same as New entry.

`EntryDetailView`: survey name, prompted or manual with the prompt's scheduled time,
started and completed times, then every question of the survey in position order
(archived included, only when the entry has an answer to it) with the answer rendered:
scale as "5 of 7" plus end labels, choice answers as current option labels, yes/no,
text. Unanswered questions are omitted. A "Delete entry" destructive button at the
bottom opens a confirmation:

> Delete this entry permanently. This erases its N answers. It cannot be undone.
> The prompt it answered still counts as answered.

Confirm calls `store.deleteEntry`, then `appModel.refresh()`, then pops.

`#if DEBUG` only: a toolbar menu item "Add sample entry" on JournalView that writes one
completed entry with random answers to the first active survey, dated within the last
14 days. It exists so this and later tasks can be checked by eye in the simulator.
Wrap it entirely in `#if DEBUG`.

## Settings

`SettingsView` is a `List` with rows in this order, each a `NavigationLink` to the named
view: "Surveys" → `SurveyListView`; "Notifications" → `NotificationSettingsView`;
"Export" → `ExportView`; "Delete all data" (destructive style) → `DeleteAllDataView`;
"About" → `AboutView`. This file is owned by A1 and later tasks must not need to edit it.

## Extension points (the stubs)

Each stub is one file with the exact signature below, rendering a `ContentUnavailableView`
that names the task that replaces it. Later tasks replace the file wholesale and nothing
else. Get the signatures right; they are the contract.

```swift
// Survey/Runner/SurveyRunnerView.swift   (A3)
struct SurveyRunnerView: View {
    init(survey: Survey, promptId: String?, onFinish: @escaping () -> Void)
}

// Survey/Editor/SurveyListView.swift     (A4)
struct SurveyListView: View { init() }          // reads AppModel from the environment

// Notifications/NotificationCoordinator.swift   (A2)
@MainActor
protocol NotificationCoordinating: AnyObject {
    var authorizationStatus: UNAuthorizationStatus { get }
    func requestAuthorization() async -> Bool
    func refresh(now: Date) async          // plan, persist, reconcile
    func scheduleChanged(surveyId: String, now: Date) async
    func promptsDestroyed(now: Date) async // after a survey hard delete or eraseEverything
    var pendingRoute: String? { get set }  // prompt ID from a tapped notification
}
@MainActor final class NoopNotificationCoordinator: NotificationCoordinating { ... }

// Notifications/NotificationSettingsView.swift   (A2)
struct NotificationSettingsView: View { init() }

// Insights/InsightsView.swift            (A5)
struct InsightsView: View { init() }

// Settings/ExportView.swift              (A6)
struct ExportView: View { init() }
// Settings/DeleteAllDataView.swift       (A6)
struct DeleteAllDataView: View { init() }
// Settings/AboutView.swift               (A6)
struct AboutView: View { init() }
```

`AppModel.live()` uses `NoopNotificationCoordinator`; A2 swaps it in one line.

## Test target

Add `OpenBlipTests` to `project.yml`: a `bundle.unit-test` target, host application
`OpenBlip`, sources `OpenBlipTests/`, included in the scheme's test action. Swift Testing
(`import Testing`) works in Xcode 26 test bundles. Tests build an `AppModel` on
`Store.inMemory()` with `NoopNotificationCoordinator`. Cover:

- `LockPolicy`: nil background time never locks; 29 seconds does not; 30 does; a custom
  grace period is honoured.
- `AppModel` seeds the template exactly once: after `init`, `surveys.count == 1` with the
  six template questions; a second `AppModel` on the same store does not add another.
- `refresh()` reflects a deletion made through the store.
- `didEnterBackground` then `willEnterForeground` after the grace locks; within it does
  not; `unlock()` clears it.

## Accessibility and appearance

Every control has an accessibility label. Badges are text, not colour alone. Test the
Journal at the largest Dynamic Type accessibility size; rows wrap rather than truncate.
Use semantic colours only. Portrait, iPhone only.

## Acceptance

- `xcodebuild build` and `xcodebuild test` succeed with zero app-target warnings.
- Launching in the simulator: lock appears, Face ID can be simulated via Features >
  Face ID > Matching Face; tabs appear; Settings rows open their stubs; Add sample entry
  produces rows in the Journal; entry detail shows answers; delete removes the row.
- Backgrounding the simulator (Home) for over 30 seconds and returning re-locks.
- The database directory exists under Application Support and carries the complete
  protection class (check with the `FileManager` attributes in a DEBUG log line at launch).
- `App/DESIGN.md`, `Journal/DESIGN.md`, `Settings/DESIGN.md` written: purpose, the
  extension-point table for stubs, the lock policy, the seeding rule, and known
  limitations.

## Out of scope

Notification scheduling, answering a survey, editing a survey, charts, export. Those are
A2 to A6 and they replace the stubs. If a stub signature turns out to be wrong for you,
do not change it; note it under "Deviations from the task" so the planner can update the
downstream handoffs.
