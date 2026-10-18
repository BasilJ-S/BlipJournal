import Foundation
import Testing
import BlipJournalCore

// MARK: - Fixtures

private func at(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
}

private let moodQ = "q-mood"
private let spectrumQ = "q-spectrum"
private let doingQ = "q-doing"
private let withQ = "q-with"
private let restedQ = "q-rested"
private let notesQ = "q-notes"

private let survey = Survey(id: "s1", name: "Daily", questions: [
    Question(id: moodQ, kind: .scale, label: "Mood", position: 0, scale: ScaleConfig()),
    Question(id: spectrumQ, kind: .spectrum, label: "Energy", position: 1, spectrum: SpectrumConfig()),
    Question(id: doingQ, kind: .singleChoice, label: "Doing", position: 2, options: [
        ChoiceOption(id: "work", label: "Working", position: 0),
        ChoiceOption(id: "rest", label: "Resting", position: 1),
        ChoiceOption(id: "old", label: "Old", position: 2, isArchived: true),
    ]),
    Question(id: withQ, kind: .multiChoice, label: "With", position: 3, options: [
        ChoiceOption(id: "alone", label: "Alone", position: 0),
        ChoiceOption(id: "friends", label: "Friends", position: 1),
    ]),
    Question(id: restedQ, kind: .yesNo, label: "Rested", position: 4),
    Question(id: notesQ, kind: .text, label: "Notes", position: 5),
])
private let other = Survey(id: "s2", name: "Evening")
private let surveys = [survey.id: survey, other.id: other]

private func entry(
    _ id: String, _ seconds: TimeInterval, survey: String = "s1",
    prompted: Bool = false, completed: Bool = true
) -> Entry {
    Entry(
        id: id, surveyId: survey, promptId: prompted ? "p-\(id)" : nil, startedAt: at(seconds),
        completedAt: completed ? at(seconds + 60) : nil)
}

private func answer(_ entryId: String, _ questionId: String, _ value: AnswerValue) -> Answer {
    Answer(
        id: "a-\(entryId)-\(questionId)", entryId: entryId, questionId: questionId,
        questionVersionId: "v-\(questionId)", answeredAt: at(0), value: value)
}

private func ids(_ entries: [Entry]) -> [String] { entries.map(\.id) }

// MARK: - Tests

@Suite("Journal query")
struct JournalQueryTests {
    private let entries = [
        entry("a", 100, prompted: true),
        entry("b", 300),
        entry("c", 200, completed: false),
        entry("d", 400, survey: "s2", prompted: true),
    ]

    @Test("the default filter keeps everything, newest first, and is inactive")
    func defaults() {
        let filter = JournalFilter()
        #expect(!filter.isActive)
        #expect(ids(JournalQuery.apply(entries, filter: filter, sort: .newestFirst, answers: [])) == ["d", "b", "c", "a"])
        #expect(ids(JournalQuery.apply(entries, filter: filter, sort: .oldestFirst, answers: [])) == ["a", "c", "b", "d"])
    }

    @Test("equal start times break by identifier, both directions")
    func dateTies() {
        let tied = [entry("y", 100), entry("x", 100), entry("z", 100)]
        #expect(ids(JournalQuery.apply(tied, filter: JournalFilter(), sort: .newestFirst, answers: [])) == ["z", "y", "x"])
        #expect(ids(JournalQuery.apply(tied, filter: JournalFilter(), sort: .oldestFirst, answers: [])) == ["x", "y", "z"])
    }

    @Test("survey, source and status narrow on entry metadata", arguments: [
        (JournalFilter(surveyId: "s1"), ["b", "c", "a"]),
        (JournalFilter(source: .prompted), ["d", "a"]),
        (JournalFilter(source: .manual), ["b", "c"]),
        (JournalFilter(status: .completed), ["d", "b", "a"]),
        (JournalFilter(status: .draft), ["c"]),
        (JournalFilter(surveyId: "s1", source: .prompted, status: .completed), ["a"]),
    ])
    func metadata(filter: JournalFilter, expected: [String]) {
        #expect(filter.isActive)
        #expect(ids(JournalQuery.apply(entries, filter: filter, sort: .newestFirst, answers: [])) == expected)
    }

    @Test("an option condition matches single choice and multi-choice membership")
    func optionCondition() {
        let answers = [
            answer("a", doingQ, .single(optionId: "work")),
            answer("b", doingQ, .single(optionId: "rest")),
            answer("a", withQ, .multi(optionIds: ["alone"])),
            answer("b", withQ, .multi(optionIds: ["friends", "alone"])),
            answer("c", withQ, .multi(optionIds: [])),
        ]
        let working = JournalFilter(surveyId: "s1", answer: .option(questionId: doingQ, optionId: "work"))
        #expect(ids(JournalQuery.apply(entries, filter: working, sort: .newestFirst, answers: answers)) == ["a"])
        let alone = JournalFilter(surveyId: "s1", answer: .option(questionId: withQ, optionId: "alone"))
        #expect(ids(JournalQuery.apply(entries, filter: alone, sort: .newestFirst, answers: answers)) == ["b", "a"])
    }

    @Test("a yes/no condition matches only that value; unanswered entries never match")
    func yesNoCondition() {
        let answers = [answer("a", restedQ, .yesNo(true)), answer("b", restedQ, .yesNo(false))]
        let yes = JournalFilter(surveyId: "s1", answer: .yesNo(questionId: restedQ, value: true))
        let no = JournalFilter(surveyId: "s1", answer: .yesNo(questionId: restedQ, value: false))
        #expect(ids(JournalQuery.apply(entries, filter: yes, sort: .newestFirst, answers: answers)) == ["a"])
        #expect(ids(JournalQuery.apply(entries, filter: no, sort: .newestFirst, answers: answers)) == ["b"])
    }

