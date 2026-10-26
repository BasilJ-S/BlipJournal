import Foundation
import Testing
@testable import BlipJournalCore

/// Keeps `docs/survey-format.md` and `docs/survey-format.schema.json` honest: the
/// published example and the AI prompt's example import, and the schema accepts what
/// the app writes.
@Suite("SurveyFile documentation")
struct SurveyFileDocsTests {
    private typealias Support = SurveyFileTestSupport

    private static let docs = Support.repositoryRoot.appendingPathComponent("docs")

    private static func spec() throws -> String {
        try String(contentsOf: docs.appendingPathComponent("survey-format.md"), encoding: .utf8)
    }

    private static func validator() throws -> SchemaValidator {
        try SchemaValidator(contentsOf: docs.appendingPathComponent("survey-format.schema.json"))
    }

    /// The body of the first fenced code block after `marker`.
    private static func block(after marker: String, in markdown: String) throws -> String {
        let markerEnd = try #require(markdown.range(of: marker)).upperBound
        let fence = try #require(markdown.range(of: "```", range: markerEnd..<markdown.endIndex))
        let languageLineEnd = try #require(markdown[fence.upperBound...].firstIndex(of: "\n"))
        let bodyStart = markdown.index(after: languageLineEnd)
        let closing = try #require(markdown.range(of: "\n```", range: bodyStart..<markdown.endIndex))
        return String(markdown[bodyStart..<closing.lowerBound])
    }

    private static func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    @Test("the complete example validates against the schema and imports")
    func completeExample() throws {
        let example = try Self.block(after: "<!-- complete-example", in: Self.spec())
        #expect(try Self.validator().errors(in: Self.json(example)) == [])
        let contents = try SurveyFile.decode(Data(example.utf8)).get()
        #expect(Set(contents.questions.map(\.kind)) == Set(QuestionKind.allCases))
        #expect(contents.journalSummaryQuestionIds.count == 2)
        let store = try Store.inMemory()
        let imported = try store.importSurvey(contents)
        #expect(imported.activeQuestions.count == contents.questions.count)
    }

    @Test("the example inside the AI prompt validates and imports as pasted text")
    func promptExample() throws {
        let prompt = try Self.block(after: "<!-- ai-prompt", in: Self.spec())
        let start = try #require(prompt.firstIndex(of: "{"))
        let end = try #require(prompt.lastIndex(of: "}"))
        #expect(try Self.validator().errors(in: Self.json(String(prompt[start...end]))) == [])
        let contents = try SurveyFile.decode(text: prompt).get()
        #expect(!contents.questions.isEmpty)
    }

    @Test("files the app writes validate against the schema")
    func exportsValidate() throws {
        let validator = try Self.validator()
        let template = SurveyTemplate.makeDefault()
        var scaleSurvey = template
        scaleSurvey.questions.append(Question(
            kind: .scale, label: "Energy", position: 6, scale: ScaleConfig(min: 0, max: 10, minLabel: "", maxLabel: "Max")))
        for survey in [template, scaleSurvey, Survey(name: "Empty")] {
            let written = try JSONDecoder().decode(JSONValue.self, from: SurveyFile.encode(survey))
            #expect(validator.errors(in: written) == [])
        }
    }

    @Test("the schema rejects what the reader rejects for shape")
    func schemaRejects() throws {
        let validator = try Self.validator()
        let broken = [
            #"{"formatVersion": 2, "name": "S", "questions": []}"#,
            #"{"formatVersion": 1, "questions": []}"#,
            Support.file(question: #"{"kind": "text", "label": "Note", "requried": true}"#),
            Support.file(question: #"{"kind": "slider", "label": "Note"}"#),
            Support.file(extra: #""sampling": {"windowStart": "9am"}"#),
            Support.file(extra: #""journalSummary": ["a", "b", "c"]"#),
            Support.file(question: #"{"kind": "spectrum", "label": "F", "spectrum": {"zones": [{"label": "A", "color": "red"}, {"label": "B"}]}}"#),
        ]
        for file in broken {
            #expect(!validator.errors(in: try Self.json(file)).isEmpty, "schema accepted \(file)")
            #expect(!Support.issues(file).isEmpty, "reader accepted \(file)")
        }
    }

    @Test("the schema uses only keywords the test validator checks")
    func schemaKeywords() throws {
        #expect(try Self.validator().keywordsUsed.subtracting(SchemaValidator.supportedKeywords) == [])
    }

    @Test("every field in the schema is documented in the spec")
    func everyFieldDocumented() throws {
        let spec = try Self.spec()
        let validator = try Self.validator()
        var schemas = [validator.root]
        if case .object(let definitions)? = validator.root["$defs"] {
            schemas += definitions.map(\.value)
        }
        for schema in schemas {
            guard case .object(let properties)? = schema["properties"] else { continue }
            for field in properties.map(\.key) {
                #expect(spec.contains("| `\(field)` |"), "\(field) has no row in docs/survey-format.md")
            }
        }
    }
}
