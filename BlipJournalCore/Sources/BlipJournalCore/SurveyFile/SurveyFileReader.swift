import Foundation

/// A place in a survey file, kept as components so it can be written both for the file
/// (`questions[2].scale.max`) and for a person ("Question 3, scale, max").
struct FieldPath {
    enum Component {
        case key(String)
        case index(Int)
    }

    var components: [Component] = []

    static func / (path: FieldPath, key: String) -> FieldPath {
        FieldPath(components: path.components + [.key(key)])
    }

    static func / (path: FieldPath, index: Int) -> FieldPath {
        FieldPath(components: path.components + [.index(index)])
    }

    var text: String {
        components.enumerated().map { offset, component -> String in
            switch component {
            case .key(let key): offset == 0 ? key : "." + key
            case .index(let index): "[\(index)]"
            }
        }.joined()
    }

    /// Lists count from 1 and take the singular of their field name: `questions[2]` is
    /// "Question 3". Other fields keep the name written in the file.
    var location: String {
        let listItemNames = [
            "questions": "Question", "options": "Option", "zones": "Zone",
            "breakpoints": "Breakpoint", "journalSummary": "Journal summary entry",
        ]
        var parts: [String] = []
        for component in components {
            switch component {
            case .key(let key):
                parts.append(key)
            case .index(let index):
                let list = parts.popLast() ?? ""
                parts.append("\(listItemNames[list] ?? list) \(index + 1)")
            }
        }
        return parts.isEmpty ? "The file" : parts.joined(separator: ", ")
    }
}

/// Reads a parsed survey file into ``SurveyFileContents``, collecting every issue rather
/// than stopping at the first, so a person can fix them all in one pass. The rules match
/// what the editor accepts, so anything the editor can build can be written and read
/// back.
struct SurveyFileReader {
    private(set) var issues: [SurveyFileError.Issue] = []

    private struct FileQuestion {
        var fileId: String?
        var question: Question
    }

    private static let kindList = QuestionKind.allCases.map(\.rawValue).joined(separator: ", ")

    /// Nil exactly when at least one issue was reported.
    mutating func readSurvey(_ root: JSONValue) -> SurveyFileContents? {
        let path = FieldPath()
        guard case .object = root else {
            report(path, "A survey file must be one JSON object, starting with { and ending with }.")
            return nil
        }
        // A newer version can mean fields this build has never heard of, so nothing else
        // is worth reporting until the version is one it reads.
        guard readFormatVersion(root["formatVersion"], at: path / "formatVersion") else { return nil }
        _ = object(root, at: path, allowed: [
            "$schema", "formatVersion", "name", "questions", "sampling", "journalSummary",
        ])
        _ = string(root["$schema"], at: path / "$schema")
        let name = requiredText(root["name"], at: path / "name")
        let questions = readQuestions(root["questions"], at: path / "questions")
        let sampling = readSampling(root["sampling"], at: path / "sampling")
        let summary = readJournalSummary(
            root["journalSummary"], at: path / "journalSummary", questions: questions)
        guard issues.isEmpty, let name else { return nil }
        return SurveyFileContents(
            name: name, questions: questions.map(\.question), sampling: sampling,
            journalSummaryQuestionIds: summary)
    }

    private mutating func report(_ path: FieldPath, _ message: String) {
        issues.append(SurveyFileError.Issue(path, message))
    }

    // MARK: Fields

    private mutating func readFormatVersion(_ value: JSONValue?, at path: FieldPath) -> Bool {
        let supported = SurveyFile.formatVersion
        guard let value else {
            report(path, "The file has no \"formatVersion\". Add \"formatVersion\": \(supported) at the top.")
            return false
        }
        guard case .number(let number) = value, let version = Int(exactly: number), version >= 1 else {
            report(path, "\"formatVersion\" must be a whole number, \(supported) for this version of the format.")
            return false
        }
        guard version <= supported else {
            report(path, """
                This file uses survey format version \(version), and this version of Blip Journal \
                reads up to version \(supported). Update Blip Journal, then import the file again.
                """)
            return false
        }
        return true
    }

