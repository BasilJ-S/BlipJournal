# Task C3: Sampling

**Status: done, merged in #7.** Kept as the record of what was asked. Where it and the code disagree, the code and the component's `DESIGN.md` are authoritative; the PR description lists the agreed deviations.

Implementation handoff for `OpenBlipCore/Sources/OpenBlipCore/Sampling/`. Read
`AGENTS.md`, the "Notification subsystem" section of `README.md`, the C3 section of
`docs/PLAN.md`, and `Model/SamplingConfig.swift` and `Model/Prompt.swift`. Do not touch
anything under `OpenBlip/` or `Storage/`.

## Goal

Two pure components: a `DaySampler` that turns one survey's `SamplingConfig` into random
prompt times for one day, and a `PromptPlanner` that decides, across all surveys, which
prompts to create and which to mark missed. No persistence, no notification code. The app
calls the planner every time it comes to the foreground and persists the result.

## Branch and delivery

- Branch from `main`: `c3-sampling`. Open a draft PR when done. See "Change control" in
  `AGENTS.md`.
- Add `"Sampling/DESIGN.md"` to the `exclude:` list in `Package.swift`.

## Files to create

```
Sampling/DayKey.swift          DayKey.string(for:calendar:) and DayKey.date(from:calendar:)
Sampling/SeededRandomNumberGenerator.swift
Sampling/DaySampler.swift
Sampling/PromptPlanner.swift
Sampling/DESIGN.md
Tests/OpenBlipCoreTests/Sampling/   one test file per source file
```

## Types

```swift
public enum DayKey {
    /// "yyyy-MM-dd" for the calendar day containing `date`, in `calendar`'s time zone.
    public static func string(for date: Date, calendar: Calendar) -> String
    /// Start of the day named by `key` in `calendar`'s time zone, or nil if malformed.
    public static func date(from key: String, calendar: Calendar) -> Date?
}

/// SplitMix64. Deterministic for a given seed. For tests and for reproducible schedules.
public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    public init(seed: UInt64)
    public mutating func next() -> UInt64
}

public struct DaySampler: Sendable {
    public init()
    /// Prompt times for the day containing `day`, ascending, rounded down to the minute.
    public func sample<G: RandomNumberGenerator>(
        day: Date, config: SamplingConfig, calendar: Calendar, using rng: inout G
    ) -> [Date]
}

public struct PromptPlan: Sendable, Equatable {
    public var newPrompts: [Prompt]        // status pending, ascending by scheduledAt
    public var missedPromptIds: [String]   // pending prompts to mark missed
}

public struct PromptPlanner: Sendable {
    public static let maxPending = 60
    public var maxHorizonDays: Int         // default 7
    public init(maxHorizonDays: Int = 7)
    public func plan<G: RandomNumberGenerator>(
        now: Date, surveys: [Survey], existing: [Prompt], calendar: Calendar, using rng: inout G
    ) -> PromptPlan
}
```

The `Prompt.day` field must be produced by `DayKey.string`. This is the only place in the
codebase that formats a day key; Storage and the app treat it as opaque.

## DaySampler rules

Precondition: `config.validationErrors.isEmpty`. If not, return `[]`; do not trap.

1. `windowStart = calendar.date(byAdding: .minute, value: config.windowStartMinutes, to: calendar.startOfDay(for: day))`,
   same for `windowEnd`. Use calendar arithmetic, not `addingTimeInterval`, so a day
   with a DST transition still maps 09:00 to 09:00 local.
2. Let `n = config.promptsPerDay`. If `n == 0` or `isEnabled == false`, return `[]`.
3. Split `[windowStart, windowEnd)` into `n` equal blocks by wall-clock duration.
4. For block `i`, the lower bound is `blockStart`, raised to `previous + minGap` if a
   previous prompt exists and that is later. If the lower bound is at or past
   `blockEnd`: place the prompt at the lower bound if it is still before `windowEnd`,
   otherwise drop it. Otherwise draw uniformly in `[lower, blockEnd)`.
5. Round each result down to the whole minute. After rounding, if a prompt is closer
   than `minGap` to the previous one, push it to exactly `previous + minGap`; if that
   reaches `windowEnd`, drop it.
