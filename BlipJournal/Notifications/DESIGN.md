# Notifications

## Purpose

Turns the planner's output (`BlipJournalCore.PromptPlanner`) into real local
notifications and routes a tapped notification into the survey runner. Everything that
touches `UNUserNotificationCenter` goes through `NotificationCenterClient` so tests run
against a fake.

```
NotificationCenterClient.swift   protocol over UNUserNotificationCenter; live and fake
NotificationCoordinator.swift    protocol (A1) + NotificationCoordinator + Noop stand-in
NotificationDelegate.swift       UNUserNotificationCenterDelegate, set at launch
PromptRouteView.swift            what a tapped notification opens
NotificationSettingsView.swift   Settings → Notifications
```

## Refresh sequence

`refresh(now:)` runs every foreground and after every schedule-affecting write:

1. Load every survey (archived included) and `existing`: pending prompts plus every
   prompt whose `day` is today or later (`prompts(status: nil)`, filtered — volumes are
   small).
2. `PromptPlanner.plan` against `existing`, a `SystemRandomNumberGenerator`, and the
   given calendar.
3. Mark `plan.missedPromptIds` as `.missed`.
4. Insert `plan.newPrompts`.
5. If authorization is `.authorized` or `.provisional`, reconcile the request centre
   (below). Otherwise stop here: the store stays consistent (prompts are planned and
   marked missed on schedule) but nothing is requested until permission is granted.

A generation counter bumped at the start of every `refresh` guards steps 5 onward: a run
still awaiting the client when a newer run starts (a reset racing a stale in-flight
refresh) checks the counter before each destructive client call and gives up rather than
resurrecting requests the newer run already cleared. Steps 1-4 always run to completion
once started, since they are plain synchronous store writes with no client round trip to
race.

## Reconcile rule

**Target**: pending prompts with `scheduledAt > now` belonging to a survey that is not
archived and has `sampling.isEnabled`. Requests pending in the centre but outside the
target are removed. For each target prompt, the request is added if missing, or replaced
(re-adding under the same identifier and content) if its rendered content differs from
what is currently pending — `NotificationCenterClient.pendingRequestContent()` is what
makes that comparison possible without deleting and re-adding every request on every
refresh. Request identifier is always the prompt ID; the trigger is a non-repeating
`UNCalendarNotificationTrigger` from `calendar.dateComponents([.year, .month, .day,
.hour, .minute], from: scheduledAt)`.

Delivered notifications are then swept: one is removed if its prompt no longer exists, is
no longer `.pending`, or (while still pending) its content no longer matches what the
survey would render now. That last case is what clears a stale delivered notification
after its survey's notification preview or name changes, scoped to exactly the surveys
whose rendered content actually changed — nothing else is touched.

## Notification content

`Survey.notificationPreview.content(surveyName:)` (`BlipJournalCore`) is the only source
of a notification's title and body. Never anything from inside the survey beyond its name
in `.surveyName` mode. Sound is the default; `interruptionLevel` is `.timeSensitive`
(letting prompts through Focus); `categoryIdentifier` is `"PROMPT"`, registered with no
actions at launch.

## Denied or undetermined permission

Prompts are still planned and stored on every refresh regardless of authorization, so the
schedule stays correct the moment permission is granted. No request is added and nothing
delivered is swept while permission is anything but `.authorized` or `.provisional`.
`requestAuthorization()` is called only from the explicit "Enable notifications" button
in `NotificationSettingsView`; launch, foreground, `scheduleChanged`, `promptsDestroyed`
and displaying the settings screen never call it. Manual journaling, survey editing,
Insights and export never check authorization.

## Routing states (`PromptRouteView`)

Resolves the prompt, its survey (`AppModel.surveysById`, archived included so a deleted
survey is still distinguishable from a missing one), and any entry already linked to the
prompt, in that order:

| Entry | Prompt status | Result |
|---|---|---|
| unfinished (no `completedAt`) | any | resumes in the runner, even past expiry or after the planner marked it missed |
| completed | any | read-only detail; v0 has no edit |
| none | pending, not expired | fresh runner |
| none | pending, expired | marks it missed, then the dead end below |
| none | missed / dismissed | dead end: "expired before it was answered", offers a manual entry (`promptId: nil`) or Dismiss |
| none | answered | dead end: "already answered, entry deleted", offers a manual entry or Dismiss; never creates a second prompted entry |
| — | prompt or survey missing | "not available", Dismiss only |

`pendingRoute` is retained while locked: `RootView` only exists once unlocked, so the
sheet cannot appear until then. Clearing `pendingRoute` (finish, dismiss, or
`promptsDestroyed` finding the route's prompt gone) is the only way the sheet closes.

## Cold launch

`NotificationDelegate.shared` is set as the centre's delegate in `AppDelegate` before
SwiftUI builds anything. A tap arriving before a coordinator exists is stashed on the
delegate; `NotificationCoordinator.attach(to:)`, called once from `AppModel.live()`,
claims it into `pendingRoute`. A tap arriving after attachment sets `pendingRoute`
directly.

## Known limitations

- No quick-reply or other notification actions in v0; the `PROMPT` category carries none.
- iOS caps pending local notifications at 64 per app; `PromptPlanner.maxPending` (60)
  leaves headroom, shared across every survey, so a person running several
  high-frequency surveys sees a shorter horizon on each (see Sampling `DESIGN.md`).
- No background refresh: the schedule is only as fresh as the last foreground or
  schedule-affecting write.
- `Store` has no `unarchiveSurvey` yet (Storage `DESIGN.md`), so "unarchiving restores
  scheduling when the saved configuration is enabled" is implemented by the coordinator
  logic (an unarchived, enabled survey is eligible the same as any other) but not yet
  exercised by a coordinator test; A4 owns adding the unarchive path and its own coverage.
