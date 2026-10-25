# Survey template gallery

`TemplateGalleryView` lists the premade surveys bundled with the app, then **Blank
survey**. The templates, their purposes and their tests live in BlipJournalCore's
`SurveyFile` (`SurveyTemplateGallery`); this folder only shows them.

- **One importer.** Each template is read with `PendingSurveyImport(fileAt:)`, the path a
  file from Files takes, and tapping one opens the same `SurveyImportSheet` preview:
  name, schedule and every question. Nothing is added until Add survey, and the result
  is an ordinary survey, paused, with fresh identifiers, editable like any other.
- **Rows** show the survey's name, the one-line purpose, and its question count and
  schedule, read from the file. Templates are read once per launch; they cannot change
  while the app runs.
- **Blank** asks for a name and creates an empty, paused survey through
  `EditorModel.createSurvey`, as the Surveys + menu's Blank survey does.
- **Where it appears.** Settings → Surveys → + → Start from a template, in a sheet that
  closes once a survey is added; and once, as the second step of the welcome
  (Onboarding `DESIGN.md`), which leaves out the mood and feelings template.
- `onAdded` runs from the preview sheet's `onDismiss`, not while it is closing, so the
  preview and the gallery's own container never dismiss at the same moment.

Known limitations: a template that fails to read (only possible with a broken build, and
caught by the core tests) shows its file id as its name and opens the preview's list of
problems. The preview calls it "Import survey".