6. Return ascending.

## PromptPlanner rules

Inputs: `existing` is every prompt with `status == pending` plus every prompt whose
`day` is today or later, for all surveys. The planner treats it as complete for those
days. Days before today are never generated.

1. **Missed.** Collect the IDs of pending prompts where `prompt.isExpired(at: now)`.
   Also collect pending prompts that have been superseded: `p` is superseded if another
   prompt `q` for the same survey has `p.scheduledAt < q.scheduledAt <= now`. A survey
   never has two live prompts. Both sets go in `missedPromptIds`, deduplicated,
   ascending by `scheduledAt`.
2. **Eligible surveys.** `isArchived == false`, `sampling.isEnabled`,
   `sampling.validationErrors.isEmpty`, `promptsPerDay > 0`.
3. **Horizon.** `dailyTotal = sum(promptsPerDay)` over eligible surveys. If zero, no new
   prompts. Otherwise `horizonDays = min(maxHorizonDays, max(1, maxPending / dailyTotal))`.
4. **Generate.** For each eligible survey and each day offset `0..<horizonDays` from
   `now`'s day in `calendar`: compute the day key; if `existing` already has any prompt
   for that survey and day (any status), skip; otherwise sample with `DaySampler`, keep
   times strictly later than `now + 60s`, and make a `Prompt` for each with
   `expiresAt = scheduledAt + expiryMinutes`, `status = .pending`, `day` = that key.
5. **Cap.** Let `livePending` be the count of existing pending prompts not in
   `missedPromptIds`. If `livePending + newPrompts.count > maxPending`, drop new prompts
   from the latest `scheduledAt` downward until it fits.
6. `newPrompts` ascending by `scheduledAt`, ties by survey ID then generation order.

The planner never proposes deleting prompts. When a survey's schedule changes, the app
calls `Store.deleteFuturePendingPrompts` before re-planning; that is outside this task.

## Tests

Swift Testing. Use `SeededRandomNumberGenerator(seed:)`, a `Calendar` with a fixed
`TimeZone(identifier: "America/Toronto")`, and fixed dates built from components. Cover:

- `DayKey` round-trips; a date at 23:59 local and 00:01 next day give different keys;
  the key follows the calendar's zone, not UTC.
- `SeededRandomNumberGenerator` with the same seed yields the same sequence; different
  seeds differ.
- Sampler: same seed gives same output; every time is within `[windowStart, windowEnd)`;
  ascending with gaps `>= minGap`; count equals `promptsPerDay` for the default config
  over 1000 seeds; whole-minute results; a window too narrow for the gap yields fewer
  prompts, never a gap violation; `n == 0` and disabled configs yield `[]`; an invalid
  config yields `[]`; on 2026-03-08 and 2026-11-01 (DST transitions in Toronto) every
  time still falls within the local window and the count is unchanged; a full-day window
  `0...1440` works.
- Planner: overdue pending prompts are missed; a pending prompt superseded by a later
  prompt that has fired is missed; days already present in `existing` are skipped; today
  only yields times after `now + 60s`; an archived, disabled, invalid, or zero-count
  survey gets nothing; horizon shrinks as `dailyTotal` grows and never exceeds
  `maxHorizonDays`; total pending never exceeds `maxPending` even when `existing` is
  already near the cap; output is ascending and deterministic for a seed; two surveys
  with different windows each get their own prompts with their own expiry.

## Acceptance

- `swift build` and `swift test` pass with zero warnings.
- `Sampling/` imports only `Foundation`.
- No `Date()` call anywhere in `Sampling/`; time always comes in as a parameter.
- `Sampling/DESIGN.md`: purpose, the stratified algorithm in a few lines, the
  supersession rule and why, the horizon and cap arithmetic, the DST handling, and
  known limitations (no per-weekday windows, no quiet days).

## Out of scope

Persisting prompts, notification requests, reacting to schedule changes, any UI. If the
sampler needs a config field that does not exist, do not add it to the model; list it
under "Deviations from the task" in the PR as a proposed follow-up.
