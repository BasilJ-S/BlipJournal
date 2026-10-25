import Foundation
import Testing
import BlipJournalCore

@Suite("SurveyFile encoding, round trip and import")
struct SurveyFileRoundTripTests {
    private typealias Support = SurveyFileTestSupport
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Every kind, archived definitions, two summary questions in reverse order, a paused
    /// non-default schedule, colours outside 0...1 and text that needs escaping.
    private static func elaborateSurvey() -> Survey {
        let scale = Question(
            kind: .scale, label: "Energy", position: 4, isRequired: true,
            scale: ScaleConfig(min: -3, max: 3, minLabel: "", maxLabel: "Wired"))
        let spectrum = Question(
            kind: .spectrum, label: "Feeling", position: 7,
            spectrum: SpectrumConfig(
                zones: [
                    .init(label: "Low", color: SpectrumColor(red: 1.02, green: -0.01, blue: 0.123456789)),
                    .init(label: "High", color: SpectrumColor(red: 0.2, green: 0.7, blue: 0.4)),
                ],
                breakpoints: [1.0 / 3.0]))
        let choice = Question(
            kind: .multiChoice, label: "With \"whom\"?\nPick any", position: 9,
            allowsCustomOptions: true,
            options: [
                ChoiceOption(label: "Partner", position: 3),
                ChoiceOption(label: "Retired", position: 1, isArchived: true),
                ChoiceOption(label: "Alone ☕️", position: 0),
                ChoiceOption(label: "Back\\slash\ttab", position: 5),
            ])
        let empty = Question(kind: .singleChoice, label: "Not set up yet", position: 10)
        let archived = Question(kind: .yesNo, label: "Old question", position: 1, isArchived: true)
        let text = Question(kind: .text, label: "Anything else?", position: 12)
        let yesNo = Question(kind: .yesNo, label: "Caffeine?", position: 11)
        return Survey(
            name: "Study \\ week 1",
            sampling: SamplingConfig(
                promptsPerDay: 6, windowStartMinutes: 7 * 60 + 15, windowEndMinutes: 1440,
                minGapMinutes: 45, expiryMinutes: 90, isEnabled: false),
            notificationPreview: .custom(message: "Not exported"),
            journalSummaryQuestionIds: [spectrum.id, scale.id],
            questions: [text, choice, archived, spectrum, empty, scale, yesNo])
    }

    @Test("the default survey survives export and import unchanged")
    func defaultTemplateRoundTrip() throws {
        let survey = SurveyTemplate.makeDefault(now: now)
        let contents = try SurveyFile.decode(SurveyFile.encode(survey)).get()
        #expect(Support.Definition(contents) == Support.Definition(survey))
    }

    @Test("an elaborate survey survives export and import unchanged")
    func elaborateRoundTrip() throws {
        let survey = Self.elaborateSurvey()
        let contents = try SurveyFile.decode(SurveyFile.encode(survey)).get()
        #expect(Support.Definition(contents) == Support.Definition(survey))
        #expect(contents.questions.map(\.label) == survey.activeQuestions.map(\.label))
        #expect(!contents.questions.contains { $0.label == "Old question" })
        #expect(contents.questions[2].activeOptions.map(\.label) == ["Alone ☕️", "Partner", "Back\\slash\ttab"])
    }

    @Test("export leaves out archived definitions, sampling state and the notification preview")
    func exportLeavesOut() throws {
        let text = String(decoding: SurveyFile.encode(Self.elaborateSurvey()), as: UTF8.self)
        #expect(!text.contains("Old question"))
        #expect(!text.contains("Retired"))
        #expect(!text.contains("Not exported"))
        #expect(!text.contains("isEnabled"))
        #expect(!text.contains("allowsCustomOptions"))
    }

    @Test("export escapes text so it reads back exactly")
    func escaping() {
        let text = String(decoding: SurveyFile.encode(Self.elaborateSurvey()), as: UTF8.self)
        #expect(text.contains(#""label": "With \"whom\"?\nPick any""#))
        #expect(text.contains(#""Back\\slash\ttab""#))
        #expect(text.contains(#""name": "Study \\ week 1""#))
    }

