import Foundation
import Testing
import BlipJournalCore
@testable import BlipJournal

@MainActor
struct InsightsModelTests {
    @Test(arguments: [
        (1, 7, 0.0, 7.0),
        (0, 100, 0.0, 100.0),
        (-100, 0, -100.0, 0.0),
        (-5, 5, -5.0, 5.0),
    ])
    func bucketDomainIncludesZeroAndScaleBounds(
        min: Int, max: Int, expectedLower: Double, expectedUpper: Double
    ) {
        let domain = BucketBarChart.barDomain(for: ScaleConfig(min: min, max: max))
        #expect(domain.lowerBound == expectedLower)
        #expect(domain.upperBound == expectedUpper)
    }

    /// Gregorian calendar in Toronto, weeks starting Monday, so DST transitions and
    /// weekday buckets behave the way a real device would, whatever the test host is set to.
    private let toronto: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        toronto.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: Fixtures

    @discardableResult
    private func makeSurvey(_ store: Store, name: String = "Check-in", now: Date) throws -> Survey {
        let template = SurveyTemplate.makeDefault(now: now)
        return try store.createSurvey(
            name: name, sampling: template.sampling, questions: template.questions, now: now)
    }

    /// Writes a completed entry answering the survey's default mood question, and
    /// optionally its first multi-choice question, both at `date`.
    @discardableResult
    private func addEntry(
        _ store: Store, survey: Survey, at date: Date,
        moodValue: AnswerValue? = .spectrum(0.5), options: [String] = []
    ) throws -> Entry {
        let versionIds = try store.currentQuestionVersionIds(surveyId: survey.id)
        let entry = Entry(surveyId: survey.id, startedAt: date, completedAt: date)
        var answers: [Answer] = []
        if let moodValue, let question = survey.activeQuestions.first(where: { $0.kind == moodValue.kind }),
           let versionId = versionIds[question.id] {
            answers.append(Answer(
                entryId: entry.id, questionId: question.id, questionVersionId: versionId,
                answeredAt: date, value: moodValue))
        }
        if !options.isEmpty, let question = survey.activeQuestions.first(where: { $0.kind == .multiChoice }),
           let versionId = versionIds[question.id] {
            answers.append(Answer(
                entryId: entry.id, questionId: question.id, questionVersionId: versionId,
                answeredAt: date, value: .multi(optionIds: options)))
        }
        try store.saveEntry(entry, answers: answers)
        return entry
    }

    private func prompt(_ survey: Survey, _ date: Date, status: PromptStatus) -> Prompt {
        Prompt(
            surveyId: survey.id, day: DayKey.string(for: date, calendar: toronto),
            scheduledAt: date, expiresAt: date.addingTimeInterval(1200),
            status: status, respondedAt: status == .pending ? nil : date)
    }

    // MARK: Question selection

