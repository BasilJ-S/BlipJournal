import Foundation
import Testing
import BlipJournalCore

@Suite("SurveyFile decoding")
struct SurveyFileDecodeTests {
    private typealias Support = SurveyFileTestSupport

    @Test("a minimal hand-written file takes every default and gets identifiers")
    func minimalFile() throws {
        let contents = try Support.decode(
            #"{"formatVersion": 1, "name": "Water", "questions": [{"kind": "yesNo", "label": "Water?"}]}"#)
        #expect(contents.name == "Water")
        #expect(contents.sampling == SamplingConfig.default)
        #expect(contents.journalSummaryQuestionIds.isEmpty)
        let question = try #require(contents.questions.first)
        #expect(question.kind == .yesNo)
        #expect(question.label == "Water?")
        #expect(question.position == 0)
        #expect(question.isRequired == false)
        #expect(question.isArchived == false)
        #expect(question.allowsCustomOptions == false)
        #expect(question.options.isEmpty)
        #expect(question.scale == nil)
        #expect(question.spectrum == nil)
        #expect(!question.id.isEmpty)
    }

    @Test("absent sampling fields take the app defaults one by one")
    func partialSampling() throws {
        let contents = try Support.decode(Support.file(extra: #""sampling": {"promptsPerDay": 5, "windowEnd": "24:00"}"#))
        #expect(contents.sampling == SamplingConfig(promptsPerDay: 5, windowEndMinutes: 1440))
    }

    @Test("times are read as minutes after midnight")
    func times() throws {
        let contents = try Support.decode(Support.file(extra: #""sampling": {"windowStart": "07:05", "windowEnd": "21:30"}"#))
        #expect(contents.sampling.windowStartMinutes == 7 * 60 + 5)
        #expect(contents.sampling.windowEndMinutes == 21 * 60 + 30)
    }

    @Test("a scale question without a scale gets the default scale, and partial scales fill in")
    func scaleDefaults() throws {
        let bare = try Support.decode(Support.file(question: #"{"kind": "scale", "label": "Mood"}"#))
        #expect(bare.questions[0].scale == ScaleConfig())
        let partial = try Support.decode(Support.file(question: #"{"kind": "scale", "label": "Mood", "scale": {"max": 5, "maxLabel": ""}}"#))
        #expect(partial.questions[0].scale == ScaleConfig(min: 1, max: 5, minLabel: "Very unpleasant", maxLabel: ""))
    }

    @Test("a spectrum question without a spectrum gets the default spectrum")
    func spectrumDefault() throws {
        let contents = try Support.decode(Support.file(question: #"{"kind": "spectrum", "label": "Feeling"}"#))
        #expect(contents.questions[0].spectrum == SpectrumConfig())
    }

    @Test("three uncoloured, unsplit zones get exactly the default colours and thirds")
    func spectrumZoneDefaults() throws {
        let contents = try Support.decode(Support.file(question: #"""
            {"kind": "spectrum", "label": "Feeling", "spectrum": {"zones": [
                {"label": "Low"}, {"label": "Middle"}, {"label": "High"}]}}
            """#))
        let spectrum = try #require(contents.questions[0].spectrum)
        #expect(spectrum.breakpoints == SpectrumConfig().breakpoints)
        #expect(spectrum.zones.map(\.color) == SpectrumConfig().zones.map(\.color))
        #expect(spectrum.zones.map(\.label) == ["Low", "Middle", "High"])
    }

    @Test("two uncoloured zones split in half and take the two end colours")
    func twoZones() throws {
        let contents = try Support.decode(Support.file(question: #"""
            {"kind": "spectrum", "label": "Feeling", "spectrum": {"zones": [{"label": "Bad"}, {"label": "Good"}]}}
            """#))
        let spectrum = try #require(contents.questions[0].spectrum)
        let defaults = SpectrumConfig().zones.map(\.color)
        #expect(spectrum.breakpoints == [0.5])
        #expect(spectrum.zones.map(\.color) == [defaults[0], defaults[2]])
        #expect(spectrum.isValid)
    }

    @Test("colours are read from hex or from red, green and blue numbers, and breakpoints as given")
    func colours() throws {
        let contents = try Support.decode(Support.file(question: #"""
            {"kind": "spectrum", "label": "Feeling", "spectrum": {
                "zones": [{"label": "A", "color": "#FF0080"}, {"label": "B", "color": {"red": 0.1, "green": 1.02, "blue": 0}}],
                "breakpoints": [0.25]}}
            """#))
        let spectrum = try #require(contents.questions[0].spectrum)
        #expect(spectrum.zones[0].color == SpectrumColor(red: 1, green: 0, blue: 128.0 / 255))
        #expect(spectrum.zones[1].color == SpectrumColor(red: 0.1, green: 1.02, blue: 0))
        #expect(spectrum.breakpoints == [0.25])
    }

    @Test("questions and options keep file order, and expandable becomes allowsCustomOptions")
    func orderAndOptions() throws {
        let contents = try Support.decode(#"""
            {"formatVersion": 1, "name": "S", "questions": [
                {"kind": "text", "label": "First"},
                {"kind": "multiChoice", "label": "Second", "required": true, "expandable": true, "options": ["B", "A", "C"]},
                {"kind": "singleChoice", "label": "Third", "options": []}
            ]}
            """#)
        #expect(contents.questions.map(\.label) == ["First", "Second", "Third"])
        #expect(contents.questions.map(\.position) == [0, 1, 2])
        let choice = contents.questions[1]
        #expect(choice.isRequired)
        #expect(choice.allowsCustomOptions)
        #expect(choice.activeOptions.map(\.label) == ["B", "A", "C"])
        #expect(choice.options.map(\.position) == [0, 1, 2])
        #expect(Set(choice.options.map(\.id)).count == 3)
        #expect(contents.questions[2].options.isEmpty)
        #expect(contents.questions[2].allowsCustomOptions == false)
    }

    @Test("repeated option labels are kept as separate options, as the editor allows")
    func repeatedOptions() throws {
        let contents = try Support.decode(Support.file(question: #"{"kind": "multiChoice", "label": "Q", "options": ["A", "A"]}"#))
        let options = contents.questions[0].activeOptions
        #expect(options.map(\.label) == ["A", "A"])
        #expect(options[0].id != options[1].id)
    }

    @Test("journalSummary names questions by file id, in its own order")
    func journalSummaryByFileId() throws {
        let contents = try Support.decode(#"""
            {"formatVersion": 1, "name": "S", "journalSummary": ["b", "a"], "questions": [
                {"id": "a", "kind": "yesNo", "label": "A"},
                {"id": "b", "kind": "text", "label": "B"}
            ]}
            """#)
        #expect(contents.journalSummaryQuestionIds == [contents.questions[1].id, contents.questions[0].id])
    }

    @Test("without journalSummary the first scale or spectrum question summarises; [] means none")
    func journalSummaryDefault() throws {
        let questions = #"[{"kind": "text", "label": "Note"}, {"kind": "scale", "label": "Mood"}, {"kind": "spectrum", "label": "Feeling"}]"#
        let absent = try Support.decode(#"{"formatVersion": 1, "name": "S", "questions": "# + questions + "}")
        #expect(absent.journalSummaryQuestionIds == [absent.questions[1].id])
        let empty = try Support.decode(#"{"formatVersion": 1, "name": "S", "journalSummary": [], "questions": "# + questions + "}")
        #expect(empty.journalSummaryQuestionIds.isEmpty)
    }

    @Test("an empty question list is a valid, if empty, survey")
    func emptyQuestions() throws {
        let contents = try Support.decode(#"{"formatVersion": 1, "name": "Later", "questions": []}"#)
        #expect(contents.questions.isEmpty)
    }

    @Test("a $schema field is allowed and ignored")
    func schemaField() throws {
        let contents = try Support.decode(Support.file(extra: #""$schema": "https://example.com/survey-format.schema.json""#))
        #expect(contents.name == "Survey")
    }

    @Test("pasted text may carry prose and a Markdown code block around the JSON")
    func pastedText() throws {
        let text = """
            Here is your survey:

            ```json
            {"formatVersion": 1, "name": "Pasted", "questions": [{"kind": "text", "label": "Note"}]}
            ```

            Let me know if you want changes.
            """
        let contents = try SurveyFile.decode(text: text).get()
        #expect(contents.name == "Pasted")
    }

    @Test("a UTF-8 byte order mark is skipped")
    func byteOrderMark() throws {
        let json = #"{"formatVersion": 1, "name": "BOM", "questions": []}"#
        let contents = try SurveyFile.decode(Data([0xEF, 0xBB, 0xBF]) + Data(json.utf8)).get()
        #expect(contents.name == "BOM")
    }

    @Test("a file on disk is read through the same path as bytes")
    func fileOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("blipsurvey")
        try Data(#"{"formatVersion": 1, "name": "Disk", "questions": []}"#.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try SurveyFile.decode(contentsOf: url).get().name == "Disk")
    }

    @Test("a missing file is an issue, not a crash")
    func missingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard case .failure(let error) = SurveyFile.decode(contentsOf: url) else {
            Issue.record("a missing file decoded")
            return
        }
        #expect(error.issues.map(\.path) == [""])
    }

    @Test("every decode mints new identifiers")
    func freshIdentifiers() throws {
        let json = Support.file(question: #"{"kind": "singleChoice", "label": "Pick", "options": ["A"]}"#)
        let first = try Support.decode(json)
        let second = try Support.decode(json)
        #expect(first.questions[0].id != second.questions[0].id)
        #expect(first.questions[0].options[0].id != second.questions[0].options[0].id)
    }
}
