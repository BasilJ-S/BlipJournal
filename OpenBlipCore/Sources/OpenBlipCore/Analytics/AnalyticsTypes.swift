import Foundation

/// One scale answer, placed in time, ready to plot.
///
/// Produced by `Analytics.scaleSeries` and carried through `Analytics.rollingMean`,
/// which replaces `value` and nothing else.
public struct MoodPoint: Sendable, Equatable, Identifiable {
    /// The answer's identifier.
    public var id: String
    /// The entry the answer belongs to.
    public var entryId: String
    /// When the answer was given: `Answer.answeredAt`.
    public var date: Date
    /// The scale value, or a rolling mean of scale values.
    public var value: Double
    /// Whether the entry answered a prompt: `Entry.isPrompted`.
    public var prompted: Bool

    public init(id: String, entryId: String, date: Date, value: Double, prompted: Bool) {
        self.id = id
        self.entryId = entryId
        self.date = date
        self.value = value
        self.prompted = prompted
    }
}

/// The mean and count of the points that fell into one bucket of a bar chart.
public struct BucketStat: Sendable, Equatable, Identifiable {
    /// Stable key: `"0"`...`"23"` for hours, the weekday number for weekdays, the
    /// option identifier for options.
    public var id: String
    /// What the chart shows on the axis.
    public var label: String
    /// Arithmetic mean of the bucket's values. Nil when `count` is zero.
    public var mean: Double?
    /// How many values the mean is over.
    public var count: Int

    public init(id: String, label: String, mean: Double?, count: Int) {
        self.id = id
        self.label = label
        self.mean = mean
        self.count = count
    }
}

/// How prompts were responded to.
public struct ComplianceStats: Sendable, Equatable {
    public var answered: Int
    public var missed: Int
    public var dismissed: Int
    public var pending: Int
    /// `answered / (answered + missed + dismissed)`, nil when that denominator is zero.
    /// Pending prompts have no outcome yet and are left out of the rate.
    public var rate: Double?

    public init(answered: Int, missed: Int, dismissed: Int, pending: Int, rate: Double?) {
        self.answered = answered
        self.missed = missed
        self.dismissed = dismissed
        self.pending = pending
        self.rate = rate
    }
}
