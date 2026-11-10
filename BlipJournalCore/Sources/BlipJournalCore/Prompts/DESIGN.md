# Prompts

`PromptRoute.resolve` turns a notification prompt ID into an `Outcome` using current
stored prompts, entries and the supplied survey lookup (including archived surveys).

| Stored state | Outcome |
|---|---|
| Missing prompt or survey | Unavailable |
| Linked unfinished entry | Runner, regardless of expiry or prompt status |
| Linked completed entry | Read-only detail |
| No entry; pending and unexpired | Fresh runner |
| No entry; answered | Dead end: entry deleted |
| No entry; expired, missed or dismissed | Dead end: expired |

The only mutation marks an expired pending prompt missed. Dead ends may offer a manual
entry; they never create another entry linked to the prompt. The app owns draft flushing,
route replacement and view identity. Store read failures currently resolve as missing data.
