import BlipJournalCore
import Foundation
import Testing
@testable import BlipJournal

@MainActor
struct EntryDraftTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() throws -> (Store, Survey) {
        let store = try Store.inMemory()
        let template = SurveyTemplate.makeDefault(now: now)
        let survey = try store.createSurvey(name: template.name, sampling: template.sampling, questions: template.questions, now: now)
        return (store, survey)
    }

    private func entryCount(_ store: Store, _ survey: Survey) throws -> Int { try store.entries(surveyId: survey.id, from: nil, to: nil).count }
    private func firstQuestion(_ survey: Survey, _ kind: QuestionKind) throws -> Question { try #require(survey.activeQuestions.first { $0.kind == kind }) }

    @Test func manualDraftIsSavedOnFirstAnswerAndResumes() async throws {
        let (store, survey) = try fixture()
        let first = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        #expect(try entryCount(store, survey) == 0)
        let question = try firstQuestion(survey, .spectrum)
        try await first.set(.spectrum(0.3), for: question.id, now: now.addingTimeInterval(30))
        let saved = try #require(try store.entries(surveyId: survey.id, from: nil, to: nil).first)
        #expect(saved.id == first.entry.id); #expect(saved.startedAt == now)
        let resumed = try EntryDraft(store: store, entry: saved)
        #expect(resumed.values[question.id] == .spectrum(0.3))
    }

    @Test func manualDraftWithoutAnswersLeavesNoEntry() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let text = try firstQuestion(survey, .text)
        draft.setText("   ", for: text.id, now: now); try await draft.flush()
        let other = try #require(survey.activeQuestions.first(where: { $0.kind != .text }))
        try await draft.set(nil, for: other.id, now: now)
        #expect(try entryCount(store, survey) == 0)
    }

    @Test func nonBlankTextSavesManualDraft() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let text = try firstQuestion(survey, .text)
        draft.setText("note", for: text.id, now: now); try await draft.flush()
        #expect(try entryCount(store, survey) == 1)
    }

    @Test func clearingEveryAnswerKeepsTheSavedEntry() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let question = try firstQuestion(survey, .spectrum)
        try await draft.set(.spectrum(0.3), for: question.id, now: now)
        try await draft.set(nil, for: question.id, now: now)
        #expect(try entryCount(store, survey) == 1); #expect(try store.answers(entryId: draft.entry.id).isEmpty)
    }

    @Test func clearQueuedBehindFirstSaveIsWritten() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let question = try firstQuestion(survey, .spectrum)
        let answer = Task { try await draft.set(.spectrum(0.3), for: question.id, now: now) }
        let clear = Task { try await draft.set(nil, for: question.id, now: now) }
        try await answer.value; try await clear.value
        #expect(try entryCount(store, survey) == 1); #expect(try store.answers(entryId: draft.entry.id).isEmpty)
    }

    @Test func completingWithoutAnswersLeavesNoEntry() async throws {
        let store = try Store.inMemory()
        let template = SurveyTemplate.makeDefault(now: now)
        let optional = template.questions.map { var question = $0; question.isRequired = false; return question }
        let survey = try store.createSurvey(name: template.name, sampling: template.sampling, questions: optional, now: now)
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        try await draft.complete(now: now)
        #expect(try entryCount(store, survey) == 0)
    }

    @Test func notificationDraftReusesPromptEntry() throws {
        let (store, survey) = try fixture()
        let prompt = Prompt(surveyId: survey.id, day: "2026-01-01", scheduledAt: now, expiresAt: now.addingTimeInterval(3600))
        try store.insertPrompts([prompt])
        let first = try EntryDraft(store: store, survey: survey, promptId: prompt.id, now: now)
        #expect(try entryCount(store, survey) == 1)
        let reopened = try EntryDraft(store: store, survey: survey, promptId: prompt.id, now: now.addingTimeInterval(60))
        #expect(reopened.entry.id == first.entry.id); #expect(try entryCount(store, survey) == 1)
    }

    @Test func keepsAnswerIdentityAndFirstTimestamp() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let question = try firstQuestion(survey, .spectrum)
        try await draft.set(.spectrum(0.2), for: question.id, now: now)
        try await draft.set(.spectrum(0.5), for: question.id, now: now.addingTimeInterval(10))
        let answer = try #require(try store.answers(entryId: draft.entry.id).first)
        #expect(answer.value == .spectrum(0.5)); #expect(answer.answeredAt == now)
    }

    @Test func clearRemovesAnswerAndRequiredGating() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let question = try #require(survey.activeQuestions.first(where: { $0.isRequired }))
        try await draft.set(.text("note"), for: question.id, now: now)
        #expect(draft.canComplete)
        try await draft.set(nil, for: question.id)
        #expect(!draft.canComplete); #expect(try store.answers(entryId: draft.entry.id).isEmpty)
    }

    @Test func textLimitAndWhitespaceAreEnforced() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let question = try firstQuestion(survey, .text)
        draft.setText(String(repeating: "x", count: 500), for: question.id, now: now)
        try await draft.flush(); #expect(draft.values[question.id] == .text(String(repeating: "x", count: 500)))
        draft.setText(String(repeating: "x", count: 501), for: question.id, now: now.addingTimeInterval(1))
        #expect(draft.values[question.id]?.isEmpty == false)
        draft.setText("   ", for: question.id); try await draft.flush()
        #expect(try store.answers(entryId: draft.entry.id).isEmpty)
    }

    @Test func expiredPromptCannotStartNewDraft() throws {
        let (store, survey) = try fixture()
        let prompt = Prompt(surveyId: survey.id, day: "2026-01-01", scheduledAt: now, expiresAt: now.addingTimeInterval(1))
        try store.insertPrompts([prompt])
        #expect(throws: EntryDraft.Error.expiredPrompt) { try EntryDraft(store: store, survey: survey, promptId: prompt.id, now: now.addingTimeInterval(1)) }
    }

    @Test func draftDoesNotReopenAnEntryClosedAtExpiry() async throws {
        let store = try Store.inMemory()
        let survey = try store.createSurvey(
            name: "Sleep", sampling: .default,
            questions: [
                Question(kind: .yesNo, label: "Slept well?", position: 0, isRequired: true),
                Question(kind: .text, label: "Anything else?", position: 1),
            ],
            now: now)
        let prompt = Prompt(surveyId: survey.id, day: "2026-01-01", scheduledAt: now, expiresAt: now.addingTimeInterval(1200))
        try store.insertPrompts([prompt])
        let offered = try #require(NotificationAnswers(survey: survey))
        _ = try store.saveNotificationAnswer(
            promptId: prompt.id, questionId: offered.questionId,
            actionIdentifier: offered.choices[0].actionIdentifier, now: now.addingTimeInterval(60))
        let draft = try EntryDraft(store: store, survey: survey, promptId: prompt.id, now: now.addingTimeInterval(120))
        try store.settleExpiredPrompts([prompt.id], now: now.addingTimeInterval(1300))

        let text = try firstQuestion(survey, .text)
        await #expect(throws: EntryDraft.Error.completed) {
            try await draft.set(.text("late"), for: text.id, now: now.addingTimeInterval(1400))
        }
        let stored = try #require(try store.entries(surveyId: survey.id, from: nil, to: nil).first)
        #expect(stored.completedAt == now.addingTimeInterval(60))
        #expect(stored.answeredFromNotification)
        #expect(try store.answers(entryId: stored.id).count == 1)
    }
}