    @Test("a condition never matches a value of another kind")
    func kindMismatch() {
        #expect(!JournalAnswerFilter.yesNo(questionId: restedQ, value: true).matches(.scale(1)))
        #expect(!JournalAnswerFilter.option(questionId: doingQ, optionId: "work").matches(.text("work")))
    }

    @Test("answer sort orders by value, puts unanswered last newest first, and breaks ties newest first")
    func answerSort() {
        let many = [entry("a", 100), entry("b", 200), entry("c", 300), entry("d", 400), entry("e", 500)]
        let answers = [
            answer("a", moodQ, .scale(5)),
            answer("b", moodQ, .scale(2)),
            answer("c", moodQ, .scale(5)),
            answer("d", restedQ, .yesNo(true)),
        ]
        let high = JournalQuery.apply(
            many, filter: JournalFilter(), sort: .answer(questionId: moodQ, descending: true), answers: answers)
        #expect(ids(high) == ["c", "a", "b", "e", "d"])
        let low = JournalQuery.apply(
            many, filter: JournalFilter(), sort: .answer(questionId: moodQ, descending: false), answers: answers)
        #expect(ids(low) == ["b", "c", "a", "e", "d"])
    }

    @Test("spectrum answers sort by position and non-finite positions count as unanswered")
    func spectrumSort() {
        let many = [entry("a", 100), entry("b", 200), entry("c", 300)]
        let answers = [
            answer("a", spectrumQ, .spectrum(0.25)),
            answer("b", spectrumQ, .spectrum(.nan)),
            answer("c", spectrumQ, .spectrum(0.75)),
        ]
        let sorted = JournalQuery.apply(
            many, filter: JournalFilter(), sort: .answer(questionId: spectrumQ, descending: true), answers: answers)
        #expect(ids(sorted) == ["c", "a", "b"])
    }

    @Test("questionIds lists the filter question then the sort question, without repeats")
    func questionIds() {
        let filter = JournalFilter(surveyId: "s1", answer: .yesNo(questionId: restedQ, value: true))
        #expect(JournalQuery.questionIds(filter: JournalFilter(), sort: .newestFirst).isEmpty)
        #expect(JournalQuery.questionIds(filter: filter, sort: .answer(questionId: moodQ, descending: true)) == [restedQ, moodQ])
        #expect(JournalQuery.questionIds(filter: filter, sort: .answer(questionId: restedQ, descending: true)) == [restedQ])
    }

    @Test("normalized keeps a valid query untouched")
    func normalizedValid() {
        let filter = JournalFilter(surveyId: "s1", answer: .option(questionId: doingQ, optionId: "old"))
        let sort = JournalSort.answer(questionId: spectrumQ, descending: false)
        let result = JournalQuery.normalized(filter: filter, sort: sort, surveys: surveys)
        #expect(result.filter == filter)
        #expect(result.sort == sort)
    }

    @Test("normalized drops references that no longer resolve")
    func normalizedDrops() {
        let unknownSurvey = JournalQuery.normalized(
            filter: JournalFilter(surveyId: "gone", source: .manual, answer: .yesNo(questionId: restedQ, value: true)),
            sort: .answer(questionId: moodQ, descending: true), surveys: surveys)
        #expect(unknownSurvey.filter == JournalFilter(source: .manual))
        #expect(unknownSurvey.sort == .newestFirst)

        let wrongSurvey = JournalQuery.normalized(
            filter: JournalFilter(surveyId: "s2", answer: .yesNo(questionId: restedQ, value: true)),
            sort: .answer(questionId: moodQ, descending: true), surveys: surveys)
        #expect(wrongSurvey.filter == JournalFilter(surveyId: "s2"))
        #expect(wrongSurvey.sort == .newestFirst)

        let unknownOption = JournalQuery.normalized(
            filter: JournalFilter(surveyId: "s1", answer: .option(questionId: doingQ, optionId: "erased")),
            sort: .oldestFirst, surveys: surveys)
        #expect(unknownOption.filter.answer == nil)
        #expect(unknownOption.sort == .oldestFirst)

        let wrongKinds = JournalQuery.normalized(
            filter: JournalFilter(surveyId: "s1", answer: .yesNo(questionId: doingQ, value: true)),
            sort: .answer(questionId: notesQ, descending: true), surveys: surveys)
        #expect(wrongKinds.filter.answer == nil)
        #expect(wrongKinds.sort == .newestFirst)
    }

    @Test("defaultCondition picks the first active option, Yes, or nothing")
    func defaultCondition() throws {
        let doing = try #require(survey.questions.first { $0.id == doingQ })
        let rested = try #require(survey.questions.first { $0.id == restedQ })
        let mood = try #require(survey.questions.first { $0.id == moodQ })
        #expect(JournalAnswerFilter.defaultCondition(for: doing) == .option(questionId: doingQ, optionId: "work"))
        #expect(JournalAnswerFilter.defaultCondition(for: rested) == .yesNo(questionId: restedQ, value: true))
        #expect(JournalAnswerFilter.defaultCondition(for: mood) == nil)
        let empty = Question(id: "q-empty", kind: .multiChoice, label: "Empty", position: 0)
        #expect(JournalAnswerFilter.defaultCondition(for: empty) == nil)
    }

    @Test("sort is chronological only by date")
    func chronological() {
        #expect(JournalSort.newestFirst.isChronological)
        #expect(JournalSort.oldestFirst.isChronological)
        #expect(!JournalSort.answer(questionId: moodQ, descending: true).isChronological)
    }
}
