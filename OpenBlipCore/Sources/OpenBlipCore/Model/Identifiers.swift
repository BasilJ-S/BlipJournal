import Foundation

/// Generator for the identifiers every entity in the model is keyed by.
///
/// Identifiers are plain `String`s holding a lowercase, hyphenated UUID. A string
/// keeps the model free of any database or platform type, survives JSON export
/// unchanged, and can be used as a SQLite `TEXT PRIMARY KEY` without conversion.
public enum ID {
    /// A freshly generated identifier.
    ///
    /// Lowercased so that every identifier the app writes has one canonical spelling;
    /// comparisons and CSV exports stay stable.
    public static func make() -> String {
        UUID().uuidString.lowercased()
    }
}

/// Another spelling of ``ID``, for use inside `Identifiable` types.
///
/// `Identifiable` gives every conforming type an `ID` associated type, and inside that
/// type's body it shadows the ``ID`` enum, so `ID.make()` does not compile there.
/// Module-qualifying it does not help either, because the ``OpenBlipCore`` enum shadows
/// the module name. This alias is what the memberwise initialisers say instead. It is
/// public only because a public default argument cannot reference an internal name;
/// prefer ``ID`` when writing new call sites.
public typealias Identifier = ID
