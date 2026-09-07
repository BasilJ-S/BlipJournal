import BlipJournalCore
import Foundation
import Observation

enum ArchivedTarget: Hashable {
    case survey(Survey)
    case question(Question, in: Survey)
    case option(ChoiceOption, in: Question, Survey)
}

enum EditorError: Error, Equatable {
    case invalidSampling([SamplingConfig.ValidationError])
    case surveyNeedsQuestion
    case invalidScale
    case invalidSpectrum
}

@MainActor @Observable
final class EditorModel {
    let store: Store
    let notifications: any NotificationCoordinating

    init(store: Store, notifications: any NotificationCoordinating) {
        self.store = store
        self.notifications = notifications
    }

    private func survey(_ id: String) throws -> Survey {
        guard let survey = try store.survey(id) else { throw StoreError.notFound }
        return survey
    }

    @discardableResult
    func createSurvey(name: String, now: Date = Date()) throws -> Survey {
        var sampling = SamplingConfig.default
        sampling.isEnabled = false
        return try store.createSurvey(name: name, sampling: sampling, questions: [], now: now)
    }

    @discardableResult
    func copySurvey(sourceId: String, name: String, now: Date = Date()) throws -> Survey {
        let source = try survey(sourceId)
        let questions = source.activeQuestions.enumerated().map { index, question in
            Question(
                kind: question.kind,
                label: question.label,
                position: index,
                isRequired: question.isRequired,
                scale: question.scale,
                spectrum: question.spectrum,
                allowsCustomOptions: question.allowsCustomOptions,
                options: question.activeOptions.enumerated().map { optionIndex, option in
                    ChoiceOption(label: option.label, position: optionIndex)
                })
        }
        var sampling = source.sampling
        sampling.isEnabled = false
        let copy = try store.createSurvey(name: name, sampling: sampling, questions: questions, now: now)
        // New surveys always start privately, even when the source used another preview.
        if source.notificationPreview != .default {
            try store.updateNotificationPreview(surveyId: copy.id, .default, now: now)
        }
        return try survey(copy.id)
    }

    func rename(surveyId: String, to name: String, now: Date = Date()) throws {
        try store.renameSurvey(surveyId, to: name, now: now)
        Task { await notifications.refresh(now: now) }
    }

    func archive(surveyId: String, now: Date = Date()) async throws {
        try store.archiveSurvey(surveyId, now: now)
        try store.deleteFuturePendingPrompts(surveyId: surveyId, after: now)
        await notifications.scheduleChanged(surveyId: surveyId, now: now)
    }

    func unarchive(surveyId: String, now: Date = Date()) async throws {
        try store.unarchiveSurvey(surveyId, now: now)
        await notifications.scheduleChanged(surveyId: surveyId, now: now)
    }

    @discardableResult
    func addQuestion(
        surveyId: String, kind: QuestionKind, label: String, isRequired: Bool,
        scale: ScaleConfig?, spectrum: SpectrumConfig? = nil, allowsCustomOptions: Bool, now: Date = Date()
    ) throws -> Question {
        if kind == .scale && !(scale?.isValid ?? false) { throw EditorError.invalidScale }
        if kind == .spectrum && !(spectrum?.isValid ?? false) { throw EditorError.invalidSpectrum }
        return try store.addQuestion(
            surveyId: surveyId, kind: kind, label: label, isRequired: isRequired,
            scale: scale, spectrum: spectrum, allowsCustomOptions: allowsCustomOptions, now: now)
    }

    func updateQuestion(_ question: Question, now: Date = Date()) throws {
        if question.kind == .scale && !(question.scale?.isValid ?? false) { throw EditorError.invalidScale }
        if question.kind == .spectrum && !(question.spectrum?.isValid ?? false) { throw EditorError.invalidSpectrum }
        try store.updateQuestion(
            question.id, label: question.label, position: question.position,
            isRequired: question.isRequired, isArchived: question.isArchived,
            scale: question.scale, spectrum: question.spectrum,
            allowsCustomOptions: question.allowsCustomOptions, now: now)
    }

    func moveQuestions(surveyId: String, from: IndexSet, to: Int, now: Date = Date()) throws {
        let current = try survey(surveyId).activeQuestions
        var moved = current
        let selected = from.sorted().map { moved[$0] }
        for index in from.sorted(by: >) { moved.remove(at: index) }
        let destination = max(0, min(to - from.filter { $0 < to }.count, moved.count))
        moved.insert(contentsOf: selected, at: destination)
        for (position, question) in moved.enumerated() where question.position != position {
            var updated = question
            updated.position = position
            try updateQuestion(updated, now: now)
        }
    }

    @discardableResult
    func addOption(questionId: String, label: String, now: Date = Date()) throws -> ChoiceOption {
        try store.addOption(questionId: questionId, label: label, now: now)
    }

    func updateOption(_ option: ChoiceOption, now: Date = Date()) throws {
        try store.updateOption(option.id, label: option.label, position: option.position,
                               isArchived: option.isArchived, now: now)
    }

    func moveOptions(questionId: String, from: IndexSet, to: Int, now: Date = Date()) throws {
        guard let question = try store.surveys(includeArchived: true)
            .flatMap({ $0.questions }).first(where: { $0.id == questionId }) else {
            throw StoreError.notFound
        }
        var moved = question.activeOptions
        let selected = from.sorted().map { moved[$0] }
        for index in from.sorted(by: >) { moved.remove(at: index) }
        let destination = max(0, min(to - from.filter { $0 < to }.count, moved.count))
        moved.insert(contentsOf: selected, at: destination)
        for (position, option) in moved.enumerated() where option.position != position {
            var updated = option
            updated.position = position
            try updateOption(updated, now: now)
        }
    }

    func saveSampling(surveyId: String, _ config: SamplingConfig, now: Date = Date()) async throws {
        if !config.validationErrors.isEmpty { throw EditorError.invalidSampling(config.validationErrors) }
        let currentSurvey = try survey(surveyId)
        if config.isEnabled && currentSurvey.activeQuestions.isEmpty {
            throw EditorError.surveyNeedsQuestion
        }
        try store.updateSampling(surveyId: surveyId, config, now: now)
        await notifications.scheduleChanged(surveyId: surveyId, now: now)
    }

    func saveNotificationPreview(surveyId: String, _ preview: NotificationPreview, now: Date = Date()) async throws {
        try store.updateNotificationPreview(surveyId: surveyId, preview, now: now)
        await notifications.refresh(now: now)
    }

    func deletionImpact(for target: ArchivedTarget) throws -> DeletionImpact {
        switch target {
        case .survey(let survey): try store.deletionImpact(surveyId: survey.id)
        case .question(let question, _): try store.deletionImpact(questionId: question.id)
        case .option(let option, _, _): try store.deletionImpact(optionId: option.id)
        }
    }

    func hardDelete(_ target: ArchivedTarget, now: Date = Date()) async throws {
        switch target {
        case .survey(let survey):
            try store.hardDeleteSurvey(survey.id)
            await notifications.promptsDestroyed(now: now)
        case .question(let question, _):
            try store.hardDeleteQuestion(question.id)
        case .option(let option, _, _):
            try store.hardDeleteOption(option.id)
        }
    }
}
