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
| Restore from backup | `Settings/RestoreBackupView` | #38 |
| Delete all data (destructive style) | `Settings/DeleteAllDataView` | A6 |
| About | `Settings/AboutView` | A6 |

Every destination takes `init()` and reads `AppModel` from the environment.
All Settings destinations hide the system List/Form canvas so the shared paper background
continues below the navigation bar.

## A6 behaviour

CSV exports are UTF-8 with a byte-order mark for Excel compatibility. JSON backups have
no BOM and always contain the complete database; date filtering applies only to CSV.
Temporary exports live in protected `Application Support/BlipJournal/exports/` and are
removed when sharing ends or the export screen disappears.

Delete-all erases and reseeds in the store transaction, asks the notification coordinator
to remove pending and delivered prompts, clears its pending route, refreshes the app, and
reports that notifications are paused. iOS notification authorization is not revoked.

## Restore from backup

Replaces the database with a JSON backup. Flow: pick a file (`fileImporter`, JSON), core
decodes and checks it (`BackupExporter.decodeForRestore`; unreadable or newer-schema files
are refused with a plain message and nothing changes), the screen shows the backup's date
and survey and entry counts beside the phone's and says everything will be replaced, then
the person may "Save a backup of current data" (recommended, primary) or replace. Nothing
is written until Replace. If they replace without having completed the share sheet on this
screen, a second "Are you sure?" alert says current data will be lost.

The save step is `ExportModel` in JSON backup mode and the shared `ActivityView`, so the
file, its protection and its temporary-file clean-up are the Export screen's, not copies.
After a restore, `DeleteAllDataModel.reset` (shared with delete-all) removes pending and
delivered prompt notifications, reschedules from the restored surveys, clears the
notification route and refreshes every screen. The app keeps no safety copy of its own.

## About

Shows the version and build from the bundle, the app's MIT licence, and
acknowledgements: GRDB.swift's MIT notice, and the SIL Open Font License for Nunito and
JetBrains Mono, read from the bundled `Brand/Fonts/OFL.txt` so it is not duplicated.
Both licences require their notices to ship with the app.

Licence text flows to the screen width. The inline MIT and GRDB strings use `\` line
continuations. `OFL.txt` stays verbatim in the bundle and is reflowed for display by
`LicenceText.reflowed`: lines within a paragraph join, blank-line breaks stay, dash rules
go, and headings and `Copyright <year>` lines keep their own line. Only line breaks
move, never words, which its tests check.

## Known limitations

- Restore replaces and never merges; JSON backups cannot be date-filtered. "Saved" means the share sheet reported a completed action, which includes sharing to an app, not only Save to Files.
