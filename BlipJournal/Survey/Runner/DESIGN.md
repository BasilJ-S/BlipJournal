# Survey/Runner

The runner presents active questions in one scrollable screen. `EntryDraft` creates or
resumes the entry immediately, preserves answer IDs and first timestamps, and writes
through one ordered queue. Text edits debounce for 300ms and flush on close, completion,
and backgrounding. Custom options are inserted before reloading the survey so their
creation order remains recoverable. Known limitations: no conditional questions, no
undo, no completed-entry editing, and a brief text-loss window before debounce or forced
termination; quick notes are limited to 500 Swift characters.

Scale and spectrum questions use adjustable sliders with explicit accessibility labels.
An unanswered spectrum shows "Not selected" and no thumb; its first adjustment begins
from the midpoint. Invalid spectrum configuration is rendered inert rather than trapping.
