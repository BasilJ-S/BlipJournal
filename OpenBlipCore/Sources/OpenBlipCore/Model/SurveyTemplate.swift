import Foundation

/// The survey a fresh install starts with.
///
/// This is a factory, not stored state: every call mints new identifiers, so the
/// template can be used to seed a first survey and again whenever the user wants
/// another copy without the two sharing identity.
public enum SurveyTemplate {
    /// The six-question default survey from the README, with the default schedule.
    ///
    /// Positions start at 0 and follow the order below. Only the first question is
    /// required. Every identifier in the returned survey is freshly generated, so two
    /// calls are equal in content and different in identity.
    ///
    /// - Parameter now: The creation timestamp to stamp on the survey.
    public static func makeDefault(now: Date = Date()) -> Survey {
        Survey(
            name: "Daily check-in",
            createdAt: now,
            sampling: .default,
            questions: [
                Question(
                    kind: .scale,
                    label: "How are you feeling right now?",
                    position: 0,
                    isRequired: true,
                    scale: ScaleConfig(
                        min: 1,
                        max: 7,
                        minLabel: "Very unpleasant",
                        maxLabel: "Very pleasant"
                    )
                ),
                Question(
                    kind: .multiChoice,
                    label: "What best describes this feeling?",
                    position: 1,
                    allowsCustomOptions: true,
                    options: makeOptions([
                        "Calm", "Content", "Happy", "Excited", "Focused", "Tired",
                        "Bored", "Anxious", "Stressed", "Irritated", "Sad", "Lonely",
                    ])
                ),
                Question(
                    kind: .multiChoice,
                    label: "What is having the biggest impact?",
                    position: 2,
                    allowsCustomOptions: true,
                    options: makeOptions([
                        "Work", "Study", "Family", "Partner", "Friends", "Health",
                        "Sleep", "Exercise", "Food", "Money", "Weather", "News",
                        "Hobbies",
                    ])
                ),
                Question(
                    kind: .singleChoice,
                    label: "What are you doing?",
                    position: 3,
                    allowsCustomOptions: true,
                    options: makeOptions([
                        "Working", "Studying", "Commuting", "Eating", "Socialising",
                        "Exercising", "Resting", "Chores", "Screen time", "Outdoors",
                    ])
                ),
                Question(
                    kind: .multiChoice,
                    label: "Who are you with?",
                    position: 4,
                    allowsCustomOptions: true,
                    options: makeOptions([
                        "Alone", "Partner", "Family", "Friends", "Colleagues",
                        "Strangers",
                    ])
                ),
                Question(
                    kind: .text,
                    label: "Anything else?",
                    position: 5
                ),
            ]
        )
    }

    /// Wraps labels as options, numbering positions from 0 in the order given.
    private static func makeOptions(_ labels: [String]) -> [ChoiceOption] {
        labels.enumerated().map { position, label in
            ChoiceOption(label: label, position: position)
        }
    }
}