    private mutating func readQuestions(_ value: JSONValue?, at path: FieldPath) -> [FileQuestion] {
        guard let value else {
            report(path, "The file has no \"questions\". Add a list of questions in [ ].")
            return []
        }
        guard let items = array(value, at: path) else { return [] }
        var questions: [FileQuestion] = []
        var seenIds: Set<String> = []
        for (index, item) in items.enumerated() {
            guard let question = readQuestion(item, at: path / index, position: index) else { continue }
            if let fileId = question.fileId, !seenIds.insert(fileId).inserted {
                report(path / index / "id", "Another question already has the id \"\(fileId)\". Each id must be different.")
            }
            questions.append(question)
        }
        return questions
    }

    private mutating func readQuestion(_ value: JSONValue, at path: FieldPath, position: Int) -> FileQuestion? {
        guard object(value, at: path, allowed: [
            "id", "kind", "label", "required", "expandable", "options", "scale", "spectrum",
        ]) else { return nil }
        let fileId = value["id"] == nil ? nil : requiredText(value["id"], at: path / "id")
        let kind = readKind(value["kind"], at: path / "kind")
        let label = requiredText(value["label"], at: path / "label")
        let isRequired = bool(value["required"], at: path / "required") ?? false
        guard let kind else { return nil }

        let kindOnlyFields: [(field: String, belongs: Bool, owners: String)] = [
            ("options", kind.usesOptions, "singleChoice and multiChoice questions"),
            ("expandable", kind.usesOptions, "singleChoice and multiChoice questions"),
            ("scale", kind == .scale, "scale questions"),
            ("spectrum", kind == .spectrum, "spectrum questions"),
        ]
        for entry in kindOnlyFields where !entry.belongs && value[entry.field] != nil {
            report(path / entry.field, """
                Only \(entry.owners) have "\(entry.field)". Remove it, or change "kind".
                """)
        }

        var question = Question(kind: kind, label: label ?? "", position: position, isRequired: isRequired)
        switch kind {
        case .scale:
            question.scale = readScale(value["scale"], at: path / "scale")
        case .spectrum:
            question.spectrum = readSpectrum(value["spectrum"], at: path / "spectrum")
        case .singleChoice, .multiChoice:
            question.allowsCustomOptions = bool(value["expandable"], at: path / "expandable") ?? false
            question.options = readOptions(value["options"], at: path / "options")
        case .yesNo, .text:
            break
        }
        return FileQuestion(fileId: fileId, question: question)
    }

    private mutating func readKind(_ value: JSONValue?, at path: FieldPath) -> QuestionKind? {
        guard let value else {
            report(path, "This field is missing. Use one of: \(Self.kindList).")
            return nil
        }
        guard let raw = string(value, at: path) else { return nil }
        guard let kind = QuestionKind(rawValue: raw) else {
            report(path, "\"\(raw)\" is not a question kind. Use one of: \(Self.kindList).")
            return nil
        }
        return kind
    }

    private mutating func readOptions(_ value: JSONValue?, at path: FieldPath) -> [ChoiceOption] {
        var labels: [String] = []
        for (index, item) in (array(value, at: path) ?? []).enumerated() {
            guard let label = requiredText(item, at: path / index) else { continue }
            if labels.contains(label) {
                report(path / index, "\"\(label)\" is already an option. Each option must be different.")
            } else {
                labels.append(label)
            }
        }
        return labels.enumerated().map { ChoiceOption(label: $1, position: $0) }
    }

