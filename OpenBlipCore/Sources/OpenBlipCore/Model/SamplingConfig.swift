import Foundation

/// One survey's prompt schedule.
///
/// Times of day are stored as minutes after local midnight rather than `Date`s so a
/// schedule means the same thing on every date, in every time zone, and across a DST
/// transition. Turning these minutes into concrete instants is the sampler's job.
public struct SamplingConfig: Sendable, Equatable, Hashable, Codable {
    /// How many prompts to schedule on each day the survey is enabled.
    public var promptsPerDay: Int
    /// Start of the daily window, in minutes after local midnight. 540 is 09:00.
    public var windowStartMinutes: Int
    /// End of the daily window, in minutes after local midnight. 1380 is 23:00.
    public var windowEndMinutes: Int
    /// The smallest gap the sampler may leave between two prompts on the same day.
    public var minGapMinutes: Int
    /// How long a prompt stays answerable before it counts as missed.
    public var expiryMinutes: Int
    /// Whether the planner schedules anything at all for this survey.
    public var isEnabled: Bool

    /// Creates a schedule, defaulting to the values in the README's "Defaults" table.
    public init(
        promptsPerDay: Int = 3,
        windowStartMinutes: Int = 540,
        windowEndMinutes: Int = 1380,
        minGapMinutes: Int = 60,
        expiryMinutes: Int = 20,
        isEnabled: Bool = true
    ) {
        self.promptsPerDay = promptsPerDay
        self.windowStartMinutes = windowStartMinutes
        self.windowEndMinutes = windowEndMinutes
        self.minGapMinutes = minGapMinutes
        self.expiryMinutes = expiryMinutes
        self.isEnabled = isEnabled
    }

    /// The schedule a new survey starts with: 3 prompts between 09:00 and 23:00, at
    /// least 60 minutes apart, each expiring after 20 minutes.
    public static let `default` = SamplingConfig()

    /// Every rule this schedule breaks. Empty means the schedule is usable.
    ///
    /// Errors are returned in a fixed order so a UI can show them deterministically.
    /// ``ValidationError/gapDoesNotFit`` is only reported once the window and the gap
    /// are each well formed, because comparing against a negative window length or a
    /// negative gap says nothing useful; one mistake should not produce a cascade.
    public var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []

        if !(0...20).contains(promptsPerDay) {
            errors.append(.promptsPerDayOutOfRange)
        }

        let windowIsWellFormed =
            windowStartMinutes >= 0
            && windowStartMinutes < windowEndMinutes
            && windowEndMinutes <= 1440
        if !windowIsWellFormed {
            errors.append(.windowOutOfRange)
        }

        let gapIsInRange = (0...1440).contains(minGapMinutes)
        if !gapIsInRange {
            errors.append(.minGapOutOfRange)
        }

        if windowIsWellFormed, gapIsInRange,
           (promptsPerDay - 1) * minGapMinutes >= windowEndMinutes - windowStartMinutes {
            errors.append(.gapDoesNotFit)
        }

        if !(1...240).contains(expiryMinutes) {
            errors.append(.expiryOutOfRange)
        }

        return errors
    }

    /// A single way a ``SamplingConfig`` can be unusable.
    ///
    /// Backed by `String` so the case survives JSON alongside the config it describes.
    public enum ValidationError: String, Error, CaseIterable, Sendable, Equatable, Hashable, Codable {
        /// `promptsPerDay` is outside `0...20`.
        case promptsPerDayOutOfRange
        /// The window is not `0 <= start < end <= 1440`.
        case windowOutOfRange
        /// `minGapMinutes` is outside `0...1440`. A negative gap is meaningless and
        /// would let the sampler place prompts in any order it liked; zero is allowed
        /// and means "no minimum".
        case minGapOutOfRange
        /// `(promptsPerDay - 1) * minGapMinutes` is not shorter than the window, so the
        /// requested prompts cannot all fit while respecting the gap.
        case gapDoesNotFit
        /// `expiryMinutes` is outside `1...240`.
        case expiryOutOfRange
    }
}
