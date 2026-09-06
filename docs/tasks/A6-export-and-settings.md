# Task A6: Export, Delete all data, About

Implementation handoff for `OpenBlip/Settings/` (three stub files). Read `AGENTS.md`, the
"Export formats" section of `README.md`, the A6 section of `docs/PLAN.md`,
`OpenBlipCore/Sources/OpenBlipCore/Export/DESIGN.md`, `Storage/DESIGN.md` (backup and
`eraseEverything`), and `OpenBlip/App/DESIGN.md`. Requires A1 on `main`. Do not modify
`OpenBlipCore/`, `SettingsView.swift`, or files outside the three stubs, a new
`Settings/ExportModel.swift`, `Settings/DESIGN.md`, and `OpenBlipTests/Settings/`.

## Goal

Replace three A1 stubs: `ExportView`, `DeleteAllDataView`, `AboutView`, each `init()`
reading `AppModel` from the environment. Export writes a CSV or JSON backup to a file
and hands it to the share sheet; Delete all data erases everything with the strongest
confirmation in the app; About shows version, licence, and the repository link.

## Branch and delivery

Branch from `main`: `a6-export-settings`. Draft PR when done. `xcodebuild` build and test
against the iPhone 17 Pro simulator, zero app-target warnings.

## ExportModel

```swift
@MainActor @Observable final class ExportModel {
    enum Format: CaseIterable { case wideCSV, longCSV, jsonBackup }
    init(store: Store, calendar: Calendar = .autoupdatingCurrent, fileManager: FileManager = .default)
    var surveys: [Survey]            // includeArchived: true; archived shown with a suffix
    var selectedSurveyId: String?    // nil allowed only for jsonBackup, which is whole-database
    var format: Format
    func makeFile(now: Date = Date()) throws -> URL     // writes and returns the file
    func cleanUp()                                       // removes every file this model wrote
}
```

- Files go in `Application Support/OpenBlip/exports/`, a subdirectory of the protected
  store directory so they inherit the `complete` protection class. Create it with the
  same attributes as `Store.open` uses. `cleanUp` deletes the directory's contents; call
  it when the share sheet dismisses and on `ExportView` disappear.
- File names: `OpenBlip-<survey name slug>-<yyyyMMdd>-wide.csv`, `...-long.csv`,
  `OpenBlip-backup-<yyyyMMdd>.json`. Slug: lowercase, non-alphanumerics to `-`, max 40
  characters.
- CSV files are UTF-8 **with** a byte-order mark, so Excel opens them correctly. JSON has
  no BOM. Document this in `DESIGN.md`; the core exporter deliberately leaves the BOM
  decision to the app.
- `jsonBackup` uses `store.backup(now:)` then `BackupExporter.json`.

## ExportView

Survey picker (hidden for JSON backup), format picker with one line describing each
format, a warning paragraph that is always visible:

> Exported files are not encrypted. Anyone with the file can read your answers.

Then a `ShareLink(item: url)` created from `makeFile()`; errors show as an alert. A
footer says where the JSON backup can be used (a future import) and that CSV opens in
Numbers and Excel.

## DeleteAllDataView

A screen, not just an alert, so it is never reached by accident. Text explaining what
goes: every survey, every answer, every prompt, and the schedule; the app returns to
its first-launch state with the default survey. A single destructive "Delete all data"
button opens a confirmation dialog:

> Delete all data permanently. This erases N entries, M surveys, and every prompt.
> It cannot be undone. Exported files on other devices are not affected.

Counts come from the store (entries across all surveys, surveys including archived).
Confirm: `store.eraseEverything()`, then `await appModel.notifications.promptsDestroyed(now:)`,
then `appModel.refresh()`, then pop to the Settings root and show a short banner
"All data deleted." No typed confirmation string.

## AboutView

App name, version and build from the bundle, one paragraph on what OpenBlip is (no
medical claims), the licence (MIT, with the full text in a disclosure group), a link to
`https://github.com/BasilJ-S/OpenBlip`, and a line stating that the app makes no network
requests and collects no data. Opening the link hands off to Safari; that is the user's
action, not a network call by the app.

## Tests

`OpenBlipTests/Settings/ExportModelTests.swift` on `Store.inMemory()` with a temporary
directory injected in place of Application Support (make the base directory an `init`
parameter with the real one as default):

- Wide CSV file starts with the BOM and the header row from `CSVExporter.wide`.
- Long CSV likewise. JSON backup has no BOM and decodes with `BackupExporter.decode`.
- File names follow the pattern and slugging strips punctuation.
- `cleanUp` leaves the exports directory empty.
- `makeFile` for an unknown survey throws.

## Acceptance

- Build and tests pass, zero app-target warnings.
- Exported wide CSV opens in Numbers with correct columns; the file is gone from the
  exports directory after the share sheet closes.
- Delete all data leaves the app with one default survey, no entries, and no pending
  notification requests (A2 must be merged to check the last part; otherwise verify the
  store).
- `Settings/DESIGN.md` updated (A1 created it): the export file rules, the BOM decision,
  the delete-all sequence, and known limitations (no import, no partial export by date).

## Out of scope

Import, per-date-range export, iCloud, anything outside `Settings/`.