    private mutating func readScale(_ value: JSONValue?, at path: FieldPath) -> ScaleConfig {
        let defaults = ScaleConfig()
        guard let value, object(value, at: path, allowed: ["min", "max", "minLabel", "maxLabel"]) else {
            return defaults
        }
        let before = issues.count
        let scale = ScaleConfig(
            min: integer(value["min"], at: path / "min") ?? defaults.min,
            max: integer(value["max"], at: path / "max") ?? defaults.max,
            minLabel: string(value["minLabel"], at: path / "minLabel") ?? defaults.minLabel,
            maxLabel: string(value["maxLabel"], at: path / "maxLabel") ?? defaults.maxLabel)
        if issues.count == before, !scale.isValid {
            report(path, """
                The scale runs from \(scale.min) to \(scale.max). "min" must be lower than "max", \
                and both must be from -100 to 100.
                """)
        }
        return scale
    }

    private mutating func readSpectrum(_ value: JSONValue?, at path: FieldPath) -> SpectrumConfig {
        guard let value, object(value, at: path, allowed: ["zones", "breakpoints"]) else {
            return SpectrumConfig()
        }
        guard let zoneValues = array(value["zones"], at: path / "zones") else {
            if value["zones"] == nil {
                report(path / "zones", "This field is missing. List the zones from left to right, at least two.")
            }
            return SpectrumConfig()
        }
        let count = zoneValues.count
        guard count >= 2 else {
            report(path / "zones", "A spectrum needs at least two zones.")
            return SpectrumConfig()
        }
        var zones: [SpectrumConfig.Zone] = []
        for (index, zoneValue) in zoneValues.enumerated() {
            zones.append(readZone(
                zoneValue, at: path / "zones" / index,
                defaultColor: Self.defaultZoneColor(index, of: count)))
        }
        guard let breakpointValues = array(value["breakpoints"], at: path / "breakpoints") else {
            return SpectrumConfig(zones: zones, breakpoints: (1..<count).map { Double($0) / Double(count) })
        }
        let before = issues.count
        var breakpoints: [Double] = []
        for (index, item) in breakpointValues.enumerated() {
            if let breakpoint = number(item, at: path / "breakpoints" / index) {
                breakpoints.append(breakpoint)
            }
        }
        guard issues.count == before else { return SpectrumConfig(zones: zones, breakpoints: breakpoints) }
        if breakpoints.count != count - 1 {
            report(path / "breakpoints", """
                \(count) zones need exactly \(count - 1) breakpoints, the boundaries between \
                neighbouring zones. Or leave "breakpoints" out to split the spectrum evenly.
                """)
        } else if !breakpoints.allSatisfy({ $0 > 0 && $0 < 1 }) {
            report(path / "breakpoints", "Each breakpoint must be between 0 and 1, not 0 or 1 themselves.")
        } else if zip(breakpoints, breakpoints.dropFirst()).contains(where: { $0 >= $1 }) {
            report(path / "breakpoints", "Breakpoints must increase from left to right, with no repeats.")
        }
        return SpectrumConfig(zones: zones, breakpoints: breakpoints)
    }

    private mutating func readZone(
        _ value: JSONValue, at path: FieldPath, defaultColor: SpectrumColor
    ) -> SpectrumConfig.Zone {
        guard object(value, at: path, allowed: ["label", "color"]) else {
            return SpectrumConfig.Zone(label: "", color: defaultColor)
        }
        let label = requiredText(value["label"], at: path / "label") ?? ""
        var color = defaultColor
        if let colorValue = value["color"], let parsed = readColor(colorValue, at: path / "color") {
            color = parsed
        }
        return SpectrumConfig.Zone(label: label, color: color)
    }

