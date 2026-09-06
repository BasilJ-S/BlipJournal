import Foundation
import Testing
import BlipJournalCore

@Suite("Store definitions")
struct StoreDefinitionsTests {
    private let t = Fixture.at

    @Test("createSurvey from the template reads back equal to the template")
    func createFromTemplate() throws {
        let store = try Store.inMemory()
        let template = SurveyTemplate.makeDefault(now: t(0))

        let created = try store.createSurvey(
            name: template.name, sampling: template.sampling, questions: template.questions, now: t(0))

        var expected = template
        expected.id = created.id
        expected.createdAt = created.createdAt
        #expect(created == expected)
        #expect(created.createdAt == t(0))
        #expect(try store.survey(created.id) == created)
        #expect(try store.surveys(includeArchived: false) == [created])
    }

    @Test("renaming a question three times gives four label versions in order, and the survey shows the last")
    func renameQuestion() throws {
        let (store, survey) = try Fixture.seeded()
        let question = try survey.question(labelled: "Anything else?")

        for (index, label) in ["One", "Two", "Three"].enumerated() {
            try store.updateQuestion(
                question.id, label: label, position: question.position, isRequired: question.isRequired,
                isArchived: false, scale: nil, allowsCustomOptions: false, now: t(Double(index + 1)))
        }

        let history = try store.labelHistory(questionId: question.id)
        #expect(history == [
            LabelVersion(label: "Anything else?", validFrom: t(0)),
            LabelVersion(label: "One", validFrom: t(1)),
            LabelVersion(label: "Two", validFrom: t(2)),
            LabelVersion(label: "Three", validFrom: t(3)),
        ])
        let reloaded = try #require(try store.survey(survey.id))
        #expect(try reloaded.question(labelled: "Three").id == question.id)
        #expect(reloaded.questions.count == 6)
    }

    @Test("two versions written with the same now resolve by insertion order")
    func sameTimestampResolvesByInsertion() throws {
        let (store, survey) = try Fixture.seeded()
        let question = try survey.question(labelled: "Anything else?")

        for label in ["B", "C"] {
            try store.updateQuestion(
                question.id, label: label, position: 5, isRequired: false, isArchived: false,
                scale: nil, allowsCustomOptions: false, now: t(1))
        }

        #expect(try store.labelHistory(questionId: question.id).map(\.label) == ["Anything else?", "B", "C"])
        let reloaded = try #require(try store.survey(survey.id))
        #expect(reloaded.questions.first { $0.id == question.id }?.label == "C")
        #expect(try store.labelHistory(questionId: question.id).label(at: t(1)) == "C")
    }

    @Test("updateSampling twice makes the second the survey's sampling")
    func updateSampling() throws {
        let (store, survey) = try Fixture.seeded()
        let first = SamplingConfig(promptsPerDay: 5)
        let second = SamplingConfig(promptsPerDay: 2, windowStartMinutes: 600, isEnabled: false)

        try store.updateSampling(surveyId: survey.id, first, now: t(1))
        try store.updateSampling(surveyId: survey.id, second, now: t(2))

        #expect(try store.survey(survey.id)?.sampling == second)
        #expect(try store.backup(now: t(3)).surveySamplings.count == 3)
    }

    @Test("currentQuestionVersionIds changes for exactly the renamed question")
    func currentVersionIds() throws {
        let (store, survey) = try Fixture.seeded()
        let before = try store.currentQuestionVersionIds(surveyId: survey.id)
        #expect(Set(before.keys) == Set(survey.questions.map(\.id)))
        let renamed = try survey.question(labelled: "What are you doing?")

        try store.updateQuestion(
            renamed.id, label: "Doing what?", position: renamed.position, isRequired: false,
            isArchived: false, scale: nil, allowsCustomOptions: true, now: t(1))

        let after = try store.currentQuestionVersionIds(surveyId: survey.id)
        #expect(after[renamed.id] != before[renamed.id])
        for question in survey.questions where question.id != renamed.id {
            #expect(after[question.id] == before[question.id])
        }
        #expect(try store.currentQuestionVersionIds(surveyId: "nope").isEmpty)
    }

    @Test("archiving a question leaves its options' own flags alone, and unarchiving restores the same active set")
    func archiveQuestionKeepsOptionFlags() throws {
        let (store, survey) = try Fixture.seeded()
        let question = try survey.question(labelled: "Who are you with?")
        let strangers = try question.option(labelled: "Strangers")
        try store.updateOption(strangers.id, label: strangers.label, position: strangers.position, isArchived: true, now: t(1))
        let activeBefore = try #require(try store.survey(survey.id)?.questions
            .first { $0.id == question.id }).activeOptions.map(\.id)
        #expect(activeBefore.count == 5)

        try store.updateQuestion(
            question.id, label: question.label, position: question.position, isRequired: false,
            isArchived: true, scale: nil, allowsCustomOptions: true, now: t(2))
        let archived = try #require(try store.survey(survey.id)?.questions.first { $0.id == question.id })
        #expect(archived.isArchived)
        #expect(archived.options.filter(\.isArchived).map(\.id) == [strangers.id])
        #expect(archived.options.count == 6)
        #expect(try store.backup(now: t(3)).optionVersions.count == 41 + 1)

        try store.updateQuestion(
            question.id, label: question.label, position: question.position, isRequired: false,
            isArchived: false, scale: nil, allowsCustomOptions: true, now: t(3))
        let restored = try #require(try store.survey(survey.id)?.questions.first { $0.id == question.id })
        #expect(!restored.isArchived)
        #expect(restored.activeOptions.map(\.id) == activeBefore)
    }

    @Test("an archived option stays in the current view with isArchived set")
    func archiveOption() throws {
        let (store, survey) = try Fixture.seeded()
        let question = try survey.question(labelled: "What are you doing?")
        let option = try question.option(labelled: "Chores")

        try store.updateOption(option.id, label: "Chores", position: option.position, isArchived: true, now: t(1))

        let reloaded = try #require(try store.survey(survey.id)?.questions.first { $0.id == question.id })
        let current = try reloaded.option(labelled: "Chores")
        #expect(current.id == option.id)
        #expect(current.isArchived)
        #expect(reloaded.options.count == 10)
        #expect(reloaded.activeOptions.count == 9)
        #expect(try store.labelHistory(optionId: option.id).count == 2)
    }

    @Test("renaming and archiving a survey append versions and filter listings")
    func surveyVersions() throws {
        let store = try Store.inMemory()
        let first = try Fixture.seed(store, name: "First", now: t(0))
        let second = try Fixture.seed(store, name: "Second", now: t(1))

        try store.renameSurvey(first.id, to: "Renamed", now: t(2))
        try store.archiveSurvey(first.id, now: t(3))

        #expect(try store.labelHistory(surveyId: first.id) == [
            LabelVersion(label: "First", validFrom: t(0)),
            LabelVersion(label: "Renamed", validFrom: t(2)),
            LabelVersion(label: "Renamed", validFrom: t(3)),
        ])
        let archived = try #require(try store.survey(first.id))
        #expect(archived.name == "Renamed")
        #expect(archived.isArchived)
        #expect(archived.questions.allSatisfy { !$0.isArchived })
        #expect(try store.surveys(includeArchived: false).map(\.id) == [second.id])
        #expect(try store.surveys(includeArchived: true).map(\.id) == [first.id, second.id])
    }

    @Test("addQuestion and addOption append at the end, counting archived positions")
    func addAppendsAtEnd() throws {
        let (store, survey) = try Fixture.seeded()
        let last = try survey.question(labelled: "Anything else?")
        try store.updateQuestion(
            last.id, label: last.label, position: last.position, isRequired: false,
            isArchived: true, scale: nil, allowsCustomOptions: false, now: t(1))

        let added = try store.addQuestion(
            surveyId: survey.id, kind: .yesNo, label: "Slept well?", isRequired: false,
            scale: nil, allowsCustomOptions: false, now: t(2))
        #expect(added.position == 6)
        #expect(added.kind == .yesNo)
        #expect(added.options.isEmpty)

        let scaled = try store.addQuestion(
            surveyId: survey.id, kind: .scale, label: "Energy?", isRequired: true,
            scale: ScaleConfig(min: 0, max: 10, minLabel: "Flat", maxLabel: "Buzzing"),
            allowsCustomOptions: false, now: t(3))
        #expect(scaled.position == 7)

        let reloaded = try #require(try store.survey(survey.id))
        #expect(reloaded.questions.count == 8)
        #expect(reloaded.questions.first { $0.id == added.id } == added)
        #expect(reloaded.questions.first { $0.id == scaled.id } == scaled)
        #expect(reloaded.activeQuestions.map(\.position) == [0, 1, 2, 3, 4, 6, 7])

        let doing = try survey.question(labelled: "What are you doing?")
        let option = try store.addOption(questionId: doing.id, label: "Gardening", now: t(4))
        #expect(option.position == 10)
        #expect(!option.isArchived)
        let question = try #require(try store.survey(survey.id)?.questions.first { $0.id == doing.id })
        #expect(question.options.count == 11)
        #expect(try question.option(labelled: "Gardening") == option)

        let empty = try store.addQuestion(
            surveyId: survey.id, kind: .singleChoice, label: "Where?", isRequired: false,
            scale: nil, allowsCustomOptions: true, now: t(5))
        #expect(try store.addOption(questionId: empty.id, label: "Home", now: t(6)).position == 0)
    }

    @Test("every mutator throws notFound for an unknown identifier")
    func unknownIdentifiers() throws {
        let (store, _) = try Fixture.seeded()
        #expect(throws: StoreError.notFound) { try store.renameSurvey("x", to: "y", now: t(1)) }
        #expect(throws: StoreError.notFound) { try store.archiveSurvey("x", now: t(1)) }
        #expect(throws: StoreError.notFound) { try store.updateSampling(surveyId: "x", .default, now: t(1)) }
        #expect(throws: StoreError.notFound) {
            try store.addQuestion(
                surveyId: "x", kind: .text, label: "?", isRequired: false, scale: nil,
                allowsCustomOptions: false, now: t(1))
        }
        #expect(throws: StoreError.notFound) {
            try store.updateQuestion(
                "x", label: "?", position: 0, isRequired: false, isArchived: false, scale: nil,
                allowsCustomOptions: false, now: t(1))
        }
        #expect(throws: StoreError.notFound) { try store.addOption(questionId: "x", label: "?", now: t(1)) }
        #expect(throws: StoreError.notFound) { try store.updateOption("x", label: "?", position: 0, isArchived: false, now: t(1)) }
        #expect(try store.survey("x") == nil)
        #expect(try store.labelHistory(surveyId: "x").isEmpty)
        #expect(try store.labelHistory(questionId: "x").isEmpty)
        #expect(try store.labelHistory(optionId: "x").isEmpty)
    }

    @Test("surveys are listed in createdAt order regardless of insertion order")
    func surveysOrdered() throws {
        let store = try Store.inMemory()
        let later = try Fixture.seed(store, name: "Later", now: t(10))
        let earlier = try Fixture.seed(store, name: "Earlier", now: t(5))
        #expect(try store.surveys(includeArchived: true).map(\.id) == [earlier.id, later.id])
    }
}
