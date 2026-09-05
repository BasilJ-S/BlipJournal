# Task C1: Domain model

**Status: done, merged in #2.** What follows is the brief as it was written, kept as the
record of what was asked. Where it and the code disagree, the code and
`OpenBlipCore/Sources/OpenBlipCore/Model/DESIGN.md` are authoritative. The differences,
all agreed in review:

- The ID helper is `Identifier`, not `ID`. `Identifiable` gives conforming types an `ID`
  associated type that shadows it.
- `SamplingConfig.ValidationError` has a fifth case, `minGapOutOfRange` (`0...1440`).
- `Answer` carries `answeredAt`. It is what makes the options a person saw replayable.
- `AnswerValue`'s JSON discriminator is the `QuestionKind` raw value, so `singleChoice`
  and `multiChoice` rather than `single` and `multi`.
- The placeholder `OpenBlipCore` enum is now `CoreSchema.version`, since a type named
  after the module shadows the module.

Implementation handoff for OpenBlipCore. Read `AGENTS.md` and the "Architecture" and
"Defaults" sections of `README.md` before starting. Do not read or touch anything under
`OpenBlip/` (the app target).

## Goal

Create the plain Swift value types that every other subsystem talks in. No database, no
UI, no GRDB import. When this task is done, the storage, sampling, and export tasks can
start in parallel against these types.

## Branch and delivery

- Branch from `main`: `c1-domain-model`.
- Commit as the repo's local git identity (already configured). Do not change it.
- Push the branch and open a draft pull request when done. Do not merge. The planner
  reviews the PR as a comment; the maintainer merges. See "Change control" in `AGENTS.md`.

## Files to create

All under `OpenBlipCore/Sources/OpenBlipCore/Model/`:

```
Identifiers.swift      ID generation helper
QuestionKind.swift     QuestionKind, ScaleConfig
SamplingConfig.swift   SamplingConfig with defaults and validation
Survey.swift           Survey, Question, ChoiceOption
Prompt.swift           Prompt, PromptStatus
Entry.swift            Entry, Answer, AnswerValue
LabelVersion.swift     LabelVersion and label(at:) lookup
SurveyTemplate.swift   SurveyTemplate.makeDefault()
DESIGN.md              Component design doc, see AGENTS.md "Documentation"
```

Tests under `OpenBlipCore/Tests/OpenBlipCoreTests/Model/`. Delete the placeholder test
in `OpenBlipCoreTests.swift` and keep the `schemaVersion` constant in
`OpenBlipCore.swift` untouched.

## Types

Every type is `public`, `Sendable`, `Equatable`, `Hashable`, and `Codable`. Types with
an `id` are `Identifiable`. IDs are `String` holding a lowercase UUID. Provide a
public memberwise `init` with sensible defaults where noted. Add a doc comment on every
type and every non-obvious property.

```swift
public enum ID {
    public static func make() -> String   // UUID().uuidString.lowercased()
}

public enum QuestionKind: String, CaseIterable {
    case scale, singleChoice, multiChoice, yesNo, text
    public var usesOptions: Bool          // true for singleChoice and multiChoice
}

public struct ScaleConfig {
    public var min: Int                   // default 1
    public var max: Int                   // default 7
    public var minLabel: String           // default "Very unpleasant"
    public var maxLabel: String           // default "Very pleasant"
    public var isValid: Bool              // max > min, and (max - min) <= 10
}

public struct SamplingConfig {
    public var promptsPerDay: Int         // default 3
    public var windowStartMinutes: Int    // minutes after local midnight, default 540 (09:00)
    public var windowEndMinutes: Int      // default 1380 (23:00)
    public var minGapMinutes: Int         // default 60
    public var expiryMinutes: Int         // default 20
    public var isEnabled: Bool            // default true
    public static let `default`: SamplingConfig
    public var validationErrors: [ValidationError]   // empty means valid
    public enum ValidationError: Error, Equatable {
        case promptsPerDayOutOfRange        // must be 0...20
        case windowOutOfRange               // 0 <= start < end <= 1440
        case gapDoesNotFit                  // (promptsPerDay - 1) * minGap must be < window length
        case expiryOutOfRange               // 1...240
    }
}

public struct ChoiceOption: Identifiable {
    public var id: String
    public var label: String
    public var position: Int
    public var isArchived: Bool           // default false
}

public struct Question: Identifiable {
    public var id: String
    public var kind: QuestionKind
    public var label: String
    public var position: Int
    public var isRequired: Bool           // default false
    public var isArchived: Bool           // default false
    public var scale: ScaleConfig?        // non-nil only when kind == .scale
    public var allowsCustomOptions: Bool  // default false; only meaningful when kind.usesOptions
    public var options: [ChoiceOption]    // empty unless kind.usesOptions
    public var activeOptions: [ChoiceOption]   // not archived, sorted by position
}

public struct Survey: Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var isArchived: Bool           // default false
    public var sampling: SamplingConfig
    public var questions: [Question]
    public var activeQuestions: [Question]     // not archived, sorted by position
}

public enum PromptStatus: String, CaseIterable {
    case pending, answered, missed, dismissed
}

public struct Prompt: Identifiable {
    public var id: String
    public var surveyId: String
    public var day: String                // "yyyy-MM-dd" in the local calendar, the day it was generated for
    public var scheduledAt: Date
    public var expiresAt: Date
    public var status: PromptStatus       // default .pending
    public var respondedAt: Date?         // set when status becomes answered or missed
    public func isExpired(at now: Date) -> Bool   // status == .pending && expiresAt <= now
}

public struct Entry: Identifiable {
    public var id: String
    public var surveyId: String
    public var promptId: String?          // nil means a manual, unprompted entry
    public var startedAt: Date
    public var completedAt: Date?         // nil while the entry is a partial autosave
    public var isPrompted: Bool           // promptId != nil
}

public enum AnswerValue {
    case scale(Int)
    case single(optionId: String)
    case multi(optionIds: [String])
    case yesNo(Bool)
    case text(String)
    public var kind: QuestionKind
    public var isEmpty: Bool              // multi([]) and text("") are empty; others never are
}

public struct Answer: Identifiable {
    public var id: String
    public var entryId: String
    public var questionId: String
    public var questionVersionId: String  // ID of the questionVersion row that was current when
                                          // answered. Storage assigns it; the model only carries it.
    public var value: AnswerValue
}

public struct LabelVersion {
    public var label: String
    public var validFrom: Date
}

extension Array where Element == LabelVersion {
    /// Newest version with validFrom <= date. Falls back to the earliest version when
    /// date precedes all of them. Nil only when the array is empty.
    public func label(at date: Date) -> String?
}

public enum SurveyTemplate {
    /// The six-question default survey from README, with default sampling.
    public static func makeDefault(now: Date = Date()) -> Survey
}
```

