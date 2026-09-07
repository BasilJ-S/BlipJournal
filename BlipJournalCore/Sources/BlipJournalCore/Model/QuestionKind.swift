import Foundation

/// The kind of answer a question accepts.
///
/// The raw values are persisted and exported, so they are part of the on-disk and
/// CSV contract: renaming a case is a migration, not a refactor.
public enum QuestionKind: String, CaseIterable, Sendable, Equatable, Hashable, Codable {
    /// A numeric rating inside a bounded range, configured by ``ScaleConfig``. A small
    /// number of individually meaningful values: how many, how much, which of these
    /// numbers. See ``spectrum`` for a continuous position instead of a count.
    case scale
    /// A continuous position on a bipolar axis, configured by ``SpectrumConfig``. Where
    /// ``scale`` counts, this places: the position matters, not a discrete number, and
    /// only the zone it falls in is named.
    case spectrum
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
        case .scale, .spectrum, .yesNo, .text: false
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

    /// Whether the range is usable: `-100 <= min < max <= 100`.
    ///
    /// Every comparison is direct, never a difference, so an extreme `Int` (`.min`,
    /// `.max`) cannot overflow it the way `max - min` would.
    public var isValid: Bool {
        min >= -100 && max <= 100 && min < max
    }
}

/// An RGB colour, `0...1` per channel. Stored here rather than as a SwiftUI `Color`
/// because this module imports only `Foundation`; `BlipJournal` extends this with a
/// `Color` conversion.
public struct SpectrumColor: Sendable, Equatable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The zones and boundaries of a ``QuestionKind/spectrum`` question: a continuous
/// `0...1` position, split into labelled, coloured bands.
///
/// Present only on spectrum questions. The defaults are the three-band pleasantness
/// spectrum Apple's State of Mind picker uses as its wording.
public struct SpectrumConfig: Sendable, Equatable, Hashable, Codable {
    /// One labelled, coloured band of the spectrum.
    public struct Zone: Sendable, Equatable, Hashable, Codable {
        public var label: String
        public var color: SpectrumColor

        public init(label: String, color: SpectrumColor) {
            self.label = label
            self.color = color
        }
    }

    /// Every zone, left to right. At least two.
    public var zones: [Zone]
    /// Interior boundaries between zones, strictly between 0 and 1 and strictly
    /// increasing. Always one fewer than `zones.count`: boundaries are stored rather
    /// than a start/end per zone so the zones can never overlap or leave a gap.
    public var breakpoints: [Double]

    public init(zones: [Zone], breakpoints: [Double]) {
        self.zones = zones
        self.breakpoints = breakpoints
    }

    /// The pleasantness spectrum a new spectrum question opens with: the three labels
    /// Apple's State of Mind picker uses, split into equal thirds.
    public init() {
        self.init(
            zones: [
                Zone(label: "Very unpleasant", color: SpectrumColor(red: 0.85, green: 0.25, blue: 0.25)),
                Zone(label: "Neutral", color: SpectrumColor(red: 0.85, green: 0.72, blue: 0.35)),
                Zone(label: "Very pleasant", color: SpectrumColor(red: 0.30, green: 0.70, blue: 0.40)),
            ],
            breakpoints: [1.0 / 3.0, 2.0 / 3.0])
    }

    /// A few built-in starting points, name alongside config. The editor lets a person
    /// load one and then keep editing it; nothing here is ever loaded automatically.
    public static let presets: [(name: String, config: SpectrumConfig)] = [
        ("Pleasantness", SpectrumConfig()),
        ("Energy", SpectrumConfig(
            zones: [
                Zone(label: "Low energy", color: SpectrumColor(red: 0.30, green: 0.45, blue: 0.80)),
                Zone(label: "Medium energy", color: SpectrumColor(red: 0.55, green: 0.40, blue: 0.75)),
                Zone(label: "High energy", color: SpectrumColor(red: 0.90, green: 0.55, blue: 0.20)),
            ],
            breakpoints: [1.0 / 3.0, 2.0 / 3.0])),
        ("Calm to anxious", SpectrumConfig(
            zones: [
                Zone(label: "Calm", color: SpectrumColor(red: 0.35, green: 0.60, blue: 0.75)),
                Zone(label: "A little on edge", color: SpectrumColor(red: 0.80, green: 0.65, blue: 0.35)),
                Zone(label: "Anxious", color: SpectrumColor(red: 0.80, green: 0.30, blue: 0.30)),
            ],
            breakpoints: [1.0 / 3.0, 2.0 / 3.0])),
    ]

    /// Whether the zones and breakpoints are usable: at least two non-blank zones,
    /// exactly one fewer breakpoint than zones, every breakpoint strictly between 0
    /// and 1, and strictly increasing.
    public var isValid: Bool {
        guard zones.count >= 2, breakpoints.count == zones.count - 1 else { return false }
        guard zones.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return false }
        guard breakpoints.allSatisfy({ $0 > 0 && $0 < 1 }) else { return false }
        return breakpoints == breakpoints.sorted() && Set(breakpoints).count == breakpoints.count
    }

    /// The index into `zones` that `value` (clamped to `0...1`) falls in, or nil when
    /// the configuration is invalid.
    public func zoneIndex(for value: Double) -> Int? {
        guard isValid else { return nil }
        let clamped = min(max(value, 0), 1)
        var index = 0
        for breakpoint in breakpoints where clamped >= breakpoint {
            index += 1
        }
        return min(index, zones.count - 1)
    }

    /// The zone `value` (clamped to `0...1`) falls in, or nil when the configuration
    /// is invalid.
    public func zone(for value: Double) -> Zone? {
        zoneIndex(for: value).map { zones[$0] }
    }
}