    @Test func loadPicksTemplateDefaultQuestions() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let survey = try makeSurvey(store, now: at(2026, 1, 1))

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)

        #expect(model.selectedSurveyId == survey.id)
        #expect(model.moodQuestion?.label == "How are you feeling right now?")
        #expect(model.moodQuestion?.kind == .spectrum)
        #expect(model.choiceQuestion?.label == "What best describes this feeling?")
    }

    @Test func selectingAnotherScaleQuestionUpdatesEveryDerivedChart() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let focusQuestion = Question(
            kind: .scale, label: "How focused are you?", position: 0,
            scale: ScaleConfig(min: 1, max: 5, minLabel: "Not at all", maxLabel: "Very"))
        let energyQuestion = Question(kind: .scale, label: "How energetic?", position: 1, scale: ScaleConfig())
        let survey = try store.createSurvey(
            name: "Custom", sampling: .default, questions: [focusQuestion, energyQuestion], now: at(2026, 1, 1))
        let versionIds = try store.currentQuestionVersionIds(surveyId: survey.id)

        for (offset, value) in [(0, 4), (1, 2)] {
            let date = at(2026, 3, 9 + offset)
            let entry = Entry(surveyId: survey.id, startedAt: date, completedAt: date)
            try store.saveEntry(entry, answers: [
                Answer(
                    entryId: entry.id, questionId: focusQuestion.id, questionVersionId: versionIds[focusQuestion.id]!,
                    answeredAt: date, value: .scale(value)),
                Answer(
                    entryId: entry.id, questionId: energyQuestion.id, questionVersionId: versionIds[energyQuestion.id]!,
                    answeredAt: date, value: .scale(value + 3)),
            ])
        }

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)

        #expect(model.moodQuestion?.id == focusQuestion.id)
        #expect(model.series.map(\.value) == [4, 2])
        #expect(model.byHour.reduce(0) { $0 + $1.count } == 2)
        #expect(model.seriesAccessibilitySummary.hasPrefix("How focused are you?"))
        #expect(!model.seriesAccessibilitySummary.contains("Mood"))

        model.moodQuestion = energyQuestion

        #expect(model.series.map(\.value) == [7, 5])
        #expect(model.rolling.map(\.value) == [7, 6])
        #expect(model.seriesAccessibilitySummary.hasPrefix("How energetic?"))
    }

    @Test func spectrumQuestionDrivesSeriesAxesAndBuckets() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let spectrum = SpectrumConfig(zones: [
            .init(label: "Low", color: .init(red: 0, green: 0, blue: 0)),
            .init(label: "High", color: .init(red: 1, green: 1, blue: 1)),
        ], breakpoints: [0.5])
        let mood = Question(kind: .spectrum, label: "Energy", position: 0, spectrum: spectrum)
        let place = Question(kind: .singleChoice, label: "Place", position: 1, options: [
            ChoiceOption(id: "home", label: "Home", position: 0),
        ])
        let survey = try store.createSurvey(
            name: "Custom", sampling: .default, questions: [mood, place], now: at(2026, 1, 1))
        let versionIds = try store.currentQuestionVersionIds(surveyId: survey.id)
        let date = at(2026, 3, 9, 9)
        let entry = Entry(surveyId: survey.id, startedAt: date, completedAt: date)
        try store.saveEntry(entry, answers: [
            Answer(
                entryId: entry.id, questionId: mood.id, questionVersionId: versionIds[mood.id]!,
                answeredAt: date, value: .spectrum(0.42)),
            Answer(
                entryId: entry.id, questionId: place.id, questionVersionId: versionIds[place.id]!,
                answeredAt: date, value: .single(optionId: "home")),
        ])

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)

        #expect(model.moodQuestion?.id == mood.id)
        #expect(model.moodQuestions.map(\.id) == [mood.id])
        #expect(model.series.map(\.value) == [42])
        #expect(model.byHour.first { $0.id == "9" }?.mean == 42)
        #expect(model.byWeekday.reduce(0) { $0 + $1.count } == 1)
        #expect(model.byOption.first == BucketStat(id: "home", label: "Home", mean: 42, count: 1))
        #expect(model.moodAxis?.domain == 0...100)
        #expect(model.moodAxis?.minLabel == "Low")
        #expect(model.moodAxis?.maxLabel == "High")
    }

    // MARK: Range presets

    @Test func sevenDayPresetBoundariesAndFutureExclusion() throws {
        let now = at(2026, 3, 10, 15, 0)
        let store = try Store.inMemory()
        let survey = try makeSurvey(store, now: at(2026, 1, 1))

        let justBeforeStart = at(2026, 3, 3, 23, 59)
        let atStart = at(2026, 3, 4, 0, 0)
        let atNow = now
        let inFuture = now.addingTimeInterval(3600)
        for date in [justBeforeStart, atStart, atNow, inFuture] {
            try addEntry(store, survey: survey, at: date)
        }

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)
        model.range = .sevenDays

        let dates = Set(model.series.map(\.date))
        #expect(!dates.contains(justBeforeStart))
        #expect(dates.contains(atStart))
        #expect(dates.contains(atNow))
        #expect(!dates.contains(inFuture))

        model.range = .all
        #expect(Set(model.series.map(\.date)).contains(justBeforeStart))
        #expect(!Set(model.series.map(\.date)).contains(inFuture))
    }

    // MARK: Custom range

    @Test func customRangeSingleDayAndDSTTransition() throws {
        // Clocks in Toronto spring forward at 2 AM on Sunday March 8, 2026.
        let now = at(2026, 3, 20)
        let store = try Store.inMemory()
        let survey = try makeSurvey(store, now: at(2026, 1, 1))
        let beforeGap = at(2026, 3, 8, 1, 30)
        let afterGap = at(2026, 3, 8, 3, 30)
        let nextDay = at(2026, 3, 9, 0, 30)
        for date in [beforeGap, afterGap, nextDay] {
            try addEntry(store, survey: survey, at: date)
        }

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)
        model.range = .custom
        model.customStart = at(2026, 3, 8)
        model.customEnd = at(2026, 3, 8)

        #expect(Set(model.series.map(\.date)) == [beforeGap, afterGap])
    }

    @Test func customRangeRejectsInvalidOrFutureDates() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        _ = try makeSurvey(store, now: at(2026, 1, 1))

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)
        model.range = .custom
        let validStart = model.customStart
        let validEnd = model.customEnd

        model.customEnd = now.addingTimeInterval(86_400 * 5)
        #expect(model.customEnd == validEnd)

        model.customStart = validEnd.addingTimeInterval(86_400)
        #expect(model.customStart == validStart)
    }

    @Test func customDatesSurvivePresetSwitching() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        _ = try makeSurvey(store, now: at(2026, 1, 1))

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)
        model.range = .custom
        model.customStart = at(2026, 2, 1)
        model.customEnd = at(2026, 2, 15)

        model.range = .sevenDays
        model.range = .custom

        #expect(model.customStart == at(2026, 2, 1))
        #expect(model.customEnd == at(2026, 2, 15))
    }

    // MARK: By option

    @Test func byOptionRespectsSelectedRange() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let survey = try makeSurvey(store, now: at(2026, 1, 1))
        let choiceQuestion = try #require(survey.activeQuestions.first { $0.kind == .multiChoice })
        let calm = try #require(choiceQuestion.activeOptions.first { $0.label == "Calm" })
        let happy = try #require(choiceQuestion.activeOptions.first { $0.label == "Happy" })

        try addEntry(store, survey: survey, at: at(2026, 3, 9), options: [calm.id])
        try addEntry(store, survey: survey, at: at(2026, 2, 1), options: [happy.id])

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)
        model.range = .sevenDays

        #expect(model.byOption.first { $0.id == calm.id }?.count == 1)
        #expect(model.byOption.first { $0.id == happy.id }?.count == 0)
        #expect(model.optionDistributions.first { $0.id == calm.id }?.median == 50)
        #expect(model.comparison(optionId: calm.id).map(\.count) == [1, 0])
        let selected = try #require(model.comparison(optionId: calm.id).first)
        #expect(model.entries(in: selected).map(\.id) == selected.points.map(\.entryId))

        model.range = .all
        #expect(model.byOption.first { $0.id == happy.id }?.count == 1)
        #expect(model.comparison(optionId: calm.id).map(\.count) == [1, 1])
        try addEntry(store, survey: survey, at: now.addingTimeInterval(3600), options: [calm.id])
        try model.load(now: now)
        #expect(model.comparison(optionId: calm.id).map(\.count) == [1, 1])
        try store.deleteEntry(try #require(selected.points.first).entryId)
        try model.load(now: now)
        #expect(model.comparison(optionId: calm.id).map(\.count) == [0, 1])
        #expect(model.entries(in: selected).isEmpty)
    }

    @Test func byOptionAccessibilitySummaryDoesNotOvercountMultiChoiceEntries() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let survey = try makeSurvey(store, now: at(2026, 1, 1))
        let choiceQuestion = try #require(survey.activeQuestions.first { $0.kind == .multiChoice })
        let calm = try #require(choiceQuestion.activeOptions.first { $0.label == "Calm" })
        let happy = try #require(choiceQuestion.activeOptions.first { $0.label == "Happy" })

        // One entry selecting two options must be reported as one selection-count of
        // two, not two "entries": `Analytics.byOption` counts it once per bucket.
        try addEntry(store, survey: survey, at: at(2026, 3, 9), options: [calm.id, happy.id])

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)

        let totalBucketCount = model.byOption.reduce(0) { $0 + $1.count }
        #expect(totalBucketCount == 2)
        #expect(model.byOptionAccessibilitySummary.contains("2 selections total"))
        #expect(!model.byOptionAccessibilitySummary.contains("entries total"))
    }

    // MARK: Reload staleness

    @Test func reloadReflectsEntriesWrittenAfterTheInitialLoad() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let survey = try makeSurvey(store, now: at(2026, 1, 1))

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)
        #expect(model.series.isEmpty)

        try addEntry(store, survey: survey, at: at(2026, 3, 9))
        #expect(model.series.isEmpty) // stale until the caller reloads

        try model.load(now: now)
        #expect(model.series.count == 1)
    }

    // MARK: Compliance

    @Test func complianceCountsOnlySelectedSurveyAndRangeExcludingFuture() throws {
        let now = at(2026, 3, 10, 12, 0)
        let store = try Store.inMemory()
        let surveyA = try makeSurvey(store, name: "A", now: at(2026, 1, 1))
        let surveyB = try makeSurvey(store, name: "B", now: at(2026, 1, 1))

        try store.insertPrompts([
            prompt(surveyA, at(2026, 3, 9), status: .answered),
            prompt(surveyA, at(2026, 3, 1), status: .missed),
            prompt(surveyA, now.addingTimeInterval(3600), status: .pending),
            prompt(surveyB, at(2026, 3, 9), status: .answered),
        ])

        let model = InsightsModel(store: store, calendar: toronto)
        model.selectedSurveyId = surveyA.id
        try model.load(now: now)
        model.range = .sevenDays

        #expect(model.compliance.answered == 1)
        #expect(model.compliance.missed == 0)
        #expect(model.compliance.pending == 0)

        model.range = .all
        #expect(model.compliance.missed == 1)
        #expect(model.compliance.pending == 0)
    }

    // MARK: Survey selection

    @Test func switchingSurveyReloadsAndClearsStaleSelections() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let surveyA = try makeSurvey(store, name: "A", now: at(2026, 1, 1))
        let focusQuestion = Question(kind: .scale, label: "Focus", position: 0, scale: ScaleConfig())
        let surveyB = try store.createSurvey(
            name: "B", sampling: .default, questions: [focusQuestion], now: at(2026, 1, 1))

        let model = InsightsModel(store: store, calendar: toronto)
        model.selectedSurveyId = surveyA.id
        try model.load(now: now)
        #expect(model.moodQuestion?.label == "How are you feeling right now?")

        model.selectedSurveyId = surveyB.id
        try model.load(now: now)

        #expect(model.moodQuestion?.id == focusQuestion.id)
        #expect(model.choiceQuestion == nil)
    }

    @Test func archivedSurveysAreOrderedAfterActiveAndStayHistoricallyVisible() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let surveyA = try makeSurvey(store, name: "A", now: at(2026, 1, 1))
        let surveyB = try makeSurvey(store, name: "B", now: at(2026, 1, 2))
        try addEntry(store, survey: surveyA, at: at(2026, 2, 1), moodValue: .spectrum(0.3))
        try store.archiveSurvey(surveyA.id, now: at(2026, 1, 3))

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)

        #expect(model.selectedSurveyId == surveyB.id)
        #expect(model.surveys.map(\.id) == [surveyB.id, surveyA.id])

        model.selectedSurveyId = surveyA.id
        try model.load(now: now)
        model.range = .all

        #expect(model.snapshot?.survey.isArchived == true)
        #expect(model.series.count == 1)
    }

    @Test func selectionFallsBackToArchivedWhenNoActiveSurveyExists() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let survey = try makeSurvey(store, now: at(2026, 1, 1))
        try store.archiveSurvey(survey.id, now: at(2026, 1, 2))

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)

        #expect(model.selectedSurveyId == survey.id)
    }

    @Test func selectionIsNilWithNoSurveys() throws {
        let store = try Store.inMemory()
        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: at(2026, 3, 10))

        #expect(model.selectedSurveyId == nil)
        #expect(model.snapshot == nil)
        #expect(model.series.isEmpty)
        #expect(model.compliance.rate == nil)
    }

    @Test func reloadPreservesSelectionAfterArchiveAndFallsBackAfterHardDelete() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        let surveyA = try makeSurvey(store, name: "A", now: at(2026, 1, 1))
        let surveyB = try makeSurvey(store, name: "B", now: at(2026, 1, 2))

        let model = InsightsModel(store: store, calendar: toronto)
        model.selectedSurveyId = surveyA.id
        try model.load(now: now)
        #expect(model.selectedSurveyId == surveyA.id)

        try store.archiveSurvey(surveyA.id, now: at(2026, 1, 3))
        try model.load(now: now)
        #expect(model.selectedSurveyId == surveyA.id)

        try store.hardDeleteSurvey(surveyA.id)
        try model.load(now: now)

        #expect(model.selectedSurveyId == surveyB.id)
        #expect(model.snapshot?.survey.id == surveyB.id)
        #expect(model.series.isEmpty)
    }

    // MARK: Empty survey

    @Test func emptySurveyYieldsEmptySeriesAndNilComplianceRateWithoutThrowing() throws {
        let now = at(2026, 3, 10)
        let store = try Store.inMemory()
        _ = try makeSurvey(store, now: at(2026, 1, 1))

        let model = InsightsModel(store: store, calendar: toronto)
        try model.load(now: now)

        #expect(model.series.isEmpty)
        #expect(model.compliance.rate == nil)
        #expect(model.byHour.allSatisfy { $0.count == 0 })
        #expect(model.byWeekday.allSatisfy { $0.count == 0 })
    }
}
