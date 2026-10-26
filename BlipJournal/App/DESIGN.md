# App

Owns launch, the shared `AppModel`, authentication, and the three-tab root.
`AppModel.live()` opens Application Support/BlipJournal with Store's complete iOS
Data Protection; this is filesystem encryption, not SQLCipher.

- `AppModel` is main-actor observable state: Store, coordinator, active surveys,
  all surveys by ID, entries newest first, lock state, and a refresh revision.
  Call `refresh()` after writes; the revision invalidates answer-derived views
  even when an entry's metadata stays equal.
- Seed the default template only when there are no surveys, archived included.
- `AppModel.live()` sets the coordinator's `onEntrySaved` to `refresh()`, so an answer
  saved from a notification while the app runs appears at once, then attaches the
  coordinator to the notification delegate. `AppDelegate` sets that delegate and nothing
  else; categories belong to the coordinator (Notifications `DESIGN.md`).
- `LockPolicy` locks every cold launch and after >= 30 seconds in background.
  Foreground also asks the notification coordinator to refresh.
- `LockView` uses device-owner authentication with passcode fallback.
  `DeviceAuthentication` permits “Continue anyway” only for the explicit
  `LAError.passcodeNotSet` error; all other errors offer retry.
- The lock replaces the root so sheets cannot sit above it. Relocking discards
  navigation and sheets. The future runner must autosave before this happens.
- `PrivacyShield` puts a separate window holding only the mark above everything when the
  scene leaves `.active` while unlocked; that is what the app-switcher snapshot captures.
  A window rather than an overlay so open sheets are covered too; covering rather than
  locking keeps them, and any draft, in place. Showing it also ends text editing, since
  the keyboard's window sits above any app window and its suggestions come from typing.
- It stays down while `notifications.isRequestingAuthorization`: the permission alert
  makes the scene inactive, and covering the screen would hide the explanation the alert
  follows. Control Centre and other system alerts still raise it briefly.
- On `.active`, the lock policy runs first. Without a relock the shield comes down at
  once; on a relock it comes down from `onChange(of: isLocked)`, together with
  `LockView` replacing the root, so the old content never flashes.
- `RootView` presents the one-time `WelcomeView` (Onboarding `DESIGN.md`).
- `onOpenURL` reads a survey file handed over by another app into
  `AppModel.pendingSurveyImport`, even while locked; `RootView` previews it once unlocked,
  after the welcome and any prompt sheet (Survey/SurveyFile `DESIGN.md`).
- Launch store errors remain fatal with their error text, as required by A1.
  DEBUG logs the directory protection class; verify encryption on a device.

Extension points (fixed signatures in the A1 handoff):

| File | Owner |
|---|---|
| Survey/Runner/SurveyRunnerView | A3 |
| Survey/Editor/SurveyListView | A4 |
| Notifications/NotificationCoordinator, NotificationSettingsView | A2 |
| Insights/InsightsView | A5 |
| Settings/ExportView, DeleteAllDataView, AboutView | A6 |

Known limits: refresh eagerly reads all entries on the main actor; no notification
routing until A2/A3. Simulator storage
does not establish device Data Protection. Visible product name is Blip Journal.