    @Test("export is byte-for-byte stable and readable")
    func goldenFile() throws {
        let yesNo = Question(kind: .yesNo, label: "Water?", position: 0)
        let choice = Question(
            kind: .singleChoice, label: "Where?", position: 1, isRequired: true, allowsCustomOptions: true,
            options: [ChoiceOption(label: "Home", position: 0), ChoiceOption(label: "Out", position: 1)])
        let survey = Survey(name: "Water", journalSummaryQuestionIds: [choice.id], questions: [choice, yesNo])
        let expected = """
            {
              "formatVersion": 1,
              "name": "Water",
              "sampling": {
                "promptsPerDay": 3,
                "windowStart": "09:00",
                "windowEnd": "23:00",
                "minGapMinutes": 60,
                "expiryMinutes": 20
              },
              "journalSummary": [
                "q2"
              ],
              "questions": [
                {
                  "id": "q1",
                  "kind": "yesNo",
                  "label": "Water?",
                  "required": false
                },
                {
                  "id": "q2",
                  "kind": "singleChoice",
                  "label": "Where?",
                  "required": true,
                  "expandable": true,
                  "options": [
                    "Home",
                    "Out"
                  ]
                }
              ]
            }

            """
        #expect(String(decoding: SurveyFile.encode(survey), as: UTF8.self) == expected)
        #expect(SurveyFile.encode(survey) == SurveyFile.encode(survey))
    }

    @Test("import adds a paused, private survey with the file's definition and touches nothing else")
    func importAddsSurvey() throws {
        let store = try Store.inMemory()
        let existing = try store.createSurvey(
            name: "Existing", sampling: .default, questions: [Question(kind: .text, label: "Note", position: 0)], now: now)
        let contents = try SurveyFile.decode(SurveyFile.encode(Self.elaborateSurvey())).get()

        let imported = try store.importSurvey(contents, now: now.addingTimeInterval(1))

        #expect(imported.sampling.isEnabled == false)
        #expect(imported.notificationPreview == .private)
        #expect(imported.isArchived == false)
        #expect(Support.Definition(imported) == Support.Definition(contents))
        #expect(try store.surveys(includeArchived: true).map(\.id) == [existing.id, imported.id])
        #expect(try store.survey(existing.id) == existing)
    }

    @Test("the same contents can be imported twice, as two unrelated surveys")
    func importTwice() throws {
        let store = try Store.inMemory()
        let contents = try SurveyFile.decode(SurveyFile.encode(SurveyTemplate.makeDefault(now: now))).get()
        let first = try store.importSurvey(contents, now: now)
        let second = try store.importSurvey(contents, now: now.addingTimeInterval(1))
        #expect(first.id != second.id)
        let questionIds = first.questions.map(\.id) + second.questions.map(\.id) + contents.questions.map(\.id)
        #expect(Set(questionIds).count == questionIds.count)
        let optionIds = (first.questions + second.questions + contents.questions).flatMap { $0.options.map(\.id) }
        #expect(Set(optionIds).count == optionIds.count)
        #expect(Support.Definition(first) == Support.Definition(second))
    }

    @Test("an imported survey exports back to the file it came from")
    func importThenExport() throws {
        let store = try Store.inMemory()
        let original = SurveyFile.encode(Self.elaborateSurvey())
        let imported = try store.importSurvey(try SurveyFile.decode(original).get(), now: now)
        #expect(SurveyFile.encode(imported) == original)
    }

    @Test("an imported survey can be edited like any other, through version rows")
    func importedSurveyIsEditable() throws {
        let store = try Store.inMemory()
        let contents = try Support.decode(Support.file(question: #"{"kind": "text", "label": "Note"}"#))
        let imported = try store.importSurvey(contents, now: now)
        let question = try #require(imported.questions.first)
        try store.updateQuestion(
            question.id, label: "Renamed", position: 0, isRequired: false, isArchived: false,
            scale: nil, allowsCustomOptions: false, now: now.addingTimeInterval(1))
        #expect(try store.labelHistory(questionId: question.id).map(\.label) == ["Note", "Renamed"])
    }
}