`AnswerValue` must round-trip through `JSONEncoder` and `JSONDecoder`. Write the
`Codable` conformance by hand with a `kind` discriminator field so the JSON is stable
and readable: `{"kind":"scale","value":5}`, `{"kind":"multi","optionIds":["a","b"]}`.

## Default survey contents

Positions start at 0. Options in the order listed. All IDs freshly generated per call.

1. "How are you feeling right now?" scale 1 to 7, "Very unpleasant" / "Very pleasant", required.
2. "What best describes this feeling?" multiChoice, allowsCustomOptions:
   Calm, Content, Happy, Excited, Focused, Tired, Bored, Anxious, Stressed, Irritated, Sad, Lonely.
3. "What is having the biggest impact?" multiChoice, allowsCustomOptions:
   Work, Study, Family, Partner, Friends, Health, Sleep, Exercise, Food, Money, Weather, News, Hobbies.
4. "What are you doing?" singleChoice, allowsCustomOptions:
   Working, Studying, Commuting, Eating, Socialising, Exercising, Resting, Chores, Screen time, Outdoors.
5. "Who are you with?" multiChoice, allowsCustomOptions:
   Alone, Partner, Family, Friends, Colleagues, Strangers.
6. "Anything else?" text.

## Tests

Swift Testing (`import Testing`). One file per source file. Cover at least:

- `SamplingConfig.default` has no validation errors; each `ValidationError` case is
  produced by a config that violates exactly that rule; 3 prompts with a 60 minute gap in
  a 14 hour window is valid; 20 prompts with a 60 minute gap in a 14 hour window is not.
- `ScaleConfig.isValid` rejects `max <= min` and ranges wider than 10.
- `AnswerValue` round-trips every case through JSON and the encoded JSON contains the
  expected `kind` string. `isEmpty` behaves as specified.
- `Prompt.isExpired(at:)` is false before expiry, true at and after expiry, and false
  for non-pending prompts regardless of time.
- `[LabelVersion].label(at:)` picks the correct version for a date before, between, and
  after two versions, and returns nil for an empty array.
- `Question.activeOptions` and `Survey.activeQuestions` exclude archived items and sort
  by position even when the source array is shuffled.
- `SurveyTemplate.makeDefault()` yields six questions with the kinds, labels, option
  counts, and required flags above; the scale question has a `ScaleConfig`; every ID in
  the survey is unique; two calls produce different IDs; the whole survey round-trips
  through JSON.

## Acceptance

- `cd OpenBlipCore && swift build` and `swift test` pass with zero warnings.
- No file imports anything other than `Foundation` (and `Testing` in tests).
- All public API has doc comments.
- `Model/DESIGN.md` exists and matches the code: purpose, the type graph in a few lines,
  the ID and versioning invariants, and why `AnswerValue` uses a hand-written `Codable`.
- No `UPDATE`-style mutation helpers, no persistence, no formatting of dates for
  display. Those belong to other tasks.

## Out of scope

Storage, sampling logic, CSV, anything in the app target. If you believe a type needs a
property not listed here, add it, note it at the top of the PR description under
"Deviations from the task", and explain why.
