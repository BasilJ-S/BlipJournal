# Sampling

## Purpose

Turns schedules into prompts. `DaySampler` draws random prompt times for one survey on
one day; `PromptPlanner` runs it across every survey for the days ahead and decides which
pending prompts are dead. Both are pure: time and randomness are parameters, nothing is
persisted, no notification is requested. The app calls the planner on every foreground
and persists the result. Imports only `Foundation`.

## Key types

```
DayKey.string(for:calendar:)            the only formatter of Prompt.day, "yyyy-MM-dd"
DayKey.date(from:calendar:)             strict inverse, nil if malformed
SeededRandomNumberGenerator(seed:)      SplitMix64, for tests and reproducible schedules
DaySampler.sample(day:config:calendar:using:)  -> [Date], ascending, whole minutes
PromptPlanner.plan(now:surveys:existing:calendar:using:) -> PromptPlan
PromptPlan                              newPrompts (pending, ascending) + missedPromptIds
```

## Stratified sampling

Window `[start, end)` is split into `promptsPerDay` equal blocks. For each block the
lower bound is the block start, raised to `previous + minGap` if that is later. If the
bound has reached the block end, the prompt sits at the bound when still inside the
window, else it is dropped; otherwise one time is drawn uniformly in `[bound, blockEnd)`.
Each time is floored to the minute, then pushed to exactly `previous + gap` if rounding
brought it too close, and dropped if that push reaches the window end. Here `gap` is
`max(minGap, 1 minute)`: results are whole minutes, so a gap of zero still means no two
prompts share a minute, otherwise a survey could hold two live prompts at the same
instant that supersession can never separate. For a positive `minGap` the push is a
safety net only; the pre-rounding bound already guarantees it. Invalid, disabled, or
zero-count configs yield `[]` and never trap.

## Supersession

A pending prompt is missed when it has expired, or when a later prompt for the same
survey has already fired (`p.scheduledAt < q.scheduledAt <= now`, any status of `q`). A
survey never has two live prompts: if the device slept through one and the next has
fired, the older one is a stale notification the person should not be answering. The
result is deduplicated and ascending by `scheduledAt`, then by identifier. Supersession
only sees prompts in `existing`, so a fired prompt from before today that is no longer
pending cannot supersede; with the longest expiry (240 minutes) that window closes by
04:00, and by then the older prompt has expired on its own.

## Horizon and cap

iOS holds at most 64 pending local notifications per app; `maxPending` is 60.
`horizonDays = min(maxHorizonDays, max(1, maxPending / sum(promptsPerDay)))` over
eligible surveys (not archived, enabled, valid, count above zero), so one survey at
three per day looks a week ahead while heavy schedules look only as far as fits.
Generation covers day offsets `0..<horizonDays` from today, skipping any survey-day that
already has a prompt of any status in `existing`. Today keeps only times later than
`now + 60s`. If live pending plus new would exceed the cap, the latest new prompts are
dropped first. `newPrompts` is ascending by `scheduledAt`, ties by survey ID, then by
generation order. The planner never proposes deletions; the app clears a survey's future
pending prompts itself when its schedule changes.

## DST handling

Window edges come from wall-clock hour and minute via `Calendar.date(bySettingHour:)`,
and a closing minute of 1440 is the next day's `startOfDay`. This departs from the C3
handoff, which asked for `date(byAdding: .minute, to: startOfDay)`: on this Foundation
that adds elapsed minutes, so on the spring-forward day 540 minutes past midnight is
10:00, not 09:00. Inside the window everything is elapsed time: blocks are equal in
elapsed duration and the gap is an elapsed gap, because that is what the person
experiences between two notifications. Inside a window that does not span the
transition, wall-clock and elapsed durations coincide. On a spring-forward day an edge
that names a skipped time moves forward to the first instant that exists (Toronto 02:30
becomes 03:00); Foundation does this itself for whole-hour shifts, and for a shift that
is not a whole hour (Lord Howe Island, 30 minutes) it rolls into the next day, so an edge
that leaves the day is replaced by the day's DST transition instant. On a fall-back day
an edge inside the repeated hour takes its first occurrence. Zones whose transition is at
midnight (Santiago, Havana) still work: `startOfDay` is 01:00 there and the edges follow
it. Rounding uses the calendar's minute boundary. Day keys are always Gregorian in the calendar's time zone, so a device set to
another calendar still writes the same key.

## Known limitations

- One window for every day of the week; no per-weekday windows, no quiet days.
- On a spring-forward day a window that spans the skipped hour is an hour shorter in
  elapsed time, so a schedule whose gaps only just fit may yield one prompt fewer. A
  window lying wholly inside the skipped hour has no length that day and yields nothing.
- `maxHorizonDays` below zero behaves as zero rather than trapping.
- A time zone change is not reconciled. `Prompt.day` is whatever zone the device had when
  the prompt was generated, so after a move a survey-day counts as covered even if those
  prompts fall in a different local day, and existing prompts keep their old wall-clock
  times until they pass. The planner never deletes, so this is left to the app.
- `validationErrors` is evaluated on every call; cheap, but not free if a caller loops.
- Prompt identifiers are fresh UUIDs, so two plans with the same seed agree on times but
  not on IDs.