    /// `"#RRGGBB"`, or an object of `red`, `green` and `blue` numbers. The object form is
    /// what the writer uses, because it holds any colour the editor can pick exactly.
    private mutating func readColor(_ value: JSONValue, at path: FieldPath) -> SpectrumColor? {
        switch value {
        case .string(let text):
            let hex = text.dropFirst()
            guard text.hasPrefix("#"), hex.count == 6, hex.allSatisfy(\.isHexDigit),
                  let rgb = Int(hex, radix: 16) else { break }
            return SpectrumColor(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255)
        case .object:
            guard object(value, at: path, allowed: ["red", "green", "blue"]) else { return nil }
            var channels: [Double] = []
            for channel in ["red", "green", "blue"] {
                guard let channelValue = value[channel] else {
                    report(path / channel, "This field is missing. Give a number, usually from 0 to 1.")
                    continue
                }
                if let number = number(channelValue, at: path / channel) { channels.append(number) }
            }
            guard channels.count == 3 else { return nil }
            return SpectrumColor(red: channels[0], green: channels[1], blue: channels[2])
        default:
            break
        }
        report(path, """
            Write a colour as "#RRGGBB", such as "#D94040", or as red, green and blue numbers \
            from 0 to 1.
            """)
        return nil
    }

    /// The colour a zone gets when the file gives none: an even blend along the default
    /// spectrum's colours, so three uncoloured zones get exactly the default three.
    static func defaultZoneColor(_ index: Int, of count: Int) -> SpectrumColor {
        let stops = SpectrumConfig().zones.map(\.color)
        let scaled = Double(index) / Double(count - 1) * Double(stops.count - 1)
        let lower = min(Int(scaled), stops.count - 2)
        let fraction = scaled - Double(lower)
        let from = stops[lower], to = stops[lower + 1]
        func blend(_ start: Double, _ end: Double) -> Double { start * (1 - fraction) + end * fraction }
        return SpectrumColor(
            red: blend(from.red, to.red), green: blend(from.green, to.green), blue: blend(from.blue, to.blue))
    }

    private mutating func readSampling(_ value: JSONValue?, at path: FieldPath) -> SamplingConfig {
        let defaults = SamplingConfig.default
        guard let value, object(value, at: path, allowed: [
            "promptsPerDay", "windowStart", "windowEnd", "minGapMinutes", "expiryMinutes",
        ]) else { return defaults }
        let before = issues.count
        let sampling = SamplingConfig(
            promptsPerDay: integer(value["promptsPerDay"], at: path / "promptsPerDay") ?? defaults.promptsPerDay,
            windowStartMinutes: time(value["windowStart"], at: path / "windowStart") ?? defaults.windowStartMinutes,
            windowEndMinutes: time(value["windowEnd"], at: path / "windowEnd") ?? defaults.windowEndMinutes,
            minGapMinutes: integer(value["minGapMinutes"], at: path / "minGapMinutes") ?? defaults.minGapMinutes,
            expiryMinutes: integer(value["expiryMinutes"], at: path / "expiryMinutes") ?? defaults.expiryMinutes)
        guard issues.count == before else { return sampling }
        for error in sampling.validationErrors {
            switch error {
            case .promptsPerDayOutOfRange:
                report(path / "promptsPerDay", "Choose from 0 to 20 prompts a day.")
            case .windowOutOfRange:
                report(path / "windowEnd", """
                    The window must end later in the day than it starts. Use "24:00" for midnight \
                    at the end of the day.
                    """)
            case .minGapOutOfRange:
                report(path / "minGapMinutes", "Choose a gap from 0 to 1440 minutes.")
            case .gapDoesNotFit:
                report(path, """
                    \(sampling.promptsPerDay) prompts at least \(sampling.minGapMinutes) minutes apart \
                    don't fit in this window. Shorten the gap, widen the window, or ask for fewer prompts.
                    """)
            case .expiryOutOfRange:
                report(path / "expiryMinutes", "Choose an expiry from 1 to 240 minutes.")
            }
        }
        return sampling
    }

