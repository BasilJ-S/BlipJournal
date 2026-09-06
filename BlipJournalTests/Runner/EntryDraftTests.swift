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

    @Test func createsAndResumesDraft() throws {
        let (store, survey) = try fixture()
        let first = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        #expect(try store.entries(surveyId: survey.id, from: nil, to: nil).count == 1)
        let question = try #require(survey.activeQuestions.first)
        try #require(first.values[question.id] == nil)
        let resumed = try EntryDraft(store: store, entry: first.entry)
        #expect(resumed.entry.id == first.entry.id)
    }

    @Test func keepsAnswerIdentityAndFirstTimestamp() async throws {
        let (store, survey) = try fixture()
        let draft = try EntryDraft(store: store, survey: survey, promptId: nil, now: now)
        let question = try #require(survey.activeQuestions.first(where: { $0.kind == .scale }))
        try await draft.set(.scale(2), for: question.id, now: now)
        try await draft.set(.scale(5), for: question.id, now: now.addingTimeInterval(10))
        let answer = try #require(try store.answers(entryId: draft.entry.id).first)
        #expect(answer.value == .scale(5)); #expect(answer.answeredAt == now)
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
        let question = try #require(survey.activeQuestions.first(where: { $0.kind == .text }))
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
}
