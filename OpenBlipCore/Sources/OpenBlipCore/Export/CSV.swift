import Foundation

/// RFC 4180 field escaping and row joining.
///
/// Internal on purpose: the exporters are the only writers, and the app never touches
/// individual fields. Tests reach it through `@testable import`.
enum CSV {
    /// The line terminator of every row, header included.
    static let lineTerminator = "\r\n"

    /// Quotes `field` when RFC 4180 requires it, otherwise returns it unchanged.
    ///
    /// A field is quoted when it contains a comma, a double quote, CR or LF, or begins
    /// or ends with whitespace; double quotes inside are doubled. An empty field stays
    /// empty. Everything works on Unicode scalars, not `Character`s: `"\r\n"` is a
    /// single grapheme cluster in Swift, and a quote followed by a combining mark is
    /// one `Character` that a `Character`-level scan or replace would not see as a quote.
    static func escape(_ field: String) -> String {
        let scalars = field.unicodeScalars
        guard let first = scalars.first, let last = scalars.last else { return "" }
        let hasSpecial = scalars.contains { scalar in
            scalar == "," || scalar == "\"" || scalar == "\r" || scalar == "\n"
        }
        let hasEdgeWhitespace = first.properties.isWhitespace || last.properties.isWhitespace
        guard hasSpecial || hasEdgeWhitespace else { return field }
        var escaped = String.UnicodeScalarView()
        escaped.append("\"")
        for scalar in scalars {
            if scalar == "\"" {
                escaped.append("\"")
            }
            escaped.append(scalar)
        }
        escaped.append("\"")
        return String(escaped)
    }

    /// `fields`, each escaped, joined by commas and terminated by CRLF.
    static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",") + lineTerminator
    }
}
