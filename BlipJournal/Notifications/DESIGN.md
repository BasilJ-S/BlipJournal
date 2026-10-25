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

The Settings button uses this same refresh: it preserves existing future times, fills
uncovered days (including an incomplete today with no future prompts), and restores
missing system requests. Its inline explanation distinguishes refresh from editing a
survey's schedule. The upcoming list shows the next five stored future prompts.
The separate Reschedule button calls `reschedule(now:)`: under the same refresh lock,
delete all surveys' future pending prompts, then plan and reconcile new random times.
Past prompts and answers survive; daily history counts toward today's limit. The UI
disables both buttons during either operation and reports reschedule success or failure.
Request-add errors propagate to that result; refresh can retry the persisted schedule.

1. Load every survey (archived included) and `existing`: pending prompts plus every
   prompt whose `day` is today or later (`prompts(status: nil)`, filtered — volumes are
   small).
2. `PromptPlanner.plan` against `existing`, a `SystemRandomNumberGenerator`, and the
   given calendar.
3. Settle `plan.missedPromptIds` through `Store.settleExpiredPrompts`: `.missed`, unless
   a notification answer left an open entry holding every required answer, which is
   completed and its prompt marked `.answered` (Storage `DESIGN.md`).
4. Insert `plan.newPrompts`.
5. If `canDeliverPrompts` (authorization `.authorized` or `.provisional`, a protocol
   extension so views share the rule), reconcile the request centre (below). Otherwise
   stop here: the store stays consistent (prompts are planned and marked missed on
   schedule) but nothing is requested until permission is granted.

Refreshes are serialized through the coordinator. A later refresh waits for an earlier
one to finish all of its notification-centre work, so a reset cannot reconcile against
stale store state while an older refresh is still adding requests. A generation counter
also guards steps 5 onward: a run that becomes stale gives up before later destructive
client calls. Steps 1-4 always run to completion once started, since they are plain
synchronous store writes with no client round trip to race.

## Reconcile rule

**Target**: pending prompts with `scheduledAt > now` belonging to a survey that is not
archived and has `sampling.isEnabled`. Categories are registered first (see "Answering
from the notification"). Requests pending in the centre but outside the target are
removed. For each target prompt, the request is added if missing, or replaced
(re-adding under the same identifier and content) if its rendered content or its
category differs from what is currently pending — `NotificationCenterClient.pendingRequestContent()` is what
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
in `.surveyName` mode. Sound is the default; interruption level is left at its default
(`.active`) rather than `.timeSensitive`, gated by
`LiveNotificationCenterClient.useTimeSensitiveInterruption` (currently `false`), since
letting prompts through Focus needs the
`com.apple.developer.usernotifications.time-sensitive` entitlement, which isn't available
under Personal Team signing; `categoryIdentifier` is `"PROMPT"` (no actions) or a
per-question answer category, below. Answer actions add nothing to the title or body.

## Answering from the notification

A prompt whose survey opens with a yes/no question, or a scale of at most five values,
offers that question's answers as notification actions (`NotificationAnswers` in Model
`DESIGN.md`); every other prompt behaves as before.

- **Actions, not a content extension.** Plain `UNNotificationAction`s need no extra
  target in `project.yml`, no app group and no shared database access from a second
  process. The cost: the person sees buttons, not the question. Five values is the cap
  (`NotificationAnswers.maxScaleChoices`) to keep the action list short; how many iOS
  shows without scrolling has not been checked on a device.
- **Categories.** One per question that offers answers, `"PROMPT.answers." + questionId`,
  plus the plain `"PROMPT"`. The coordinator registers the whole set on every reconcile,
  before adding requests, so an edited scale range updates the actions of requests
  already pending. A changed first question changes the category, which replaces the
  request. `AppDelegate` no longer registers categories at launch: that would wipe the
  answer categories until the next foreground refresh.
- **Unlock first (R4).** Every action is `.authenticationRequired` and none is
  `.foreground`: iOS asks for the device to be unlocked, then wakes the app in the
  background. The database is `NSFileProtectionComplete`, so `NotificationDelegate` also
  checks `UIApplication.isProtectedDataAvailable` and drops the answer when it is false.
- **Nothing shown (R6).** Answering opens no UI and sets no `pendingRoute`; the outcome
  is never displayed. Only a tap on the notification itself routes into the app, behind
  the lock as before.
- **Saving.** `answerFromNotification` reads the question ID back out of the category and
  calls `Store.saveNotificationAnswer`, which owns every rule: open entry, flagged
  `answeredFromNotification`, prompt left pending (R2, R3); expired or already settled
  saves nothing (R5); a question edited since scheduling saves nothing. Then
  `onEntrySaved` lets `AppModel` reload, and an expired outcome triggers a refresh.
- **Continuing (R3).** The entry stays open until the prompt expires. Tapping the
  notification, or the Journal's "survey open" banner, routes as for any unfinished
  entry and resumes it in the runner. iOS removes a notification once one of its actions
  is used, so in practice the banner is the way back.
- **Cold launch.** An answer arriving before a coordinator attaches is stashed on the
  delegate like a tap, and `attach(to:)` saves it.

## Denied or undetermined permission

Prompts are still planned and stored on every refresh regardless of authorization, so the
schedule stays correct the moment permission is granted. No request is added and nothing
delivered is swept while permission is anything but `.authorized` or `.provisional`.
`requestAuthorization()` is called only from an explicit "Enable notifications" button,
in `NotificationSettingsView` or the one-time `WelcomeView` (Onboarding `DESIGN.md`).
`isRequestingAuthorization` is true while it awaits the system alert, so the privacy
shield can stay down for it (App `DESIGN.md`). Launch, foreground, `scheduleChanged`,
`promptsDestroyed` and displaying the settings screen never call it. Manual journaling, survey editing,
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

Both delegate callbacks are written in the completion-handler form and resume on the
main actor before calling the handler. UIKit does main-thread-only work synchronously
inside those handlers (`-[UIApplication _updateSnapshotAndStateRestorationWithAction:
windowScene:]`), and asserts if it is not on the main thread. The shorter `nonisolated
async` form runs on the cooperative pool, so the compiler-synthesized `@objc` thunk calls
the handler from a background thread and that assertion becomes an uncaught
Objective-C exception: every tap killed the app with SIGABRT before any UI appeared,
which read as the notification bouncing back to the Home Screen. Do not go back to the
`async` form.

## Known limitations

- Notification answers cover the first question only, and only yes/no or a scale of up
  to five values; a spectrum (the default survey's first question) offers none.
- An answer action shows no question text: with the default `.private` preview the
  notification says only "Time for a check-in." above the buttons.
- An answer picked while the runner is open on the same entry is overwritten by the
  runner's next autosave (Storage `DESIGN.md`).
- A failed save is silent: the action has no UI to report it in. The prompt stays
  pending and can still be answered in the app.
- A delivered notification whose survey's first question changed keeps its old category,
  which loses its actions at the next refresh; an answer picked before then is refused
  as `unavailable`.
- iOS caps pending local notifications at 64 per app; `PromptPlanner.maxPending` (60)
  leaves headroom, shared across every survey, so a person running several
  high-frequency surveys sees a shorter horizon on each (see Sampling `DESIGN.md`).
- No background refresh: the schedule is only as fresh as the last foreground or
  schedule-affecting write.
- Unarchiving a survey (`Store.unarchiveSurvey`, from the editor's Archived screen)
  restores its scheduling when the saved configuration is enabled: an unarchived, enabled
  survey is eligible the same as any other. No coordinator test exercises that path yet.
