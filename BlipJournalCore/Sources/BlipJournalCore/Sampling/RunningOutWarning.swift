import Foundation

/// Marks the last few scheduled prompts so sampling never stops without the person being
/// told.
///
/// New prompts are only planned when the app opens, so someone who answers only from
/// notifications eventually reaches the end of the queue. The last ``promptCount``
/// scheduled prompts, across every survey, say so; opening any of them reschedules. Pure:
/// the caller decides which prompts are scheduled and re-applies the rule on every
/// reconcile, so the warning always sits on whatever is currently last.
public enum RunningOutWarning {
    /// How many of the last scheduled prompts carry the warning.
    public static let promptCount = 3

    /// How many prompts remain, counting itself, for each of the last ``promptCount``
    /// prompts in `scheduled`, keyed by prompt identifier. The last prompt maps to 1.
    ///
    /// `scheduled` is every prompt that will be delivered as a notification, across all
    /// surveys; the rule does not filter by status, time or survey. Order is by
    /// `scheduledAt`, ties broken by identifier so the result is stable. With fewer than
    /// ``promptCount`` prompts, every one of them is marked.
    public static func remainingCounts(scheduled: [Prompt]) -> [String: Int] {
        let ordered = scheduled.sorted { ($0.scheduledAt, $0.id) < ($1.scheduledAt, $1.id) }
        var result: [String: Int] = [:]
        for (index, prompt) in ordered.enumerated() {
            let remaining = ordered.count - index
            if remaining <= promptCount {
                result[prompt.id] = remaining
            }
        }
        return result
    }

    /// The warning line for a prompt with `remaining` prompts left, counting itself.
    /// Never mentions a survey or an answer, so it is safe under every preview mode.
    public static func message(remaining: Int) -> String {
        if remaining <= 1 {
            "Last check-in scheduled. Open Blip Journal to schedule more."
        } else {
            "\(remaining) check-ins left. Open Blip Journal to schedule more."
        }
    }

    /// `base` (what the survey's preview renders) with the warning added as a second line
    /// of the body. The title is untouched, so the preview's privacy choice still holds.
    public static func content(_ base: NotificationContent, remaining: Int) -> NotificationContent {
        NotificationContent(title: base.title, body: base.body + "\n" + message(remaining: remaining))
    }

    /// Whether `content` is `base`, plain or with any running-out warning. Lets a sweep of
    /// delivered notifications tell a warned notification from one whose preview changed.
    public static func matches(_ content: NotificationContent, base: NotificationContent) -> Bool {
        content == base || (1...promptCount).contains { self.content(base, remaining: $0) == content }
    }
}
