import Foundation
import Testing
import BlipJournalCore

struct QuestionEditDraftTests {
    @Test(arguments: ["add", "rename", "reorder", "archive"])
    func optionRefreshPreservesPendingQuestionFields(operation: String) throws {
        let store = try Store.inMemory()
        let question = Question(kind: .singleChoice, label: "Original", position: 0,
            options: [ChoiceOption(label: "One", position: 0), ChoiceOption(label: "Two", position: 1)])
        let survey = try store.createSurvey(name: "Test", sampling: .default, questions: [question])
        var draft = QuestionEditDraft()
        draft.load(question)
        draft.label = "Pending label"
        draft.isRequired = true
        draft.allowsCustomOptions = true
        let option = question.options[0]
        switch operation {
        case "add": _ = try store.addOption(questionId: question.id, label: "Three")
        case "rename": try store.updateOption(option.id, label: "Renamed", position: option.position, isArchived: false)
        case "reorder": try store.updateOption(option.id, label: option.label, position: 2, isArchived: false)
        default: try store.updateOption(option.id, label: option.label, position: option.position, isArchived: true)
        }
        let latest = try #require(try store.survey(survey.id)?.questions.first)
        draft.load(latest) // The revision-keyed editor refresh.
        #expect(draft.label == "Pending label")
        #expect(draft.isRequired)
        #expect(draft.allowsCustomOptions)
        let saving = draft.applying(to: latest)
        try store.updateQuestion(saving.id, label: saving.label, position: saving.position,
            isRequired: saving.isRequired, isArchived: saving.isArchived, scale: saving.scale,
            spectrum: saving.spectrum, allowsCustomOptions: saving.allowsCustomOptions)
        let saved = try #require(try store.survey(survey.id)?.questions.first)
        #expect(saved.label == "Pending label")
        #expect(saved.isRequired)
        #expect(saved.allowsCustomOptions)
        #expect(saved.options == latest.options)
    }

    @Test func changingQuestionInitializesNewFields() {
        let a = Question(kind: .text, label: "A", position: 0)
        let b = Question(kind: .text, label: "B", position: 1)
        var draft = QuestionEditDraft()
        draft.load(a)
        draft.label = "Unsaved A"
        draft.load(b)
        #expect(draft.label == "B")
    }
}
