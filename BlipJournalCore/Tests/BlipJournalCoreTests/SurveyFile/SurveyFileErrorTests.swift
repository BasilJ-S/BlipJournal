import Foundation
import Testing
import BlipJournalCore

/// One file that must be rejected, and a path one of its issues must name.
struct RejectedSurveyFile: Sendable, CustomTestStringConvertible {
    let name: String
    let json: String
    let path: String

    var testDescription: String { name }

    private static func question(_ json: String) -> String { SurveyFileTestSupport.file(question: json) }
    private static func extra(_ json: String) -> String { SurveyFileTestSupport.file(extra: json) }
    private static func spectrum(_ json: String) -> String {
        question(#"{"kind": "spectrum", "label": "Feeling", "spectrum": "# + json + "}")
    }

    static let all: [RejectedSurveyFile] = [
        .init(name: "not JSON", json: #"{"formatVersion": 1,"#, path: ""),
        .init(name: "top level is a list", json: "[]", path: ""),
        .init(name: "no formatVersion", json: #"{"name": "S", "questions": []}"#, path: "formatVersion"),
        .init(name: "formatVersion as text", json: #"{"formatVersion": "1", "name": "S", "questions": []}"#, path: "formatVersion"),
        .init(name: "formatVersion 0", json: #"{"formatVersion": 0, "name": "S", "questions": []}"#, path: "formatVersion"),
        .init(name: "unknown top-level field", json: #"{"formatVersion": 1, "nmae": "S", "questions": []}"#, path: "nmae"),
        .init(name: "no name", json: #"{"formatVersion": 1, "questions": []}"#, path: "name"),
        .init(name: "blank name", json: #"{"formatVersion": 1, "name": "  ", "questions": []}"#, path: "name"),
        .init(name: "no questions", json: #"{"formatVersion": 1, "name": "S"}"#, path: "questions"),
        .init(name: "questions not a list", json: #"{"formatVersion": 1, "name": "S", "questions": {}}"#, path: "questions"),
        .init(name: "question not an object", json: question(#""Mood""#), path: "questions[0]"),
        .init(name: "misspelt question field", json: question(#"{"kind": "text", "label": "Note", "requried": true}"#), path: "questions[0].requried"),
        .init(name: "no kind", json: question(#"{"label": "Note"}"#), path: "questions[0].kind"),
        .init(name: "unknown kind", json: question(#"{"kind": "slider", "label": "Note"}"#), path: "questions[0].kind"),
        .init(name: "no label", json: question(#"{"kind": "text"}"#), path: "questions[0].label"),
        .init(name: "required as text", json: question(#"{"kind": "text", "label": "Note", "required": "yes"}"#), path: "questions[0].required"),
        .init(name: "blank id", json: question(#"{"id": "", "kind": "text", "label": "Note"}"#), path: "questions[0].id"),
        .init(name: "options on a text question", json: question(#"{"kind": "text", "label": "Note", "options": ["A"]}"#), path: "questions[0].options"),
        .init(name: "expandable on a yes/no question", json: question(#"{"kind": "yesNo", "label": "Q", "expandable": true}"#), path: "questions[0].expandable"),
        .init(name: "scale on a yes/no question", json: question(#"{"kind": "yesNo", "label": "Q", "scale": {}}"#), path: "questions[0].scale"),
        .init(name: "spectrum on a scale question", json: question(#"{"kind": "scale", "label": "Q", "spectrum": {}}"#), path: "questions[0].spectrum"),
        .init(name: "options not a list", json: question(#"{"kind": "singleChoice", "label": "Q", "options": "A, B"}"#), path: "questions[0].options"),
        .init(name: "blank option", json: question(#"{"kind": "singleChoice", "label": "Q", "options": [" "]}"#), path: "questions[0].options[0]"),
        .init(name: "repeated option", json: question(#"{"kind": "multiChoice", "label": "Q", "options": ["A", "A"]}"#), path: "questions[0].options[1]"),
        .init(name: "scale min above max", json: question(#"{"kind": "scale", "label": "Q", "scale": {"min": 5, "max": 1}}"#), path: "questions[0].scale"),
        .init(name: "scale beyond 100", json: question(#"{"kind": "scale", "label": "Q", "scale": {"max": 101}}"#), path: "questions[0].scale"),
        .init(name: "fractional scale bound", json: question(#"{"kind": "scale", "label": "Q", "scale": {"min": 2.5}}"#), path: "questions[0].scale.min"),
        .init(name: "misspelt scale field", json: question(#"{"kind": "scale", "label": "Q", "scale": {"maximum": 5}}"#), path: "questions[0].scale.maximum"),
        .init(name: "spectrum without zones", json: spectrum(#"{"breakpoints": [0.5]}"#), path: "questions[0].spectrum.zones"),
        .init(name: "spectrum with one zone", json: spectrum(#"{"zones": [{"label": "Only"}]}"#), path: "questions[0].spectrum.zones"),
        .init(name: "blank zone label", json: spectrum(#"{"zones": [{"label": "A"}, {"label": ""}]}"#), path: "questions[0].spectrum.zones[1].label"),
        .init(name: "colour by name", json: spectrum(#"{"zones": [{"label": "A", "color": "red"}, {"label": "B"}]}"#), path: "questions[0].spectrum.zones[0].color"),
        .init(name: "colour missing a channel", json: spectrum(#"{"zones": [{"label": "A", "color": {"red": 1, "green": 0}}, {"label": "B"}]}"#), path: "questions[0].spectrum.zones[0].color.blue"),
        .init(name: "too many breakpoints", json: spectrum(#"{"zones": [{"label": "A"}, {"label": "B"}], "breakpoints": [0.3, 0.6]}"#), path: "questions[0].spectrum.breakpoints"),
        .init(name: "breakpoint at the end", json: spectrum(#"{"zones": [{"label": "A"}, {"label": "B"}], "breakpoints": [1]}"#), path: "questions[0].spectrum.breakpoints"),
        .init(name: "breakpoints going down", json: spectrum(#"{"zones": [{"label": "A"}, {"label": "B"}, {"label": "C"}], "breakpoints": [0.6, 0.3]}"#), path: "questions[0].spectrum.breakpoints"),
        .init(name: "repeated question id", json: #"{"formatVersion": 1, "name": "S", "questions": [{"id": "a", "kind": "text", "label": "A"}, {"id": "a", "kind": "text", "label": "B"}]}"#, path: "questions[1].id"),
        .init(name: "sampling not an object", json: extra(#""sampling": 3"#), path: "sampling"),
        .init(name: "misspelt sampling field", json: extra(#""sampling": {"windowStrat": "08:00"}"#), path: "sampling.windowStrat"),
        .init(name: "time in words", json: extra(#""sampling": {"windowStart": "9am"}"#), path: "sampling.windowStart"),
        .init(name: "time past midnight", json: extra(#""sampling": {"windowEnd": "24:30"}"#), path: "sampling.windowEnd"),
        .init(name: "window ending before it starts", json: extra(#""sampling": {"windowStart": "20:00", "windowEnd": "08:00"}"#), path: "sampling.windowEnd"),
        .init(name: "too many prompts", json: extra(#""sampling": {"promptsPerDay": 21}"#), path: "sampling.promptsPerDay"),
        .init(name: "an absurd number of prompts", json: extra(#""sampling": {"promptsPerDay": 1000000000000000}"#), path: "sampling.promptsPerDay"),
        .init(name: "negative gap", json: extra(#""sampling": {"minGapMinutes": -5}"#), path: "sampling.minGapMinutes"),
        .init(name: "prompts that do not fit", json: extra(#""sampling": {"promptsPerDay": 10, "minGapMinutes": 120}"#), path: "sampling"),
        .init(name: "no expiry", json: extra(#""sampling": {"expiryMinutes": 0}"#), path: "sampling.expiryMinutes"),
        .init(name: "summary not a list", json: extra(#""journalSummary": "note""#), path: "journalSummary"),
        .init(name: "summary of three", json: extra(#""journalSummary": ["note", "note", "note"]"#), path: "journalSummary"),
        .init(name: "summary naming no question", json: extra(#""journalSummary": ["mood"]"#), path: "journalSummary[0]"),
        .init(name: "summary naming one question twice", json: extra(#""journalSummary": ["note", "note"]"#), path: "journalSummary[1]"),
    ]
}

@Suite("SurveyFile validation")
struct SurveyFileErrorTests {
    private typealias Support = SurveyFileTestSupport

    @Test("each broken file is rejected with an issue at the broken field", arguments: RejectedSurveyFile.all)
    func rejected(_ file: RejectedSurveyFile) {
        let issues = Support.issues(file.json)
        #expect(issues.map(\.path).contains(file.path), "issues: \(issues.map(\.path))")
        #expect(issues.allSatisfy { !$0.message.isEmpty && !$0.location.isEmpty })
    }

    @Test("a newer formatVersion is the only issue reported, and asks for an update")
    func newerVersion() throws {
        let issues = Support.issues(#"{"formatVersion": 2, "name": 7, "somethingNew": true}"#)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.path == "formatVersion")
        #expect(issue.message.contains("version 2"))
        #expect(issue.message.contains("Update Blip Journal"))
    }

    @Test("every issue in a file is reported, in file order")
    func everyIssue() {
        let issues = Support.issues(#"""
            {"formatVersion": 1, "name": "", "questions": [
                {"kind": "text", "label": "Fine"},
                {"kind": "scale", "label": "Bad", "scale": {"min": 3, "max": 3}},
                {"kind": "nope", "label": "Worse"}
            ], "sampling": {"expiryMinutes": 500}}
            """#)
        #expect(issues.map(\.path) == ["name", "questions[1].scale", "questions[2].kind", "sampling.expiryMinutes"])
    }

    @Test("a field that failed to read does not also fail the rule that depends on it")
    func noCascade() {
        let issues = Support.issues(Support.file(question: #"{"kind": "scale", "label": "Q", "scale": {"min": "1", "max": 0}}"#))
        #expect(issues.map(\.path) == ["questions[0].scale.min"])
    }

    @Test("locations name list items from 1 for people")
    func locations() {
        let cases: [(json: String, location: String)] = [
            (#"{"formatVersion": 1,"#, "The file"),
            (#"{"formatVersion": 1, "questions": []}"#, "name"),
            (Support.file(question: #"{"kind": "scale", "label": "Q", "scale": {"max": 1.5}}"#), "Question 1, scale, max"),
            (Support.file(question: #"{"kind": "spectrum", "label": "Q", "spectrum": {"zones": [{"label": "A"}, {}]}}"#), "Question 1, spectrum, Zone 2, label"),
            (Support.file(question: #"{"kind": "singleChoice", "label": "Q", "options": ["A", 1]}"#), "Question 1, Option 2"),
            (Support.file(extra: #""journalSummary": ["x"]"#), "Journal summary entry 1"),
            (Support.file(extra: #""sampling": {"windowStart": "8"}"#), "sampling, windowStart"),
        ]
        for (json, location) in cases {
            #expect(Support.issues(json).map(\.location) == [location])
        }
    }

    @Test("messages say what to do in plain language")
    func messages() throws {
        let unknown = try #require(Support.issues(Support.file(question: #"{"kind": "text", "label": "N", "requried": true}"#)).first)
        #expect(unknown.message.contains("\"requried\""))
        let kind = try #require(Support.issues(Support.file(question: #"{"kind": "slider", "label": "N"}"#)).first)
        #expect(kind.message.contains("singleChoice"))
        let time = try #require(Support.issues(Support.file(extra: #""sampling": {"windowStart": "9am"}"#)).first)
        #expect(time.message.contains("HH:MM"))
    }
}
