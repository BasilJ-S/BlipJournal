# Survey files (app)

Import and export of survey files, the format in `docs/survey-format.md`. Reading,
validating, writing and the import itself are BlipJournalCore's `SurveyFile`; this
folder only gets bytes in and out and shows the result.

- **Ways in.** Surveys, + menu: "Import a survey file" (`fileImporter`, `.blipsurvey`
  or `.json`) and "Paste survey text". "Open in Blip Journal" from Files, Mail or a
  share sheet arrives as `onOpenURL` in `BlipJournalApp`, is read at once into
  `AppModel.pendingSurveyImport`, and `RootView` presents it once unlocked, after the
  welcome and after any prompt sheet. All three end as a `PendingSurveyImport`
  shown by `SurveyImportSheet`; `PendingSurveyImport(fileAt:)` is also the path for
  bundled template files (`Survey/Gallery`), which pass `onAdded` to hear that a survey
  was added.
- **Nothing changes before confirming.** The sheet shows the preview (name, schedule,
  each question with its kind, options or range, and the Journal summary) and only Add
  survey writes, through `EditorModel.importSurvey`. A file that fails shows every issue
  as location and message, and "Nothing was added".
- **Way out.** The survey editor's "Share survey file" is a `ShareLink` over
  `SurveyFileDocument`, a `Transferable` that writes `SurveyFile.encode` as
  `<survey name>.blipsurvey`. No temporary file to clean up; it holds no answers.
- **File type.** `UTType.blipSurvey` (`io.github.basilj-s.BlipJournal.survey`, conforms
  to `public.json`) is exported in Info.plist and `project.yml`, with Blip Journal as
  owner of `.blipsurvey` and an alternate handler for `.json`.
  `LSSupportsOpeningDocumentsInPlace` is true: files are read inside their security
  scope and never copied into the app.

Known limitations: a survey file opened while a prompt sheet appears is dropped when
that sheet takes over, and must be opened again. One opened while another sheet is up
inside a tab (the paste sheet, a new question) waits in `pendingSurveyImport` but SwiftUI
may not present it until something else changes; opening it again works. Files are read
on the main actor, which is fine for a survey but noticeable for a large backup opened
by mistake. There is no in-app copy of the AI
prompt; it lives in the spec.
