import BlipJournalCore
import Foundation

enum DeletionConfirmation {
    static func message(for target: ArchivedTarget, store: Store) -> String {
        let impact: DeletionImpact
        let name: String
        let survivor: String
        switch target {
        case .survey(let survey): name = "Survey \"\(survey.name)\""; survivor = "Your other surveys are not affected."; impact = (try? store.deletionImpact(surveyId: survey.id)) ?? DeletionImpact()
        case .question(let question, _): name = "Question \"\(question.label)\""; survivor = "Your other questions and their answers are not affected."; impact = (try? store.deletionImpact(questionId: question.id)) ?? DeletionImpact()
        case .option(let option, _, _): name = "Option \"\(option.label)\""; survivor = "Your other questions and their answers are not affected."; impact = (try? store.deletionImpact(optionId: option.id)) ?? DeletionImpact()
        }
        var lines = ["\(name) will be permanently deleted.", "\(impact.answers) answers will be deleted."]
        if let oldest = impact.oldest { lines.append("The oldest answer is \(oldest.formatted(date: .abbreviated, time: .omitted)).") }
        if impact.options > 0 { lines.append("\(impact.options) options will be deleted.") }
        if impact.entries > 0 { lines.append("\(impact.entries) entries will be affected.") }
        if impact.prompts > 0 { lines.append("\(impact.prompts) prompts will be deleted.") }
        lines.append(survivor)
        if impact.entriesEmptied > 0 { lines.append("\(impact.entriesEmptied) entries will be left with no answers. They stay, so your response rate does not change.") }
        lines.append("It cannot be undone.")
        return lines.joined(separator: " ")
    }
}
