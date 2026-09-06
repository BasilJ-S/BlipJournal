# Task A2: Notifications

Implementation handoff for `BlipJournal/Notifications/`. Read `AGENTS.md`, the "Notification
subsystem" section of `README.md`, the A2 section of `docs/PLAN.md`,
`BlipJournalCore/Sources/BlipJournalCore/Sampling/DESIGN.md`, `Storage/DESIGN.md`, and
`BlipJournal/App/DESIGN.md` (the extension points). Requires A1 on `main`. Do not modify
`BlipJournalCore/`.

## Goal

Turn the planner's output into real local notifications and route a tapped notification
into the survey runner. Replace the two A2 stubs from A1: `NotificationCoordinator.swift`
(keep the protocol, add the real implementation) and `NotificationSettingsView.swift`.
Change one line in `AppModel.live()` to use the real coordinator. Nothing else in `App/`
changes.

## Branch and delivery

Branch from `main`: `a2-notifications`. Draft PR when done. Build and test with
`xcodebuild` against the iPhone 17 Pro simulator, zero app-target warnings.

## Files

```
Notifications/NotificationCoordinator.swift    protocol (unchanged) + NotificationCoordinator
Notifications/NotificationCenterClient.swift   protocol over UNUserNotificationCenter + live and fake
Notifications/NotificationDelegate.swift       UNUserNotificationCenterDelegate
Notifications/PromptRouteView.swift            what a tapped notification opens
Notifications/NotificationSettingsView.swift   replaces stub
Notifications/DESIGN.md
BlipJournalTests/Notifications/                   coordinator tests on the fake client
```

## NotificationCenterClient

Everything the coordinator needs from `UNUserNotificationCenter`, so tests run without
it:

```swift
protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool     // .alert, .sound, .badge
    func pendingRequestIdentifiers() async -> Set<String>
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers: [String])
    func removeAllDeliveredNotifications()
}
struct LiveNotificationCenterClient: NotificationCenterClient   // wraps .current()
final class FakeNotificationCenterClient: NotificationCenterClient // records requests; settable status
```

## NotificationCoordinator

`@MainActor final class NotificationCoordinator: NotificationCoordinating`, built with
`Store`, `NotificationCenterClient`, `Calendar` (default `.autoupdatingCurrent`), and a
`PromptPlanner`.

`refresh(now:)`:

1. Load `surveys(includeArchived: true)` and `existing` = `prompts(status: .pending)` plus
   every prompt with `day >= DayKey.string(for: now, calendar:)` (use `prompts(status: nil)`
   and filter; volumes are small).
2. `PromptPlanner().plan(now:surveys:existing:calendar:using:)` with
   `SystemRandomNumberGenerator`.
3. For each `missedPromptIds`: `setPromptStatus(id, .missed, respondedAt: now)`.
4. `insertPrompts(plan.newPrompts)`.
5. Reconcile: target = pending prompts with `scheduledAt > now`. Remove pending requests
   not in target; add requests for target prompts not pending in the centre. Request
   identifier = prompt ID. Content: title = survey name, body = "How are you right now?",
   sound default, `interruptionLevel = .timeSensitive`, `categoryIdentifier = "PROMPT"`,
   `userInfo["promptId"]`. Trigger = `UNCalendarNotificationTrigger` from
   `calendar.dateComponents([.year,.month,.day,.hour,.minute], from: scheduledAt)`,
   non-repeating.
6. `removeAllDeliveredNotifications()` for prompts no longer pending is not possible
   per-prompt without extra API; call it in full when any prompt was marked missed, so
   stale banners do not linger.

Skip steps 5 and 6 when authorization is not `.authorized` or `.provisional`; steps 1
to 4 still run so the store stays consistent.

`scheduleChanged(surveyId:now:)`: `deleteFuturePendingPrompts(surveyId:after: now)` then
`refresh(now:)`. `promptsDestroyed(now:)`: `refresh(now:)`; the reconcile removes
requests whose prompts are gone.

`requestAuthorization()` calls the client and returns the result; the settings view
decides when to ask. `authorizationStatus` is cached and refreshed on `refresh`.

`pendingRoute` is set by the delegate and consumed by the UI.

## Delegate and routing

`NotificationDelegate` is set as the centre's delegate at app launch (in `BlipJournalApp`
via `UIApplicationDelegateAdaptor`, the one addition to `App/` this task may make).
`willPresent` returns `[.banner, .sound]` so a prompt shows even when the app is open.
`didReceive` reads `userInfo["promptId"]` and sets `coordinator.pendingRoute`.

`PromptRouteView` is presented by `RootView` as a sheet whenever `pendingRoute` is
non-nil (add this presentation to `RootView`; it is the second permitted edit in `App/`).
It loads the prompt and its survey. If the prompt is pending and not expired: mark
nothing yet, show `SurveyRunnerView(survey:promptId:onFinish:)`. If expired or already
answered or missed: mark it `missed` if it was pending, then show a sheet: "This prompt
expired. Prompts stay open for N minutes." with "Log an entry anyway" (opens the runner
with `promptId: nil`) and "Dismiss". Clear `pendingRoute` on finish or dismiss.

Register the `PROMPT` category with no actions in v0.

## NotificationSettingsView

Replace the stub. Shows: authorization status in words; if `.notDetermined`, an
explanation paragraph ("Blip Journal asks how you are at a few random moments each day.
It needs permission to send those prompts.") and an "Allow notifications" button that calls
`requestAuthorization()` then `refresh`; if `.denied`, text plus an "Open Settings" link
to `UIApplication.openSettingsURLString`; if authorized, a list of the next five pending
prompts (survey name, day, time) and a "Refresh schedule" button. Mention that
time-sensitive delivery lets prompts through Focus.

## Tests

On `Store.inMemory()` with the fake client, fixed `now` values, Toronto calendar:

- After `refresh`, pending request identifiers equal the IDs of pending prompts scheduled
  after `now`.
- An expired pending prompt is marked `missed` and its request removed.
- `scheduleChanged` removes future pending prompts of that survey only and regenerates.
- `promptsDestroyed` after `hardDeleteSurvey` leaves no request for that survey.
- With status `.denied`, prompts are still planned and stored but no request is added.
- A prompt that already has an entry survives `scheduleChanged` (Store spares it) and
  keeps its request.
- Two consecutive `refresh` calls with the same `now` are idempotent.

## Acceptance

- Build and tests pass, zero app-target warnings.
- In the simulator: allow notifications, background the app, wait for a scheduled
  prompt (set a tight window in the survey's sampling for testing), tap it, the runner
  opens for that prompt. Tap one after its expiry: the expired sheet appears and the
  prompt shows as missed in Insights compliance (A5) or the store.
- `Notifications/DESIGN.md`: the refresh sequence, the reconcile rule, what happens on
  denied permission, the routing states, and known limitations (no per-prompt delivered
  cleanup, no quick-reply actions, 60-request cap shared across surveys).

## Out of scope

Notification actions, widgets, background refresh, anything in the runner beyond
launching it.
