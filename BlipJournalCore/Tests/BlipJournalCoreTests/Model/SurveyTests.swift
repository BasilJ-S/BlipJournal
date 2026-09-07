import Foundation
import Testing
import BlipJournalCore

@Suite("Question")
struct QuestionTests {
    /// Four options at positions 0...3, the one at position 2 archived, shuffled.
    private func makeShuffledOptions() -> [ChoiceOption] {
        [
            ChoiceOption(id: "a", label: "Alpha", position: 0),
            ChoiceOption(id: "b", label: "Bravo", position: 1),
            ChoiceOption(id: "c", label: "Charlie", position: 2, isArchived: true),
            ChoiceOption(id: "d", label: "Delta", position: 3),
        ].shuffled()
    }

    @Test("activeOptions drops archived options and sorts by position")
    func activeOptionsFiltersAndSorts() {
        let question = Question(
            kind: .multiChoice,
            label: "Pick some",
            position: 0,
            options: makeShuffledOptions()
        )
        #expect(question.activeOptions.map(\.id) == ["a", "b", "d"])
    }

    @Test("activeOptions is stable however the source array is shuffled")
    func activeOptionsIsStable() {
        for _ in 0..<50 {
            let question = Question(
                kind: .multiChoice,
                label: "Pick some",
                position: 0,
                options: makeShuffledOptions()
            )
            #expect(question.activeOptions.map(\.id) == ["a", "b", "d"])
        }
    }

    @Test("equal positions fall back to identifier order")
    func activeOptionsTieBreak() {
        let question = Question(
            kind: .singleChoice,
            label: "Pick one",
            position: 0,
            options: [
                ChoiceOption(id: "z", label: "Zulu", position: 0),
                ChoiceOption(id: "m", label: "Mike", position: 0),
                ChoiceOption(id: "a", label: "Alpha", position: 0),
            ]
        )
        #expect(question.activeOptions.map(\.id) == ["a", "m", "z"])
    }

    @Test("a question with every option archived has none active")
    func allArchived() {
        let question = Question(
            kind: .multiChoice,
            label: "Pick some",
            position: 0,
            options: [
                ChoiceOption(id: "a", label: "Alpha", position: 0, isArchived: true),
                ChoiceOption(id: "b", label: "Bravo", position: 1, isArchived: true),
            ]
        )
        #expect(question.activeOptions.isEmpty)
    }

    @Test("defaults leave a question optional, live, unscaled and optionless")
    func defaults() {
        let question = Question(kind: .text, label: "Anything else?", position: 5)
        #expect(!question.isRequired)
        #expect(!question.isArchived)
        #expect(question.scale == nil)
        #expect(!question.allowsCustomOptions)
        #expect(question.options.isEmpty)
        #expect(!question.id.isEmpty)
    }
}

@Suite("Survey")
struct SurveyTests {
    /// Three questions at positions 0...2, the one at position 1 archived, shuffled.
    private func makeShuffledQuestions() -> [Question] {
        [
            Question(id: "q0", kind: .scale, label: "First", position: 0),
            Question(id: "q1", kind: .yesNo, label: "Second", position: 1, isArchived: true),
            Question(id: "q2", kind: .text, label: "Third", position: 2),
        ].shuffled()
    }

    @Test("activeQuestions drops archived questions and sorts by position")
    func activeQuestionsFiltersAndSorts() {
        let survey = Survey(name: "Test", questions: makeShuffledQuestions())
        #expect(survey.activeQuestions.map(\.id) == ["q0", "q2"])
    }

    @Test("activeQuestions is stable however the source array is shuffled")
    func activeQuestionsIsStable() {
        for _ in 0..<50 {
            let survey = Survey(name: "Test", questions: makeShuffledQuestions())
            #expect(survey.activeQuestions.map(\.id) == ["q0", "q2"])
        }
    }

    @Test("equal positions fall back to identifier order")
    func activeQuestionsTieBreak() {
        let survey = Survey(name: "Test", questions: [
            Question(id: "z", kind: .text, label: "Zulu", position: 0),
            Question(id: "a", kind: .text, label: "Alpha", position: 0),
        ])
        #expect(survey.activeQuestions.map(\.id) == ["a", "z"])
    }

    @Test("defaults leave a survey live, unarchived, with the default schedule")
    func defaults() {
        let survey = Survey(name: "Test")
        #expect(!survey.isArchived)
        #expect(survey.sampling == .default)
        #expect(survey.notificationPreview == .default)
        #expect(survey.notificationPreview == .private)
        #expect(survey.journalSummaryQuestionIds.isEmpty)
        #expect(survey.questions.isEmpty)
        #expect(!survey.id.isEmpty)
    }

    @Test("Journal summary keeps two unique choices in order and resolves active questions")
    func journalSummaryQuestions() {
        let questions = makeShuffledQuestions()
        let survey = Survey(
            name: "Test",
            journalSummaryQuestionIds: ["q2", "q0", "q2"],
            questions: questions)
        #expect(survey.journalSummaryQuestionIds == ["q2", "q0"])
        #expect(survey.journalSummaryQuestions.map(\.id) == ["q2", "q0"])
    }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        let survey = Survey(
            name: "Test", notificationPreview: .custom(message: "Ping!"),
            questions: makeShuffledQuestions())
        let data = try JSONEncoder().encode(survey)
        #expect(try JSONDecoder().decode(Survey.self, from: data) == survey)
    }
}
