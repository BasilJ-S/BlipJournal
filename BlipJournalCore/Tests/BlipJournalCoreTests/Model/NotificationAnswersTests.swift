import Foundation
import Testing
import BlipJournalCore

@Suite("NotificationAnswers")
struct NotificationAnswersTests {
    private func survey(_ questions: [Question]) -> Survey {
        Survey(name: "Private name", questions: questions)
    }

    @Test("a yes/no first question offers Yes then No")
    func yesNo() throws {
        let question = Question(id: "q1", kind: .yesNo, label: "Did you sleep well?", position: 0)
        let answers = try #require(NotificationAnswers(survey: survey([question])))
        #expect(answers.questionId == "q1")
        #expect(answers.choices.map(\.title) == ["Yes", "No"])
        #expect(answers.choices.map(\.value) == [.yesNo(true), .yesNo(false)])
        #expect(answers.value(forActionIdentifier: answers.choices[1].actionIdentifier) == .yesNo(false))
    }

    @Test("a scale of up to five values offers each value, ends marked lowest and highest")
    func smallScale() throws {
        let question = Question(
            id: "q1", kind: .scale, label: "Energy", position: 0,
            scale: ScaleConfig(min: 1, max: 5, minLabel: "Drained", maxLabel: "Buzzing"))
        let answers = try #require(NotificationAnswers(survey: survey([question])))
        #expect(answers.choices.map(\.title) == ["1 (lowest)", "2", "3", "4", "5 (highest)"])
        #expect(answers.choices.map(\.value) == (1...5).map { AnswerValue.scale($0) })
        #expect(Set(answers.choices.map(\.actionIdentifier)).count == 5)
    }

    @Test("negative and two-value scales fit too")
    func otherScales() throws {
        let negative = Question(
            id: "q1", kind: .scale, label: "Mood", position: 0, scale: ScaleConfig(min: -2, max: 2))
        let values = try #require(NotificationAnswers(survey: survey([negative]))).choices.map(\.value)
        #expect(values == [.scale(-2), .scale(-1), .scale(0), .scale(1), .scale(2)])

        let binary = Question(id: "q2", kind: .scale, label: "Mood", position: 0, scale: ScaleConfig(min: 0, max: 1))
        #expect(NotificationAnswers(survey: survey([binary]))?.choices.count == 2)
    }

    @Test("titles never carry the question's wording, endpoint labels or survey name")
    func titlesRevealNothing() throws {
        let question = Question(
            id: "q1", kind: .scale, label: "Secret question", position: 0,
            scale: ScaleConfig(min: 1, max: 3, minLabel: "Secret low", maxLabel: "Secret high"))
        let answers = try #require(NotificationAnswers(survey: survey([question])))
        for choice in answers.choices {
            #expect(!choice.title.contains("Secret"))
            #expect(!choice.title.contains("Private"))
        }
    }

    @Test("a scale wider than five values, an invalid scale, or a scale without config offers nothing")
    func tooWideOrInvalid() {
        let seven = Question(id: "q1", kind: .scale, label: "Mood", position: 0, scale: ScaleConfig(min: 1, max: 7))
        let six = Question(id: "q1", kind: .scale, label: "Mood", position: 0, scale: ScaleConfig(min: 0, max: 5))
        let invalid = Question(id: "q1", kind: .scale, label: "Mood", position: 0, scale: ScaleConfig(min: 3, max: 3))
        let extreme = Question(id: "q1", kind: .scale, label: "Mood", position: 0, scale: ScaleConfig(min: .min, max: .max))
        let missing = Question(id: "q1", kind: .scale, label: "Mood", position: 0, scale: nil)
        for question in [seven, six, invalid, extreme, missing] {
            #expect(NotificationAnswers(survey: survey([question])) == nil)
        }
        #expect(NotificationAnswers.maxScaleChoices == 5)
    }

    @Test("other kinds, and a survey with no active question, offer nothing")
    func otherKinds() {
        let kinds: [QuestionKind] = [.spectrum, .singleChoice, .multiChoice, .text]
        for kind in kinds {
            let question = Question(
                id: "q1", kind: kind, label: "Q", position: 0,
                spectrum: kind == .spectrum ? SpectrumConfig() : nil)
            #expect(NotificationAnswers(survey: survey([question])) == nil)
        }
        #expect(NotificationAnswers(survey: survey([])) == nil)
        let archived = Question(id: "q1", kind: .yesNo, label: "Q", position: 0, isArchived: true)
        #expect(NotificationAnswers(survey: survey([archived])) == nil)
    }

    @Test("only the first active question counts, by position")
    func firstActiveQuestion() throws {
        let archivedFirst = Question(id: "a", kind: .yesNo, label: "Old", position: 0, isArchived: true)
        let text = Question(id: "b", kind: .text, label: "Note", position: 2)
        let yesNo = Question(id: "c", kind: .yesNo, label: "Q", position: 1)
        #expect(NotificationAnswers(survey: survey([text, archivedFirst, yesNo]))?.questionId == "c")

        let textFirst = Question(id: "d", kind: .text, label: "Note", position: 0)
        #expect(NotificationAnswers(survey: survey([yesNo, textFirst])) == nil)
    }

    @Test("the default survey, which opens with a spectrum, offers nothing")
    func defaultSurvey() {
        #expect(NotificationAnswers(survey: SurveyTemplate.makeDefault()) == nil)
    }

    @Test("an action identifier the choices do not offer has no value")
    func unknownAction() throws {
        let question = Question(id: "q1", kind: .scale, label: "Mood", position: 0, scale: ScaleConfig(min: 1, max: 4))
        let answers = try #require(NotificationAnswers(survey: survey([question])))
        #expect(answers.value(forActionIdentifier: "answer.scale.5") == nil)
        #expect(answers.value(forActionIdentifier: "answer.yes") == nil)
        #expect(answers.value(forActionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier") == nil)
    }
}
