import Foundation

/// The answers a prompt's notification offers for its survey's first question, so a
/// short prompt can be answered without opening the app.
///
/// Only a yes/no question, or a scale with at most ``maxScaleChoices`` values, fits as a
/// row of notification actions; any other first question offers nothing and the
/// notification opens the app as before. Titles are deliberately generic ("Yes", "3",
/// "1 (lowest)"): an action title can be read on the lock screen, so it never carries the
/// question's wording, a scale's endpoint labels, or anything else from the survey.
public struct NotificationAnswers: Sendable, Equatable, Hashable {
    /// One offered answer: the value it saves, the title it shows, and the action
    /// identifier that carries it back from the notification.
    public struct Choice: Sendable, Equatable, Hashable {
        public var value: AnswerValue
        public var title: String
        public var actionIdentifier: String

        public init(value: AnswerValue, title: String, actionIdentifier: String) {
            self.value = value
            self.title = title
            self.actionIdentifier = actionIdentifier
        }
    }

    /// The largest scale offered as actions, counted in values (`max - min + 1`). A 1 to 5
    /// scale fits; a 1 to 7 scale does not.
    public static let maxScaleChoices = 5

    /// The question these choices answer: the survey's first active question.
    public var questionId: String
    /// The choices in display order: yes before no, scale values ascending.
    public var choices: [Choice]

    /// The choices for `survey`'s first active question, or nil when that question is not
    /// a yes/no or a valid scale of at most ``maxScaleChoices`` values, or the survey has
    /// no active question.
    public init?(survey: Survey) {
        guard let question = survey.activeQuestions.first else { return nil }
        switch question.kind {
        case .yesNo:
            choices = [
                Choice(value: .yesNo(true), title: "Yes", actionIdentifier: "answer.yes"),
                Choice(value: .yesNo(false), title: "No", actionIdentifier: "answer.no"),
            ]
        case .scale:
            // `isValid` bounds both ends to -100...100, so the subtraction cannot overflow.
            guard let scale = question.scale, scale.isValid,
                  scale.max - scale.min + 1 <= Self.maxScaleChoices
            else { return nil }
            choices = (scale.min...scale.max).map { value in
                let title: String
                switch value {
                case scale.min: title = "\(value) (lowest)"
                case scale.max: title = "\(value) (highest)"
                default: title = "\(value)"
                }
                return Choice(value: .scale(value), title: title, actionIdentifier: "answer.scale.\(value)")
            }
        case .spectrum, .singleChoice, .multiChoice, .text:
            return nil
        }
        questionId = question.id
    }

    /// The value an action identifier stands for, or nil if these choices do not offer it
    /// (an identifier from before the question's scale was edited, say).
    public func value(forActionIdentifier identifier: String) -> AnswerValue? {
        choices.first { $0.actionIdentifier == identifier }?.value
    }
}
