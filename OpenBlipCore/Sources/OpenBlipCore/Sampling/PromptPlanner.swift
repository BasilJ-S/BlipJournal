import Foundation

/// What the planner wants done: prompts to create and prompts to mark missed.
///
/// The planner never proposes deleting anything. When a survey's schedule changes the
/// app discards that survey's future pending prompts itself before re-planning.
public struct PromptPlan: Sendable, Equatable {
    /// Prompts to persist, all `pending`, ascending by `scheduledAt`.
    public var newPrompts: [Prompt]
    /// Identifiers of pending prompts that should become `missed`.
    public var missedPromptIds: [String]

    public init(newPrompts: [Prompt] = [], missedPromptIds: [String] = []) {
        self.newPrompts = newPrompts
        self.missedPromptIds = missedPromptIds
    }
}

/// Decides, across every survey, which prompts to create and which to mark missed.
///
/// The app calls ``plan(now:surveys:existing:calendar:using:)`` each time it comes to
/// the foreground and persists the result. Pure: time and randomness are parameters.
public struct PromptPlanner: Sendable {
    /// The most prompts that may be pending at once, across all surveys. iOS caps
    /// pending local notifications at 64 per app; this leaves a little headroom.
    public static let maxPending = 60

    /// How many days ahead, today included, the planner will schedule. Values below
    /// zero behave as zero: nothing is generated.
    public var maxHorizonDays: Int

    public init(maxHorizonDays: Int = 7) {
        self.maxHorizonDays = maxHorizonDays
    }

    /// Plans against `existing`, which must hold every pending prompt plus every prompt
    /// whose `day` is today or later, for all surveys. The planner treats it as complete
    /// for those days and never generates for days before today.
    public func plan<G: RandomNumberGenerator>(
        now: Date, surveys: [Survey], existing: [Prompt], calendar: Calendar, using rng: inout G
    ) -> PromptPlan {
        let missed = Self.missedPrompts(in: existing, now: now)
        let missedIds = Set(missed.map(\.id))

        let eligible = surveys.filter { survey in
            !survey.isArchived
                && survey.sampling.isEnabled
                && survey.sampling.validationErrors.isEmpty
                && survey.sampling.promptsPerDay > 0
        }
        let dailyTotal = eligible.reduce(0) { $0 + $1.sampling.promptsPerDay }
        guard dailyTotal > 0 else {
            return PromptPlan(newPrompts: [], missedPromptIds: missed.map(\.id))
        }
        let horizonDays = max(0, min(maxHorizonDays, max(1, Self.maxPending / dailyTotal)))

        let generated = Self.generate(
            now: now, surveys: eligible, existing: existing,
            horizonDays: horizonDays, calendar: calendar, using: &rng
        )

        let livePending = existing.filter { $0.status == .pending && !missedIds.contains($0.id) }.count
        let room = max(0, Self.maxPending - livePending)
        let newPrompts = Array(generated.prefix(room))

        return PromptPlan(newPrompts: newPrompts, missedPromptIds: missed.map(\.id))
    }

    /// Pending prompts that have expired, plus pending prompts superseded by a later
    /// prompt for the same survey that has already fired. A survey never has two live
    /// prompts. Ascending by `scheduledAt`, then by identifier so the order is stable.
    private static func missedPrompts(in existing: [Prompt], now: Date) -> [Prompt] {
        var seen: Set<String> = []
        var missed: [Prompt] = []
        for prompt in existing where prompt.status == .pending {
            guard !seen.contains(prompt.id) else { continue }
            let superseded = existing.contains { other in
                other.id != prompt.id
                    && other.surveyId == prompt.surveyId
                    && prompt.scheduledAt < other.scheduledAt
                    && other.scheduledAt <= now
            }
            if prompt.isExpired(at: now) || superseded {
                seen.insert(prompt.id)
                missed.append(prompt)
            }
        }
        return missed.sorted { ($0.scheduledAt, $0.id) < ($1.scheduledAt, $1.id) }
    }

    /// One survey on one day: the unit the planner checks for existing coverage.
    private struct SurveyDay: Hashable {
        let surveyId: String
        let day: String
    }

    /// New pending prompts for every eligible survey and every day in the horizon that
    /// has none yet, ascending by `scheduledAt`, ties by survey ID then generation order.
    private static func generate<G: RandomNumberGenerator>(
        now: Date, surveys: [Survey], existing: [Prompt],
        horizonDays: Int, calendar: Calendar, using rng: inout G
    ) -> [Prompt] {
        let covered = Set(existing.map { SurveyDay(surveyId: $0.surveyId, day: $0.day) })
        let earliest = now.addingTimeInterval(60)
        let today = calendar.startOfDay(for: now)
        let sampler = DaySampler()

        var generated: [(prompt: Prompt, order: Int)] = []
        for survey in surveys {
            let expiry = TimeInterval(survey.sampling.expiryMinutes * 60)
            for offset in 0..<horizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                let dayKey = DayKey.string(for: day, calendar: calendar)
                guard !covered.contains(SurveyDay(surveyId: survey.id, day: dayKey)) else { continue }

                let times = sampler.sample(day: day, config: survey.sampling, calendar: calendar, using: &rng)
                for scheduledAt in times where scheduledAt > earliest {
                    let prompt = Prompt(
                        surveyId: survey.id,
                        day: dayKey,
                        scheduledAt: scheduledAt,
                        expiresAt: scheduledAt.addingTimeInterval(expiry),
                        status: .pending
                    )
                    generated.append((prompt, generated.count))
                }
            }
        }

        return generated
            .sorted { lhs, rhs in
                (lhs.prompt.scheduledAt, lhs.prompt.surveyId, lhs.order)
                    < (rhs.prompt.scheduledAt, rhs.prompt.surveyId, rhs.order)
            }
            .map(\.prompt)
    }
}
