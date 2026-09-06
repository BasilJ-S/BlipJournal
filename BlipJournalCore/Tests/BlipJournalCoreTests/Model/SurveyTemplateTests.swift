import Foundation
import Testing
import OpenBlipCore

@Suite("SurveyTemplate")
struct SurveyTemplateTests {
    /// The six default questions as the README and the C1 handoff specify them.
    private static let expected: [(kind: QuestionKind, label: String, options: Int, isRequired: Bool)] = [
        (.scale, "How are you feeling right now?", 0, true),
        (.multiChoice, "What best describes this feeling?", 12, false),
        (.multiChoice, "What is having the biggest impact?", 13, false),
        (.singleChoice, "What are you doing?", 10, false),
        (.multiChoice, "Who are you with?", 6, false),
        (.text, "Anything else?", 0, false),
    ]

    @Test("the default survey has six questions in position order")
    func questionCount() {
        let survey = SurveyTemplate.makeDefault()
        #expect(survey.questions.count == 6)
        #expect(survey.activeQuestions.map(\.position) == [0, 1, 2, 3, 4, 5])
        #expect(survey.activeQuestions == survey.questions)
    }

    @Test("each question has the expected kind, label, option count and required flag")
    func questionContents() {
        let questions = SurveyTemplate.makeDefault().activeQuestions
        for (index, expected) in Self.expected.enumerated() {
            let question = questions[index]
            #expect(question.kind == expected.kind)
            #expect(question.label == expected.label)
            #expect(question.options.count == expected.options)
            #expect(question.isRequired == expected.isRequired)
        }
    }

    @Test("only the scale question carries a ScaleConfig, and it is 1 to 7")
    func scaleQuestion() throws {
        let questions = SurveyTemplate.makeDefault().activeQuestions
        let scale = try #require(questions.first?.scale)
        #expect(scale.min == 1)
        #expect(scale.max == 7)
        #expect(scale.minLabel == "Very unpleasant")
        #expect(scale.maxLabel == "Very pleasant")
        #expect(scale.isValid)
        #expect(questions.dropFirst().allSatisfy { $0.scale == nil })
    }

    @Test("every choice question allows custom options and no other kind does")
    func customOptions() {
        for question in SurveyTemplate.makeDefault().activeQuestions {
            #expect(question.allowsCustomOptions == question.kind.usesOptions)
        }
    }

    @Test("option labels and order match the handoff")
    func optionLabels() {
        let questions = SurveyTemplate.makeDefault().activeQuestions
        #expect(questions[1].activeOptions.map(\.label) == [
            "Calm", "Content", "Happy", "Excited", "Focused", "Tired",
            "Bored", "Anxious", "Stressed", "Irritated", "Sad", "Lonely",
        ])
        #expect(questions[2].activeOptions.map(\.label) == [
            "Work", "Study", "Family", "Partner", "Friends", "Health",
            "Sleep", "Exercise", "Food", "Money", "Weather", "News", "Hobbies",
        ])
        #expect(questions[3].activeOptions.map(\.label) == [
            "Working", "Studying", "Commuting", "Eating", "Socialising",
            "Exercising", "Resting", "Chores", "Screen time", "Outdoors",
        ])
        #expect(questions[4].activeOptions.map(\.label) == [
            "Alone", "Partner", "Family", "Friends", "Colleagues", "Strangers",
        ])
    }

    @Test("option positions number from zero within each question")
    func optionPositions() {
        for question in SurveyTemplate.makeDefault().activeQuestions {
            #expect(question.options.map(\.position) == Array(0..<question.options.count))
            #expect(question.options.allSatisfy { !$0.isArchived })
        }
    }

    @Test("the survey is live and uses the default schedule")
    func surveyDefaults() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let survey = SurveyTemplate.makeDefault(now: now)
        #expect(survey.createdAt == now)
        #expect(!survey.isArchived)
        #expect(survey.sampling == .default)
        #expect(!survey.name.isEmpty)
    }

    @Test("every identifier in the survey is unique")
    func identifiersAreUnique() {
        let survey = SurveyTemplate.makeDefault()
        var ids = [survey.id]
        for question in survey.questions {
            ids.append(question.id)
            ids.append(contentsOf: question.options.map(\.id))
        }
        #expect(ids.count == 1 + 6 + 41)
        #expect(Set(ids).count == ids.count)
    }

    @Test("two calls produce equal content but no shared identifiers")
    func callsAreIndependent() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = SurveyTemplate.makeDefault(now: now)
        let second = SurveyTemplate.makeDefault(now: now)

        #expect(first != second)
        #expect(first.id != second.id)
        #expect(first.activeQuestions.map(\.label) == second.activeQuestions.map(\.label))

        func allIDs(_ survey: Survey) -> Set<String> {
            var ids: Set<String> = [survey.id]
            for question in survey.questions {
                ids.insert(question.id)
                ids.formUnion(question.options.map(\.id))
            }
            return ids
        }
        #expect(allIDs(first).isDisjoint(with: allIDs(second)))
    }

    @Test("the whole survey round-trips through JSON")
    func roundTrips() throws {
        let survey = SurveyTemplate.makeDefault()
        let data = try JSONEncoder().encode(survey)
        #expect(try JSONDecoder().decode(Survey.self, from: data) == survey)
    }
}
