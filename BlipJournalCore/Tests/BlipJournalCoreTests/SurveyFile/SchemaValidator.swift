import Foundation
@testable import BlipJournalCore

/// The subset of JSON Schema 2020-12 that `docs/survey-format.schema.json` uses: `$ref`
/// into `$defs`, `type`, `const`, `enum`, `oneOf`, `properties`, `required`,
/// `additionalProperties: false`, `items`, `minItems`, `maxItems`, `uniqueItems`,
/// `minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum` and `pattern`.
/// Annotations such as `default` and `description` are ignored. A test checks the schema
/// uses no other keyword, so this cannot silently skip a rule.
struct SchemaValidator {
    static let supportedKeywords: Set<String> = [
        "$schema", "$id", "$ref", "$defs", "title", "description", "default",
        "type", "const", "enum", "oneOf", "properties", "required", "additionalProperties",
        "items", "minItems", "maxItems", "uniqueItems",
        "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "pattern",
    ]

    let root: JSONValue

    init(contentsOf url: URL) throws {
        root = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    /// Every rule `value` breaks, as `path: reason`. Empty means valid.
    func errors(in value: JSONValue) -> [String] {
        errors(value, schema: root, at: "$")
    }

    /// Every keyword used anywhere in the schema, so a test can check they are all supported.
    var keywordsUsed: Set<String> {
        var keywords: Set<String> = []
        func collect(_ schema: JSONValue) {
            guard case .object(let members) = schema else { return }
            for member in members {
                keywords.insert(member.key)
                switch member.key {
                case "properties", "$defs":
                    if case .object(let children) = member.value { children.forEach { collect($0.value) } }
                case "oneOf":
                    if case .array(let children) = member.value { children.forEach(collect) }
                case "items":
                    collect(member.value)
                default:
                    break
                }
            }
        }
        collect(root)
        return keywords
    }

    private func errors(_ value: JSONValue, schema: JSONValue, at path: String) -> [String] {
        var found: [String] = []
        if let ref = schema["$ref"]?.stringValue {
            let name = String(ref.dropFirst("#/$defs/".count))
            guard let target = root["$defs"]?[name] else { return ["\(path): unresolved \(ref)"] }
            found += errors(value, schema: target, at: path)
        }
        if let type = schema["type"]?.stringValue, !matches(value, type: type) {
            found.append("\(path): expected \(type)")
        }
        if let constant = schema["const"], value != constant {
            found.append("\(path): expected \(constant)")
        }
        if case .array(let allowed)? = schema["enum"], !allowed.contains(value) {
            found.append("\(path): not one of the allowed values")
        }
        if case .array(let choices)? = schema["oneOf"] {
            let passing = choices.filter { errors(value, schema: $0, at: path).isEmpty }.count
            if passing != 1 { found.append("\(path): matches \(passing) oneOf choices") }
        }
        switch value {
        case .number(let number):
            if let bound = schema["minimum"]?.numberValue, number < bound { found.append("\(path): below minimum") }
            if let bound = schema["maximum"]?.numberValue, number > bound { found.append("\(path): above maximum") }
            if let bound = schema["exclusiveMinimum"]?.numberValue, number <= bound { found.append("\(path): not above \(bound)") }
            if let bound = schema["exclusiveMaximum"]?.numberValue, number >= bound { found.append("\(path): not below \(bound)") }
        case .string(let text):
            if let pattern = schema["pattern"]?.stringValue, text.range(of: pattern, options: .regularExpression) == nil {
                found.append("\(path): does not match \(pattern)")
            }
        case .array(let items):
            if let bound = schema["minItems"]?.numberValue, Double(items.count) < bound { found.append("\(path): too few items") }
            if let bound = schema["maxItems"]?.numberValue, Double(items.count) > bound { found.append("\(path): too many items") }
            if schema["uniqueItems"] == .bool(true),
               items.indices.contains(where: { items[..<$0].contains(items[$0]) }) {
                found.append("\(path): repeated items")
            }
            if let itemSchema = schema["items"] {
                for (index, item) in items.enumerated() {
                    found += errors(item, schema: itemSchema, at: "\(path)[\(index)]")
                }
            }
        case .object(let members):
            if case .array(let required)? = schema["required"] {
                for case .string(let key) in required where value[key] == nil {
                    found.append("\(path): missing \(key)")
                }
            }
            for member in members {
                if let propertySchema = schema["properties"]?[member.key] {
                    found += errors(member.value, schema: propertySchema, at: "\(path).\(member.key)")
                } else if schema["additionalProperties"] == .bool(false) {
                    found.append("\(path): unexpected \(member.key)")
                }
            }
        case .null, .bool:
            break
        }
        return found
    }

    private func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string),
             ("boolean", .bool), ("null", .null), ("number", .number):
            true
        case ("integer", .number(let number)):
            number == number.rounded()
        default:
            false
        }
    }
}

extension JSONValue {
    var stringValue: String? {
        if case .string(let text) = self { text } else { nil }
    }

    var numberValue: Double? {
        if case .number(let number) = self { number } else { nil }
    }
}
