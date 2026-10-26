# Survey file format

A survey file holds one Blip Journal survey: its name, questions, options, sampling
schedule and Journal summary. It is plain JSON, short enough to write by hand, and
regular enough for an AI assistant to write from a description. Every way a survey
enters the app from outside goes through this format: files you write, files a
researcher shares so every participant answers the same protocol, and text you paste.
The survey templates offered under New survey, including the survey a new install
starts with, are survey files too: they ship inside the app and are read the same way.

A survey file never holds answers, and importing one never changes anything already in
the app: it always adds a new survey. A JSON backup is a different file: it holds
everything, answers included, and is restored under Settings, Restore from backup.

- **Extension:** `.blipsurvey` for files Blip Journal writes. Blip Journal also opens
  `.json` files. Both are the same JSON; rename one to the other freely.
- **Schema:** [`survey-format.schema.json`](survey-format.schema.json) (JSON Schema
  2020-12). Add
  `"$schema": "https://raw.githubusercontent.com/BasilJ-S/BlipJournal/main/docs/survey-format.schema.json"`
  to a file to get checking and completion in an editor that supports it. The schema checks the shape; Blip Journal also checks rules
  that span fields, listed under [Validation](#validation).
- **Current version:** `formatVersion` 1.

## Complete example

<!-- complete-example: a test imports this block and validates it against the schema -->
```json
{
  "formatVersion": 1,
  "name": "Evening energy study",
  "sampling": {
    "promptsPerDay": 4,
    "windowStart": "08:00",
    "windowEnd": "22:00",
    "minGapMinutes": 90,
    "expiryMinutes": 30
  },
  "journalSummary": ["energy", "doing"],
  "questions": [
    {
      "id": "energy",
      "kind": "scale",
      "label": "How much energy do you have right now?",
      "required": true,
      "scale": { "min": 1, "max": 5, "minLabel": "None", "maxLabel": "Plenty" }
    },
    {
      "kind": "spectrum",
      "label": "How are you feeling right now?",
      "spectrum": {
        "zones": [
          { "label": "Unpleasant", "color": "#D94040" },
          { "label": "Pleasant", "color": "#4DB366" }
        ]
      }
    },
    {
      "id": "doing",
      "kind": "singleChoice",
      "label": "What are you doing?",
      "expandable": true,
      "options": ["Working", "Commuting", "Eating", "Resting", "Exercising"]
    },
    {
      "kind": "multiChoice",
      "label": "Who are you with?",
      "options": ["Alone", "Partner", "Family", "Friends", "Colleagues"]
    },
    {
      "kind": "yesNo",
      "label": "Have you had caffeine in the last two hours?"
    },
    {
      "kind": "text",
      "label": "Anything else?"
    }
  ]
}
```

The smallest valid file is a name and a list of questions:

```json
{
  "formatVersion": 1,
  "name": "Water",
  "questions": [{ "kind": "yesNo", "label": "Have you had a glass of water this hour?" }]
}
```

## Fields

Field names are case sensitive. A field Blip Journal does not know is an error rather
than being ignored, so a misspelling such as `"requried"` is caught instead of quietly
falling back to a default.

### Survey (the top level)

| Field | Type | Default | Allowed values |
|---|---|---|---|
| `formatVersion` | whole number | required | `1` |
| `name` | text | required | not blank |
| `questions` | list of [questions](#question) | required | in the order they are asked; may be empty |
| `sampling` | [sampling](#sampling) | every sampling default | |
| `journalSummary` | list of text | the first scale or spectrum question, if any | up to two question `id`s, no repeats; `[]` for none |
| `$schema` | text | none | any; ignored by Blip Journal |

### Question

| Field | Type | Default | Allowed values |
|---|---|---|---|
| `kind` | text | required | `scale`, `spectrum`, `singleChoice`, `multiChoice`, `yesNo`, `text` |
| `label` | text | required | not blank |
| `id` | text | none | not blank, different for each question. Only `journalSummary` uses it. |
| `required` | true or false | `false` | whether a check-in cannot be finished without an answer |
| `expandable` | true or false | `false` | `singleChoice` and `multiChoice` only: new options can be added while answering |
| `options` | list of text | `[]` | `singleChoice` and `multiChoice` only: not blank, in display order |
| `scale` | [scale](#scale) | every scale default | `scale` only |
| `spectrum` | [spectrum](#spectrum) | the pleasantness spectrum | `spectrum` only |

What each kind asks for:

- `scale`: a whole number in a range, such as 1 to 5.
- `spectrum`: a position on a slider between two ends, with each stretch of it named.
- `singleChoice`: exactly one option.
- `multiChoice`: any number of options, including none.
- `yesNo`: yes or no.
- `text`: a short note, up to 500 characters.

`expandable`, `options`, `scale` and `spectrum` on a kind they do not belong to are
errors.

### Scale

| Field | Type | Default | Allowed values |
|---|---|---|---|
| `min` | whole number | `1` | -100 to 100, below `max` |
| `max` | whole number | `7` | -100 to 100, above `min` |
| `minLabel` | text | `"Very unpleasant"` | any, may be empty |
| `maxLabel` | text | `"Very pleasant"` | any, may be empty |

### Spectrum

Without a `spectrum` field, a spectrum question uses "Very unpleasant", "Neutral" and
"Very pleasant" in equal thirds.

| Field | Type | Default | Allowed values |
|---|---|---|---|
| `zones` | list of [zones](#zone) | required | at least two, left to right |
| `breakpoints` | list of numbers | equal zones | one fewer than the zones, each between 0 and 1 (not 0 or 1), increasing. The slider runs from 0 on the left to 1 on the right. |

### Zone

| Field | Type | Default | Allowed values |
|---|---|---|---|
| `label` | text | required | not blank |
| `color` | text or object | a blend from red through yellow to green | `"#RRGGBB"`, or `{ "red": 0.85, "green": 0.25, "blue": 0.25 }` with numbers usually from 0 to 1 |

Files Blip Journal writes use the object form, because it keeps any colour picked in the
editor exactly.

### Sampling

| Field | Type | Default | Allowed values |
|---|---|---|---|
| `promptsPerDay` | whole number | `3` | 0 to 20 |
| `windowStart` | text | `"09:00"` | `"HH:MM"`, 24-hour, before `windowEnd` |
| `windowEnd` | text | `"23:00"` | `"HH:MM"`, 24-hour, after `windowStart`; `"24:00"` is midnight at the end of the day |
| `minGapMinutes` | whole number | `60` | 0 to 1440; 0 means no minimum |
| `expiryMinutes` | whole number | `20` | 1 to 240: how long a prompt can be answered |

The prompts must fit in the window with their gaps: `(promptsPerDay - 1) * minGapMinutes`
must be shorter than the window.

## Importing

Open a file from the Files app, tap it in Mail or Messages and choose Blip Journal, or
paste its text under Settings, Surveys, +. Blip Journal shows the survey's questions and
schedule before adding anything; nothing changes until you tap Add survey.

- Blip Journal gives every question and option its own new identifier; the file's `id`s
  are not kept. Importing the same file twice gives two separate surveys.
- An imported survey starts with notifications **paused** and a private notification
  preview, the same as any new survey. Turn it on under Sampling once you have looked it
  over. A survey file never decides when your phone buzzes on its own.
- Pasted text may include other words around the JSON, such as an assistant's reply or a
  Markdown code block: everything before the first `{` and after the last `}` is
  ignored.

## Exporting

Open a survey under Settings, Surveys and tap Share survey file. The file holds the
survey's current questions and options in order, its schedule and its Journal summary.
It never holds answers, archived questions or options, whether notifications are on, or
the notification preview. Questions get the ids `q1`, `q2` and so on. Importing the file
gives back the same survey.

## Validation

When a file cannot be imported, Blip Journal lists every problem it found, each with
where it is (such as "Question 3, scale") and what to change, and adds nothing. Besides
the shape the schema describes, it checks:

- The file is a survey file and not a JSON backup. A backup is named as one, with a
  pointer to Settings, Restore from backup.
- The `formatVersion` is one it reads. A file from a newer version of Blip Journal is
  refused with a request to update the app, without checking anything else.
- Each question `id` appears once, and each `journalSummary` entry names one of them.
- A scale's `min` is below its `max`.
- A spectrum has one fewer breakpoint than zones, and they increase.
- The window ends after it starts, and the prompts fit in it with their gaps.

## Versions

`formatVersion` changes whenever the format does, including when a field is added,
because a version of Blip Journal that does not know a field refuses it rather than
dropping it. Blip Journal reads every version up to the one it writes.

| Version | Changes |
|---|---|
| 1 | First version. |

## Writing a survey with an AI assistant

Blip Journal has no AI features and makes no network calls. You can still describe a
survey in your own words to any AI assistant and import what it writes. Copy the prompt
below, replace the last line with your description, and paste the assistant's reply into
Blip Journal under Settings, Surveys, +, Paste survey text. Check the preview before you
add it.

<!-- ai-prompt: a test imports the example inside this prompt -->
```text
Write a Blip Journal survey file for the survey I describe at the end. Reply with only
the JSON, no explanation.

Rules for the file:
- One JSON object with "formatVersion": 1, "name" (text) and "questions" (a list).
- Each question has "kind" and "label". kind is one of: "scale" (a whole number in a
  range), "spectrum" (a slider between named zones), "singleChoice" (pick one option),
  "multiChoice" (pick any options), "yesNo", "text" (a short note).
- Optional on any question: "required" (true or false, default false), "id" (a short
  name, only needed to list the question in journalSummary).
- singleChoice and multiChoice: "options", a list of labels, and optionally
  "expandable": true to let new options be added while answering.
- scale: optionally "scale" with "min" and "max" (whole numbers from -100 to 100, min
  below max) and "minLabel" and "maxLabel" (text). Default 1 to 7.
- spectrum: optionally "spectrum" with "zones", a list of at least two objects with a
  "label", left to right, each optionally with a "color" like "#D94040".
- Optional "sampling" with "promptsPerDay" (0 to 20, default 3), "windowStart" and
  "windowEnd" (24-hour "HH:MM", default "09:00" and "23:00"), "minGapMinutes" (default
  60) and "expiryMinutes" (1 to 240, default 20). The prompts must fit in the window
  with the gaps between them.
- Optional "journalSummary": a list of up to two question ids whose answers show in the
  journal list.
- Use no other fields. Leave out anything my description does not mention.

Example of the format:
{
  "formatVersion": 1,
  "name": "Focus check",
  "sampling": { "promptsPerDay": 5, "windowStart": "09:00", "windowEnd": "18:00" },
  "journalSummary": ["focus"],
  "questions": [
    { "id": "focus", "kind": "scale", "label": "How focused are you?", "required": true,
      "scale": { "min": 1, "max": 5, "minLabel": "Scattered", "maxLabel": "Locked in" } },
    { "kind": "singleChoice", "label": "Where are you?", "expandable": true,
      "options": ["Home", "Office", "Cafe"] },
    { "kind": "text", "label": "What is distracting you?" }
  ]
}

My survey: <describe your survey here: what to ask, how often, and between which hours>
```
