# App

Owns launch, the shared `AppModel`, authentication, and the three-tab root.
`AppModel.live()` opens Application Support/BlipJournal with Store's complete iOS
Data Protection; this is filesystem encryption, not SQLCipher.

- `AppModel` is main-actor observable state: Store, coordinator, active surveys,
  all surveys by ID, entries newest first, lock state, and a refresh revision.
  Call `refresh()` after writes; the revision invalidates answer-derived views
  even when an entry's metadata stays equal.
- Seed the default template only when there are no surveys, archived included.
- `LockPolicy` locks every cold launch and after >= 30 seconds in background.
  Foreground also asks the notification coordinator to refresh.
- `LockView` uses device-owner authentication with passcode fallback.
  `DeviceAuthentication` permits “Continue anyway” only for the explicit
  `LAError.passcodeNotSet` error; all other errors offer retry.
- The lock replaces the root so sheets cannot sit above it. Relocking discards
  navigation and sheets. The future runner must autosave before this happens.
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
routing until A2/A3; the app-switcher snapshot is not obscured. Simulator storage
does not establish device Data Protection. Visible product name is Blip Journal.
