# Blip Journal

An open source Experience Sampling Method (ESM) journal for iOS. Blip Journal pings you
at random moments during the day and asks a short, fully customisable survey. Every
answer stays on your phone, encrypted at rest, and can be exported to CSV at any time.

Think of Apple's State of Mind logging, but with random sampling, surveys you define
yourself, and no cloud.

## Name

The app is **Blip Journal**. The repository, the Swift package, the Xcode target and the
bundle identifier are all `OpenBlip`, and they stay that way: they are plumbing, not
branding, and renaming a shipped bundle identifier is impossible.

"Open" as a prefix reads as "open weights" or "open standard" (OpenAI, OpenCV), which is
not what this is. The App Store subtitle carries the open source signal explicitly, and
it is searchable in a way a prefix never was. Subtitle: "Open source experience sampler"
(30 characters, the App Store limit exactly).

Any string a person reads says Blip Journal. Anything a compiler, a path, or Apple reads
says OpenBlip.

**Status:** pre-alpha. Nothing ships yet. See [docs/PLAN.md](docs/PLAN.md) for the build plan.

## Goals for v0

- **Random sampling.** Each survey has its own schedule: prompts per day, a daily
  window, a minimum gap between prompts, and an expiry. Prompts are stratified random
  within the window so they are unpredictable but never clump.
- **Customisable surveys.** Arbitrarily many surveys. Each is a list of questions:
  scale, single choice, multiple choice, yes/no, or short text. Choice lists are
  expandable in place while answering.
- **Fast.** A prompt should take under 30 seconds to answer. One scrolling screen, big
  tap targets, autosave, no confirmation step.
- **Local and encrypted.** SQLite on device, protected with iOS Data Protection
  (`complete` class). Face ID or passcode to open the app. No network access at all.
- **Exportable.** CSV in wide and long formats, plus a JSON backup that includes survey
  definitions.
- **Honest data.** Unprompted (manual) entries are tagged as such. Expired prompts are
  recorded as missed so compliance is visible.
- **Yours to erase.** Delete a single entry, permanently erase anything you have archived
  along with every answer to it, or wipe everything from Settings. Erasing overwrites the
  data in the database rather than merely unlinking it.
- **Built-in charts.** Mood over time, by hour, by weekday, by activity or impact, and
  compliance rate.
- **App Store compliant.** Privacy manifest, "Data Not Collected" privacy label, no
  medical claims, Apple-provided encryption only.

## Non-goals for v0

- Cloud sync, accounts, or any network feature.
- Dark mode. Light mode only, forced.
- Conditional or branching questions.
- HealthKit integration (planned for v1 via the State of Mind API).
- Statistical analysis beyond descriptive charts.
- Import of backups (export only in v0).

## Platform

- iOS 26.0 minimum. Swift 6, SwiftUI, Swift Charts.
- Xcode 26. The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
  from `project.yml` and is not committed.
