import Foundation

/// The kind of answer a question accepts.
///
/// The raw values are persisted and exported, so they are part of the on-disk and
/// CSV contract: renaming a case is a migration, not a refactor.
public enum QuestionKind: String, CaseIterable, Sendable, Equatable, Hashable, Codable {
    /// A numeric rating inside a bounded range, configured by ``ScaleConfig``.
    case scale
    /// Exactly one option from a list.
    case singleChoice
    /// Any number of options from a list, including none.
    case multiChoice
    /// A boolean.
    case yesNo
    /// Free text.
    case text

    /// Whether questions of this kind draw their answers from a list of options.
    ///
    /// Only option-backed kinds may carry a non-empty `options` array or set
    /// `allowsCustomOptions`.
    public var usesOptions: Bool {
        switch self {
        case .singleChoice, .multiChoice: true
        case .scale, .yesNo, .text: false
        }
    }
}

/// The bounds and endpoint labels of a ``QuestionKind/scale`` question.
///
/// Present only on scale questions. The defaults are the 1 to 7 pleasantness scale
/// the default survey opens with.
public struct ScaleConfig: Sendable, Equatable, Hashable, Codable {
    /// The lowest selectable value, inclusive.
    public var min: Int
    /// The highest selectable value, inclusive.
    public var max: Int
    /// The label shown at the ``min`` end of the scale.
    public var minLabel: String
    /// The label shown at the ``max`` end of the scale.
    public var maxLabel: String

    /// Creates a scale configuration, defaulting to the 1 to 7 pleasantness scale.
    public init(
        min: Int = 1,
        max: Int = 7,
        minLabel: String = "Very unpleasant",
        maxLabel: String = "Very pleasant"
    ) {
        self.min = min
        self.max = max
        self.minLabel = minLabel
        self.maxLabel = maxLabel
    }

    /// Whether the range is usable: at least two points, and no wider than 11 points.
    ///
    /// The upper bound exists because the runner renders a scale as one row of tap
    /// targets; beyond `max - min == 10` it stops fitting on a phone screen.
    public var isValid: Bool {
        max > min && (max - min) <= 10
    }
}