    /// Minutes after midnight from `"HH:MM"`, 24-hour, `"24:00"` allowed for the end of
    /// the day.
    private mutating func time(_ value: JSONValue?, at path: FieldPath) -> Int? {
        guard let value, let text = string(value, at: path) else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 2,
           parts.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
           let hours = Int(parts[0]), let minutes = Int(parts[1]),
           minutes < 60, hours < 24 || (hours == 24 && minutes == 0) {
            return hours * 60 + minutes
        }
        report(path, """
            Write a time as "HH:MM" on a 24-hour clock, such as "09:00" or "21:30". "24:00" is \
            midnight at the end of the day.
            """)
        return nil
    }

    private mutating func readJournalSummary(
        _ value: JSONValue?, at path: FieldPath, questions: [FileQuestion]
    ) -> [String] {
        guard let value else {
            return Survey.defaultJournalSummaryQuestionIds(for: questions.map(\.question))
        }
        guard let items = array(value, at: path) else { return [] }
        if items.count > 2 {
            report(path, "The Journal shows at most two answers per entry. List no more than two question ids.")
        }
        var ids: [String] = []
        for (index, item) in items.prefix(2).enumerated() {
            guard let fileId = requiredText(item, at: path / index) else { continue }
            guard let match = questions.first(where: { $0.fileId == fileId }) else {
                report(path / index, """
                    No question has the id "\(fileId)". Add "id": "\(fileId)" to the question you mean.
                    """)
                continue
            }
            if ids.contains(match.question.id) {
                report(path / index, "\"\(fileId)\" is listed twice.")
            } else {
                ids.append(match.question.id)
            }
        }
        return ids
    }

    // MARK: Values

    /// Whether `value` is an object, reporting it if not, and reporting every field not
    /// in `allowed`, so a misspelt field is caught instead of silently defaulted.
    private mutating func object(_ value: JSONValue, at path: FieldPath, allowed: [String]) -> Bool {
        guard case .object(let members) = value else {
            report(path, "This must be an object in curly braces, { }.")
            return false
        }
        for key in members.map(\.key).filter({ !allowed.contains($0) }).sorted() {
            report(path / key, """
                Blip Journal doesn't know the field "\(key)". Check its spelling against the \
                survey format guide, or remove it.
                """)
        }
        return true
    }

    /// Nil when absent or reported.
    private mutating func array(_ value: JSONValue?, at path: FieldPath) -> [JSONValue]? {
        guard let value else { return nil }
        guard case .array(let items) = value else {
            report(path, "This must be a list in square brackets, [ ].")
            return nil
        }
        return items
    }

    /// Nil when absent or reported.
    private mutating func string(_ value: JSONValue?, at path: FieldPath) -> String? {
        guard let value else { return nil }
        guard case .string(let text) = value else {
            report(path, "This must be text in double quotation marks.")
            return nil
        }
        return text
    }

    /// Text that must be present and not blank. Nil when reported.
    private mutating func requiredText(_ value: JSONValue?, at path: FieldPath) -> String? {
        guard let value else {
            report(path, "This field is missing.")
            return nil
        }
        guard let text = string(value, at: path) else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            report(path, "This is blank. Write some text.")
            return nil
        }
        return text
    }

    /// Nil when absent or reported.
    private mutating func bool(_ value: JSONValue?, at path: FieldPath) -> Bool? {
        guard let value else { return nil }
        guard case .bool(let flag) = value else {
            report(path, "This must be true or false, without quotation marks.")
            return nil
        }
        return flag
    }

    /// Nil when absent or reported.
    private mutating func integer(_ value: JSONValue?, at path: FieldPath) -> Int? {
        guard let value else { return nil }
        guard case .number(let number) = value, let whole = Int(exactly: number) else {
            report(path, "This must be a whole number, without quotation marks.")
            return nil
        }
        return whole
    }

    /// Nil when absent or reported.
    private mutating func number(_ value: JSONValue?, at path: FieldPath) -> Double? {
        guard let value else { return nil }
        guard case .number(let number) = value else {
            report(path, "This must be a number, without quotation marks.")
            return nil
        }
        return number
    }
}
