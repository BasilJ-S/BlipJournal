# Editing

`QuestionEditDraft` holds question fields until Save question. `load` initializes once
per question ID; reloading that same question after an option mutation preserves pending
fields. Switching IDs initializes the new question. `applying(to:)` merges those fields
into the latest persisted question, retaining its current options and immutable identity.
Kind-specific configuration is included only for the relevant question kind.

Option writes remain immediate and independent. Discarding the editor discards unsaved
fields. External edits to the same question fields while this editor is open are not
merged; the local draft wins when explicitly saved.
