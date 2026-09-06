import BlipJournalCore
import Foundation
import Testing
@testable import BlipJournal

@MainActor
struct EditorModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func model(store: Store) -> EditorModel {
        EditorModel(store: store, notifications: NoopNotificationCoordinator())
    }

    @Test func newSurveysStartPausedAndCopyOnlyActiveDefinitions() throws {
        let store = try Store.inMemory()
        let editor = model(store: store)
        let source = try store.createSurvey(
            name: "Source", sampling: .default,
            questions: [
                Question(kind: .text, label: "Keep", position: 0),
                Question(kind: .yesNo, label: "Archive", position: 1, isArchived: true),
            ], now: now)
        var archivedSource = try #require(try store.survey(source.id))
        archivedSource.questions[0].isArchived = true
        try store.updateQuestion(archivedSource.questions[0], label: archivedSource.questions[0].label,
                                 position: 0, isRequired: false, isArchived: true, scale: nil,
                                 allowsCustomOptions: false, now: now.addingTimeInterval(1))
        let blank = try editor.createSurvey(name: "Blank", now: now)
        #expect(blank.sampling.isEnabled == false)
        let copy = try editor.copySurvey(sourceId: source.id, name: "Copy", now: now.addingTimeInterval(2))
        #expect(copy.sampling.isEnabled == false)
        #expect(copy.notificationPreview == .private)
        #expect(copy.activeQuestions.isEmpty)
        #expect(blank.id != source.id)
    }

    @Test func updateAndMoveQuestionsOnlyVersionChangedPositions() throws {
        let store = try Store.inMemory()
        let editor = model(store: store)
        let survey = try store.createSurvey(name: "Survey", sampling: .default, questions: [
            Question(kind: .text, label: "A", position: 0),
            Question(kind: .text, label: "B", position: 1),
            Question(kind: .text, label: "C", position: 2),
        ], now: now)
        let before = try store.survey(survey.id)!
        try editor.moveQuestions(surveyId: survey.id, from: IndexSet(integer: 0), to: 3, now: now.addingTimeInterval(1))
        let after = try store.survey(survey.id)!
        #expect(after.activeQuestions.map(\.label) == ["B", "C", "A"])
        #expect(try store.labelHistory(questionId: before.activeQuestions[1].id).count == 2)
        #expect(try store.labelHistory(questionId: before.activeQuestions[0].id).count == 2)
    }

    @Test func invalidSamplingAndCustomPreviewDoNotWrite() async throws {
        let store = try Store.inMemory()
        let editor = model(store: store)
        let survey = try editor.createSurvey(name: "Survey", now: now)
        var invalid = SamplingConfig.default
        invalid.windowEndMinutes = invalid.windowStartMinutes
        await #expect(throws: EditorError.invalidSampling(invalid.validationErrors)) {
            try await editor.saveSampling(surveyId: survey.id, invalid, now: now)
        }
        await #expect(throws: StoreError.invalidNotificationPreview) {
            try await editor.saveNotificationPreview(surveyId: survey.id, .custom(message: " \n"), now: now)
        }
        #expect(try store.survey(survey.id)?.notificationPreview == .private)
    }
}