- One third-party dependency: [GRDB.swift](https://github.com/groue/GRDB.swift) for SQLite.

## Architecture

Three subsystems, split across two targets.

```
OpenBlipCore/        Swift package. No UIKit. Tested with `swift test` on macOS.
  Model/             Domain types: Survey, Question, Option, Prompt, Entry, Answer
  Storage/           GRDB schema, migrations, insert-only versioning, queries
  Sampling/          Stratified random day sampler and multi-survey prompt planner
  Export/            CSV (wide, long) and JSON backup
OpenBlip/            iOS app target. SwiftUI only.
  App/               Entry point, app model, biometric lock
  Notifications/     UNUserNotificationCenter adapter for the prompt planner
  Survey/            Survey runner (answering) and survey editor
  Insights/          Swift Charts views
  Settings/          Surveys, sampling, export, about
```

### Storage subsystem

- SQLite via GRDB. The database lives in a dedicated directory whose protection class is
  `NSFileProtectionComplete`, so the WAL and journal files inherit it.
- **Insert-only definitions.** Surveys, questions, and options each have a stable ID and
  a separate version table. Renaming a label, reordering, changing a scale range, or
  archiving inserts a new version row. Editing never updates or deletes a definition row.
  The current definition is the newest version row.
- **Archiving, then erasing.** Removing a question or an option archives it: it leaves the
  survey you answer, and past answers still resolve to the wording you saw at the time.
  Archived things are listed on their own screen, and from there you can permanently erase
  one, which deletes it and every answer to it outright. That is the one place the app
  deletes a definition, it only ever acts on something already archived, and it tells you
  exactly what will go before it goes. Individual entries can be deleted from the Journal,
  and Settings has a "Delete all data" action.
- **Erasure means the bytes.** The database runs with `secure_delete` on, and every
  erasure checkpoints the write-ahead log and vacuums, so the removed rows are not left
  sitting in free pages or in the log. What no app can promise is erasure from the flash
  storage underneath, because wear levelling is outside its control; iOS Data Protection
  is what covers that residue.
- Answers reference the question ID, the question version ID, and option IDs, never the
  label text. Exports can therefore show either the label at the time of the answer or
  the current label.
- Migration to SQLCipher is a documented upgrade path, not a v0 feature.

### Notification subsystem

- iOS caps pending local notifications at 64 per app. The planner keeps at most 60
  prompts pending across all surveys and computes its horizon as
  `min(7 days, 60 / total prompts per day)`.
- Every time the app comes to the foreground: expire overdue prompts, generate prompts
  for any day inside the horizon that has none yet, persist them, then reconcile the
  notification center so it holds exactly the pending prompts.
- Sampling per survey per day: split the window into N equal blocks, choose one uniform
  random time per block, enforce the minimum gap. Times are rounded to the minute.
- Changing a survey's schedule discards that survey's future pending prompts and
  regenerates them.
- Prompts use the time-sensitive interruption level so they break through Focus.
- A prompt opened after its expiry is logged as missed and the user is offered a manual
  entry instead.

### UI subsystem

- **Runner.** Renders any survey definition on one scrolling screen. Scale as a
  labelled slider or segmented control, choices as tappable chips with an inline
  "add option" chip, yes/no as two buttons, text as a single-line field. Saves on every
  change; "Done" is always visible.
- **Editor.** Add, rename, reorder, and archive questions and options. Per-survey
  sampling settings. All edits go through the versioning API.
- **Lock.** Face ID with passcode fallback on launch and after returning from background.
- **Insights.** Swift Charts over the store's query layer.

### Defaults

| Setting | Default |
|---|---|
| Prompts per day | 3 |
| Window | 09:00 to 23:00 |
| Minimum gap | 60 min |
| Expiry | 20 min |

Default survey, all questions optional except the first:

1. How are you feeling right now? Scale 1 to 7, "Very unpleasant" to "Very pleasant".
2. What best describes this feeling? Multiple choice.
3. What is having the biggest impact? Multiple choice, expandable.
4. What are you doing? Single choice, expandable.
5. Who are you with? Multiple choice, expandable.
6. Anything else? Short text.

## Export formats

- **Wide CSV.** One row per entry. Columns: entry metadata (survey, prompted or manual,
  prompt time, completion time, latency) then one column per question using current
  labels. Multi-choice cells join selected labels with `; `.
- **Long CSV.** One row per answer, or per selected option for choice questions. Includes
  question ID, question kind, label at time of answer, current label, option ID, option
  label at time of answer, current option label, and the raw value.
- **JSON backup.** Every table, including version history, with a schema version number.

Exported files are not encrypted. The app says so before sharing.

## App Store compliance checklist

- `PrivacyInfo.xcprivacy` declaring no tracking and no collected data.
- `ITSAppUsesNonExemptEncryption = NO` (Apple-provided encryption only).
- `NSFaceIDUsageDescription` present. Permission prompts are preceded by an explanation.
- No diagnostic, treatment, or therapy claims anywhere in the app or listing.
- Dynamic Type and VoiceOver labels on all controls.
- MIT license (GPL is incompatible with App Store distribution).

## Building

```
brew install xcodegen
xcodegen generate
open OpenBlip.xcodeproj
```

Core package only, no Xcode required:

```
cd OpenBlipCore && swift test
```

## Contributing

All changes require approval from the maintainer ([@BasilJ-S](https://github.com/BasilJ-S)).
Open a pull request against `main`; direct pushes are not accepted. Read `AGENTS.md` first.

## License

MIT. See [LICENSE](LICENSE).
