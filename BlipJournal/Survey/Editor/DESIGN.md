# Survey editor

The editor is a small set of SwiftUI screens backed by `EditorModel`. The model is the
only app-layer writer: definition edits append Store versions, sampling changes validate
before saving, notification changes call the coordinator, and Journal summary choices
append a survey version. A survey can show zero, one, or two answer values on each Journal
row. Tapping choices establishes their display order; with two already chosen, a new tap
replaces the second while keeping the primary anchored.

Active questions and options are reordered by removing the selected rows, inserting them
at the requested destination, and renumbering the resulting active list from zero. Only
items whose position changed receive a version row. Archive hides a definition while
preserving children and history; permanent erase is reachable only from Archived and is
delegated to Store after an impact confirmation.

The confirmation text uses Store's `DeletionImpact` counts and oldest answer date. It
states what survives, mentions emptied entries, and ends with “It cannot be undone.”

Spectrum questions require at least two non-blank labelled zones and ordered interior
boundaries. Their colour pickers and boundary sliders carry labels naming their zones.

Known limitations: drag reorder is available only in EditMode; question kinds cannot
change; copying duplicates current active configuration only, never response history.
