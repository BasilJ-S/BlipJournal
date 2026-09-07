# Journal

`JournalView` lists every entry newest first, grouped by local day, with relative
date headers. Rows show time, survey, up to two answered values chosen per survey, and
text badges for source and draft status. The values keep their configured order and
unanswered choices are omitted. Badges wrap at large Dynamic Type.

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
