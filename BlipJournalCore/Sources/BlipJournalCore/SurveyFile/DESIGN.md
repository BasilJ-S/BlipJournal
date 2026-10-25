# SurveyFile

## Purpose

The reader and writer for the survey file format: one survey definition as JSON, written
by hand, by an AI assistant, or by the app, and imported as a new survey. The format is
specified in `docs/survey-format.md`, with a JSON Schema beside it; this folder is the
only code that reads or writes it. No UI and no file picking: the app hands over bytes,
text or a URL and shows the result. Imports `Foundation`; the import step goes through
`Store`.

```
SurveyFile.swift          SurveyFile (decode/encode), SurveyFileContents, SurveyFileError
SurveyFileReader.swift    validation into contents, FieldPath for issue locations
JSONValue.swift           untyped JSON tree, parsed with JSONDecoder, written in key order
Store+SurveyFile.swift    Store.importSurvey: fresh identifiers, paused, via createSurvey
SurveyTemplateGallery.swift  the bundled templates: file id, purpose, bundle URL
SurveyTemplate.swift      makeDefault: the survey a new install gets, read from a template
Templates/                the template survey files, a package resource (.copy)
```

## Flow

```
Data / pasted text / URL ─ SurveyFile.decode ─> Result<SurveyFileContents, SurveyFileError>
SurveyFileContents ─ Store.importSurvey ─> a new Survey (createSurvey, insert-only)
Survey ─ SurveyFile.encode ─> Data
```

## Invariants

- **Reading never writes.** `decode` is pure. Only `importSurvey` touches the store, and
  it only ever adds one survey through `createSurvey`, the same call the editor's blank
  and copied surveys use, so an imported survey has the same rows and version history as
  one built by hand.
- **Identifiers come from the app.** File `id`s are local names for `journalSummary` and
  are dropped. `decode` mints identifiers so contents can be previewed; `importSurvey`
  mints them again, so one decoded value can be imported twice (a double tap, the same
  file imported again, or a bundled template added twice) without a primary key clash.
- **Imports start paused** with the `.private` notification preview, like every new
  survey. The format has no field for either: when a phone buzzes is the person's
  choice, not the file author's.
- **Everything wrong is reported, nothing is guessed.** The reader collects every issue
  with a path (`questions[2].scale.max`), a location for people ("Question 3, scale,
  max") and a plain-language fix. Unknown fields are errors so a misspelt optional field
  cannot silently become its default. Rules that depend on a field, such as the scale
  range, are only checked once that field read cleanly, so one mistake does not cascade.
- **A newer `formatVersion` stops at once** with an "update Blip Journal" message: a
  newer file can have fields this build cannot judge.
- **Same rules as the editor.** Anything the editor can save, the writer can write and
  the reader accepts: empty question lists, choice questions with no options, repeated
  option labels, empty scale labels, and colours outside `0...1`. Blank question and
  option labels are refused here and by the editor alike. `encode` then `decode` gives back the same current
  definition, which the round-trip tests check.
- **Deterministic output.** `encode` writes keys in a fixed, readable order with
  two-space indentation, so the same survey always gives the same bytes and a protocol
  file diffs cleanly.

## Template gallery

- **Templates are survey files.** Each is a `.blipsurvey` in `Templates/`, read with
  `SurveyFile.decode(contentsOf:)` like a file from Files, so a template the reader
  rejects is a test failure, not a gallery bug. `SurveyTemplateGallery.templates` adds
  only what the format has no field for: the gallery order and a one-line purpose. The
  name, questions and schedule come from the file.
- **The default survey is a template.** `SurveyTemplate.makeDefault`, which seeds a new
  install and reseeds after erasing everything, reads `mood-and-feelings` through the
  same reader, so there is no second definition of the default to drift. A bundled file
  that does not read is a broken build, so it stops with `preconditionFailure` rather
  than making every caller handle an error no person can cause; the tests read it on
  every run.
- **Tests guard the set:** every listed file exists, reads, matches the schema and
  imports; every file in the folder is listed; each has 3 to 6 questions and a purpose;
  names differ; no wording stems from diagnosis, treatment or therapy. `SurveyTemplate`'s
  own tests pin the default survey's questions and options.
- **Wording is original.** No template takes items from a published item set. One that
  does must credit the source in its purpose, only from a source whose licence allows
  reuse.

## Decisions

- **One definition shape for files and copies.** `SurveyFileContents(survey)` is a
  survey's current definition; `encode` writes it and the editor's "Copy an existing
  survey" imports it under a new name, so copying and exporting cannot disagree about
  what a survey's definition is.

- **`decode` returns a `Result`.** Callers want `SurveyFileError` itself to list issues;
  a throwing API would hand them `any Error` and a cast.
- **A hand-rolled `JSONValue` instead of `Codable` models.** `Codable` stops at the first
  `DecodingError`, words it for programmers, and cannot tell an unknown key from a known
  one. Walking a parsed tree gives every issue at once with its path. Writing through the
  same tree controls key order; `JSONEncoder` sorts keys alphabetically or not at all.
- **Hand-friendly shapes.** Options are plain strings, times are `"HH:MM"`, colours may
  be `"#RRGGBB"`, and `expandable` names what the README calls an expandable choice list
  (`allowsCustomOptions` in the model). The writer uses the `{red, green, blue}` colour
  object because hex would round editor colours to 8 bits and break the round trip.
- **Defaults are the model's.** Absent fields take `SamplingConfig.default`,
  `ScaleConfig()`, `SpectrumConfig()` and `Survey.defaultJournalSummaryQuestionIds`, so
  the format and the editor cannot drift apart. Uncoloured zones blend along the default
  spectrum's colours; three of them get exactly the default three.
- **Pasted text is trimmed to the outermost braces**, so an assistant's reply can be
  pasted whole.

## Known limitations

- A `journalSummary` id that names a question which itself failed to read is reported as
  unknown as well.
- Duplicate keys in one object are not reported; `JSONDecoder` keeps one of them.
- The schema checks shape only; the cross-field rules live in `SurveyFileReader` and are
  listed in the spec. The schema test uses a small validator in the test target that
  supports only the keywords the schema uses.
