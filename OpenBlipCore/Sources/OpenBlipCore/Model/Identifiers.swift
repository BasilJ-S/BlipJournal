import Foundation

/// Generator for the identifiers every entity in the model is keyed by.
///
/// Identifiers are plain `String`s holding a lowercase, hyphenated UUID. A string
/// keeps the model free of any database or platform type, survives JSON export
/// unchanged, and can be used as a SQLite `TEXT PRIMARY KEY` without conversion.
///
/// Named `Identifier` rather than `ID` because `Identifiable` gives every conforming
/// type an `ID` associated type, which would shadow this enum inside the body of every
/// type in the model.
public enum Identifier {
    /// A freshly generated identifier.
    ///
    /// Lowercased so that every identifier the app writes has one canonical spelling;
    /// comparisons and CSV exports stay stable.
    public static func make() -> String {
        UUID().uuidString.lowercased()
    }
}
