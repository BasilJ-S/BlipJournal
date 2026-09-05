import Foundation

/// One entry in the rename history of a question or an option.
///
/// Definitions are insert-only, so a rename appends a version rather than replacing a
/// row. Storage turns those rows into these, and exports use them to show the wording
/// that was on screen when an answer was given.
public struct LabelVersion: Sendable, Equatable, Hashable, Codable {
    /// The wording this version introduced.
    public var label: String
    /// When this version became current.
    public var validFrom: Date

    /// Creates a label version.
    public init(label: String, validFrom: Date) {
        self.label = label
        self.validFrom = validFrom
    }
}

extension Array where Element == LabelVersion {
    /// Newest version with `validFrom <= date`. Falls back to the earliest version when
    /// `date` precedes all of them. Nil only when the array is empty.
    ///
    /// The fallback matters because an answer can carry a timestamp slightly before the
    /// first recorded version (clock changes, or a definition backfilled by a
    /// migration); showing the oldest known wording beats showing nothing. The receiver
    /// may be in any order.
    public func label(at date: Date) -> String? {
        guard !isEmpty else { return nil }
        let ordered = sorted { $0.validFrom < $1.validFrom }
        let current = ordered.last { $0.validFrom <= date }
        return (current ?? ordered[0]).label
    }
}
