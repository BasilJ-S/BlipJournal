# Settings

## Purpose

The Settings tab is a list of rows, each a `NavigationLink` to one screen. `SettingsView`
is owned by A1 and is not meant to change again: later tasks replace the destination
files, not this list.

## Rows, in order

| Row | Destination | Owner |
|---|---|---|
| Surveys | `Survey/Editor/SurveyListView` | A4 |
| Notifications | `Notifications/NotificationSettingsView` | A2 |
| Export | `Settings/ExportView` | A6 |
| Delete all data (destructive style) | `Settings/DeleteAllDataView` | A6 |
| About | `Settings/AboutView` | A6 |

Every destination takes `init()` and reads `AppModel` from the environment.

## Known limitations

- "Delete all data" is styled red but is a plain link; the confirmation and the call to
  `Store.eraseEverything` belong to A6.
