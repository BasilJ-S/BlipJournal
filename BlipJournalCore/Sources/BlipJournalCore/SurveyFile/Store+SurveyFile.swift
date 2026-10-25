import Foundation

extension Store {
    /// Adds the survey a survey file describes as a new survey, through the same
    /// `createSurvey` a blank or copied survey goes through, so the result is
    /// indistinguishable from one built in the editor. Nothing existing is touched.
    ///
    /// Every question and option gets a fresh identifier, so the same contents can be
    /// imported twice. Sampling starts paused and the notification preview private, as
    /// for any new survey: the person turns prompts on once they have looked it over.
    @discardableResult
    public func importSurvey(_ contents: SurveyFileContents, now: Date = Date()) throws -> Survey {
        var newIds: [String: String] = [:]
        let questions = contents.questions.map { question in
            var copy = question
            copy.id = Identifier.make()
            copy.options = question.options.map { option in
                var optionCopy = option
                optionCopy.id = Identifier.make()
                return optionCopy
            }
            newIds[question.id] = copy.id
            return copy
        }
        var sampling = contents.sampling
        sampling.isEnabled = false
        return try createSurvey(
            name: contents.name, sampling: sampling, questions: questions,
            journalSummaryQuestionIds: contents.journalSummaryQuestionIds.compactMap { newIds[$0] },
            now: now)
    }
}
