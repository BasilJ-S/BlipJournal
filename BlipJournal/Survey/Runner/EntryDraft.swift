import BlipJournalCore
import Foundation
import Observation

private actor SaveQueue {
    private var previous: Task<Void, Error>?
    func save(_ store: Store, _ entry: Entry, _ answers: [Answer]) async throws {
        let prior = previous
        let task = Task { () throws -> Void in
            _ = try? await prior?.value
            try store.saveEntry(entry, answers: answers)
        }
        previous = task
        try await task.value
    }
}

@MainActor @Observable
final class EntryDraft {
    enum Error: Swift.Error { case completed, expiredPrompt, missingVersion }
    private let store: Store
    private let queue = SaveQueue()
    private let versions: [String: String]
    private var ids: [String: String] = [:]
    private var dates: [String: Date] = [:]
    private var pendingText = false
    private var debounce: Task<Void, Never>?
    private(set) var survey: Survey
    private(set) var entry: Entry
    private(set) var values: [String: AnswerValue]

    var missingRequired: [Question] { survey.activeQuestions.filter { $0.isRequired && !hasAnswer(for: $0.id) } }
    var canComplete: Bool { missingRequired.isEmpty }
    func hasAnswer(for id: String) -> Bool { values[id]?.isEmptyForRunner == false }

    init(store: Store, survey: Survey, promptId: String?, now: Date = Date()) throws {
        self.store = store; self.survey = survey; self.versions = try store.currentQuestionVersionIds(surveyId: survey.id)
        if let promptId, let old = try store.entries(surveyId: survey.id, from: nil, to: nil).first(where: { $0.promptId == promptId }) {
            guard old.completedAt == nil else { throw Error.completed }; self.entry = old; self.values = [:]; try load()
        } else {
            if let promptId, let prompt = try store.prompts(status: nil).first(where: { $0.id == promptId }), prompt.isExpired(at: now) { throw Error.expiredPrompt }
            self.entry = Entry(surveyId: survey.id, promptId: promptId, startedAt: now); self.values = [:]
            try store.saveEntry(entry, answers: [])
        }
    }

    init(store: Store, entry: Entry) throws {
        guard entry.completedAt == nil else { throw Error.completed }
        guard let survey = try store.survey(entry.surveyId) else { throw StoreError.notFound }
        self.store = store; self.survey = survey; self.entry = entry; self.versions = try store.currentQuestionVersionIds(surveyId: survey.id); self.values = [:]; try load()
    }

    private func load() throws { for answer in try store.answers(entryId: entry.id) { ids[answer.questionId] = answer.id; dates[answer.questionId] = answer.answeredAt; values[answer.questionId] = answer.value } }

    func set(_ value: AnswerValue?, for questionId: String, now: Date = Date()) async throws {
        if pendingText { try await flush() }
        if let value, !value.isEmptyForRunner { values[questionId] = value; if ids[questionId] == nil { ids[questionId] = Identifier.make(); dates[questionId] = now } }
        else { values.removeValue(forKey: questionId); ids.removeValue(forKey: questionId); dates.removeValue(forKey: questionId) }
        try await save()
    }

    func setText(_ text: String, for questionId: String, now: Date = Date()) {
        guard text.count <= 500 else { return }
        values[questionId] = .text(text)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ids.removeValue(forKey: questionId); dates.removeValue(forKey: questionId) }
        else if ids[questionId] == nil { ids[questionId] = Identifier.make(); dates[questionId] = now }
        pendingText = true; debounce?.cancel(); debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return }; try? await self?.flush()
        }
    }

    func flush() async throws { debounce?.cancel(); debounce = nil; guard pendingText else { return }; pendingText = false; try await save() }
    func addOption(label: String, to questionId: String, now: Date = Date()) async throws {
        let option = try store.addOption(questionId: questionId, label: label, now: now); guard let survey = try store.survey(survey.id) else { throw StoreError.notFound }; self.survey = survey
        if survey.questions.first(where: { $0.id == questionId })?.kind == .singleChoice { try await set(.single(optionId: option.id), for: questionId, now: now) }
        else { var selected: [String] = []; if let value = values[questionId], case .multi(let x) = value { selected = x }; selected.append(option.id); try await set(.multi(optionIds: selected), for: questionId, now: now) }
    }
    func complete(now: Date = Date()) async throws { try await flush(); guard canComplete else { return }; entry.completedAt = now; try await save(); if let promptId = entry.promptId { try store.setPromptStatus(promptId, .answered, respondedAt: now) } }

    private func save() async throws {
        let answers = try values.compactMap { questionId, value -> Answer? in
            guard !value.isEmptyForRunner else { return nil }; guard let id = ids[questionId], let version = versions[questionId] else { throw Error.missingVersion }
            return Answer(id: id, entryId: entry.id, questionId: questionId, questionVersionId: version, answeredAt: dates[questionId] ?? Date(), value: value)
        }
        try await queue.save(store, entry, answers)
    }
}

private extension AnswerValue {
    var isEmptyForRunner: Bool { if case .text(let text) = self { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; return isEmpty }
}
