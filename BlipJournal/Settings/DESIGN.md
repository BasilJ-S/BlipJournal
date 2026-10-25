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
| Tip jar | `Settings/TipJarView` | #37 |
| About | `Settings/AboutView` | A6 |

Every destination takes `init()` and reads `AppModel` from the environment when it needs
app state.
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

Pick a JSON file, compare it with the phone (date, survey and entry counts), optionally
"Save a backup of current data", then Replace. Nothing is written until Replace; skipping
the save asks a second "Are you sure?" (`RestoreBackupModel.needsLossConfirmation`). The
save step is `ExportModel` in JSON backup mode behind the shared `shareSheet` modifier;
the reset after a restore is `DeleteAllDataModel.reset`, shared with delete-all. How the
restore itself works is in Storage `DESIGN.md`.

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

## Tip jar

Three consumable In-App Purchases, `io.github.basilj-s.BlipJournal.tip.small|medium|large`,
listed in `TipJarModel.productIDs` and mirrored in `TipJar.storekit`. The Run scheme uses
that file for local testing, and only the test target bundles it, for the `SKTestSession`
tests; the app never ships it. They are the app's only purchases, and a tip unlocks,
stores and logs nothing, so the privacy manifest is unchanged.

- The screen loads products with StoreKit 2 each time it appears and shows Apple's
  `displayPrice`, never a hard-coded price. No products or a load error shows "Tips are
  unavailable right now."; nothing else in the app depends on StoreKit.
- Purchases go through SwiftUI's `PurchaseAction`. Success shows a thank-you; pending
  (Ask to Buy) and failure show a short note; a cancellation shows nothing.
- Every transaction is finished and thanked, verified or not: the person has paid, there
  is nothing to withhold, and an unfinished one would come back at every launch.
- `AppDelegate` starts `TipJarModel.listenForTransactions()` at launch, which finishes
  Ask to Buy approvals and anything left unfinished.
- Nothing else in the app mentions tips: no prompts, badges or banners.

## Known limitations

- Restore replaces and never merges; JSON backups cannot be date-filtered. "Saved" means the share sheet reported a completed action, which includes sharing to an app, not only Save to Files.
