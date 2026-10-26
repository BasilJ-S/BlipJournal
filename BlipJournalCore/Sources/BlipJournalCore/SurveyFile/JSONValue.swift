import Foundation

/// A parsed JSON document, kept untyped so the survey file reader can name every wrong
/// field by its path instead of stopping at the first `DecodingError`, and so the writer
/// can choose the order keys appear in.
enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    /// Members in the order they are written. Parsing makes no promise about order.
    case object([Member])

    struct Member: Sendable, Equatable {
        var key: String
        var value: JSONValue

        init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    /// The value of `key` when this is an object that has it.
    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }
}

extension JSONValue: Decodable {
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// `JSONDecoder` only decodes `Bool` from `true` and `false`, and never decodes a
    /// `Double` from either, so trying `Bool` before `Double` keeps the two apart.
    init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: AnyKey.self) {
            self = .object(try container.allKeys.map { key in
                Member(key.stringValue, try container.decode(JSONValue.self, forKey: key))
            })
        } else if var container = try? decoder.unkeyedContainer() {
            var items: [JSONValue] = []
            while !container.isAtEnd {
                items.append(try container.decode(JSONValue.self))
            }
            self = .array(items)
        } else {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }
    }
}

extension JSONValue {
    /// Pretty-printed with two-space indentation and keys in the order given, so the same
    /// value always produces the same text.
    func formatted(indent: String = "") -> String {
        let inner = indent + "  "
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            // Whole numbers print without a fraction; anything else uses Swift's shortest
            // representation that reads back as the same `Double`.
            if let whole = Int(exactly: value) { return String(whole) }
            return String(value)
        case .string(let value):
            return Self.quoted(value)
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            let lines = items.map { inner + $0.formatted(indent: inner) }
            return "[\n" + lines.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let members):
            guard !members.isEmpty else { return "{}" }
            let lines = members.map { inner + Self.quoted($0.key) + ": " + $0.value.formatted(indent: inner) }
            return "{\n" + lines.joined(separator: ",\n") + "\n" + indent + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
