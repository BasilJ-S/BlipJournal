# Journal

`JournalView` lists entries, by default every one newest first, grouped by local day, with relative
date headers. Rows show time, survey, up to two answered values chosen per survey, and
text badges for source and draft status. The values keep their configured order and
unanswered choices are omitted. Badges wrap at large Dynamic Type.

- Filter and sort: a toolbar button opens `JournalFilterView`, which edits a
  `JournalFilter` and `JournalSort` live. Rules (including what changing survey clears), and which surveys, questions and
  options to offer, live in core `JournalQuery` with tests; the sheet only lays them out.
  Survey, source and status read entry metadata; an answer condition (choice option or
  yes/no) and an answer sort (scale or spectrum) need a survey and read
  `Store.answers(questionIds:)` off the main actor.
- The answer read is keyed by revision, retry attempt and question IDs. A spinner shows
  only when no read for the same questions exists yet; after a refresh the older read
  stays on screen until the new one lands, so scroll position survives. A failed read
  caches nothing: with no earlier read the list offers Try again and the bar says
  "Couldn't load answers"; with one, it stays and an alert explains. Each new key
  clears the failure first, so returning to a once-failed query shows the spinner.
- The query is normalised against `surveysById` each render and written back into
  state on appear and on every revision, so the sheet never shows a survey, question or
  option the list has dropped. The filtered survey stays pickable even when archived
  with no entries left. Each render computes the query and visible entries once.
- Date order keeps day sections (either direction); answer order is one flat list
  whose rows show date with year. While filtered, a bar above the list shows
  "n of total entries", followed by the order when not newest first; with only the order
  changed it shows "Sorted: …". Answer orders read "<question> (highest first)" in
  both the sheet and the bar, since labels often end in "?". Changing the order
  scrolls the list back to the top. Both bar forms carry Clear. No matches has its own empty state.
  State lives in the view and resets on relaunch.
- `AppModel.entries` is the list source; its refresh revision reloads answer
  summaries and detail even when entry metadata is unchanged.
- `JournalRowSummary` owns row presentation state. It checks cancellation before
  clearing state and after awaiting a read, so a cancelled revision cannot overwrite
  a newer summary. Tests explicitly complete overlapping reads in reverse order.
- New entry opens the fixed A3 runner signature; multiple surveys offer a menu.
- Unfinished entries offer Continue entry, resuming the same entry. Completed entries
  are read-only.
  Sheet dismissal reloads the model, including swipe dismissal.
- `EntryDetailView` shows answered questions only, archived included, in position
  order. Choice answers use current option labels; scales include their end labels.
  Spectrum answers show the stable raw percentage, not a zone classification that a
  later definition version could change.
- Detail and row reads run in nonisolated async helpers. Prompt lookup tries two
  nearby Gregorian day keys, then scans by ID; time-zone changes can need the scan.
  Loading a manual entry clears any previous prompt.
- Delete requires confirmation with answer count and, for prompted entries, says
  the prompt remains answered. Vacuum runs off the main actor with progress and
  duplicate deletion disabled. Delete stays disabled until the answer count loads. Reload even if cleanup throws after deletion.
  After successful deletion, dismiss even if refreshing fails.
- `SampleEntry` exists only in DEBUG. It writes active-question answers and optional
  answered prompts. A supplied RNG makes tests reproducible; the toolbar uses system
  randomness. All answers fall between start and completion, within the past 14 days.

Known limits: refresh still reads the full entry list synchronously. Errors after
committed deletion can leave the detail open with an error; returning to the list
shows refreshed state when readable. Historical wording belongs to export.
