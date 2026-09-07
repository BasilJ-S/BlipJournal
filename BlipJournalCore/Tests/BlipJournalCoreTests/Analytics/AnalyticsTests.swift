import Foundation
import Testing
import BlipJournalCore

// MARK: - Fixtures

/// Gregorian calendar in Toronto, weeks starting on Monday, POSIX locale so the
/// weekday symbols are the English abbreviations whatever the machine's locale.
private let toronto: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Toronto")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 2
    return calendar
}()

/// A local Toronto instant.
private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    toronto.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let scaleQ = "q-scale"
private let choiceQ = "q-choice"
private let textQ = "q-text"

/// A scale question, a multi-choice question with two live and two archived options,
/// and a text question.
private let survey = Survey(id: "s1", name: "Test", createdAt: at(2026, 1, 1), questions: [
    Question(id: textQ, kind: .text, label: "Notes", position: 2),
    Question(id: choiceQ, kind: .multiChoice, label: "Where", position: 1, options: [
        ChoiceOption(id: "opt-d", label: "Delta", position: 3, isArchived: true),
        ChoiceOption(id: "opt-b", label: "Bravo", position: 1),
        ChoiceOption(id: "opt-c", label: "Charlie", position: 2, isArchived: true),
        ChoiceOption(id: "opt-a", label: "Alpha", position: 0),
    ]),
    Question(id: scaleQ, kind: .scale, label: "Mood", position: 0, scale: ScaleConfig()),
])

private func snapshot(_ survey: Survey = survey, entries: [ExportEntry]) -> ExportSnapshot {
    var questionHistory = [String: [LabelVersion]]()
    var optionHistory = [String: [LabelVersion]]()
    var versionLabels = [String: String]()
    for question in survey.questions {
        questionHistory[question.id] = [LabelVersion(label: question.label, validFrom: survey.createdAt)]
        versionLabels["\(question.id)-v1"] = question.label
        for option in question.options {
            optionHistory[option.id] = [LabelVersion(label: option.label, validFrom: survey.createdAt)]
        }
    }
    return ExportSnapshot(
        survey: survey,
        entries: entries,
        questionLabelHistory: questionHistory,
        optionLabelHistory: optionHistory,
        questionVersionLabels: versionLabels
    )
}

private func prompt(id: String, status: PromptStatus) -> Prompt {
    Prompt(
        id: id, surveyId: "s1", day: "2026-03-02",
        scheduledAt: at(2026, 3, 2, 9), expiresAt: at(2026, 3, 2, 10),
        status: status, respondedAt: status == .pending ? nil : at(2026, 3, 2, 9, 30)
    )
}

/// One entry answered at `date`. `answers` maps question ID to value; answer IDs are
/// `"<entryId>/<questionId>"` unless `answerIds` overrides them.
private func entry(
    _ id: String,
    at date: Date,
    prompted: Bool = true,
    completed: Bool = true,
    answers: [(question: String, value: AnswerValue, answerId: String?)]
) -> ExportEntry {
    let entry = Entry(
        id: id, surveyId: "s1",
        promptId: prompted ? "p-\(id)" : nil,
        startedAt: date, completedAt: completed ? date : nil
    )
    let prompt = prompted ? prompt(id: "p-\(id)", status: .answered) : nil
    return ExportEntry(entry: entry, prompt: prompt, answers: answers.map {
        Answer(
            id: $0.answerId ?? "\(id)/\($0.question)", entryId: id, questionId: $0.question,
            questionVersionId: "\($0.question)-v1", answeredAt: date, value: $0.value
        )
    })
}

private func entry(
    _ id: String,
    at date: Date,
    prompted: Bool = true,
    completed: Bool = true,
    mood: Int? = nil,
    options: [String]? = nil
) -> ExportEntry {
    var answers = [(question: String, value: AnswerValue, answerId: String?)]()
    if let mood { answers.append((scaleQ, .scale(mood), nil)) }
    if let options { answers.append((choiceQ, .multi(optionIds: options), nil)) }
    return entry(id, at: date, prompted: prompted, completed: completed, answers: answers)
}

private func point(_ id: String, at date: Date, value: Double, prompted: Bool = true) -> MoodPoint {
    MoodPoint(id: id, entryId: "e-\(id)", date: date, value: value, prompted: prompted)
}

// MARK: - defaultMoodQuestion

@Suite("Analytics.defaultMoodQuestion")
struct DefaultMoodQuestionTests {
    @Test("picks the lowest-position active mood question")
    func lowestPosition() {
        let survey = Survey(name: "Test", questions: [
            Question(id: "later", kind: .scale, label: "Energy", position: 3, scale: ScaleConfig()),
            Question(id: "text", kind: .text, label: "Notes", position: 0),
            Question(id: "first", kind: .scale, label: "Mood", position: 1, scale: ScaleConfig()),
        ])
        #expect(Analytics.defaultMoodQuestion(in: survey)?.id == "first")
    }

    @Test("skips archived scale questions")
    func skipsArchived() {
        let survey = Survey(name: "Test", questions: [
            Question(id: "old", kind: .scale, label: "Old", position: 0, isArchived: true, scale: ScaleConfig()),
            Question(id: "live", kind: .scale, label: "Mood", position: 5, scale: ScaleConfig()),
        ])
        #expect(Analytics.defaultMoodQuestion(in: survey)?.id == "live")
    }

    @Test("equal positions fall back to identifier order")
    func tieBreak() {
        let survey = Survey(name: "Test", questions: [
            Question(id: "z", kind: .scale, label: "Z", position: 0, scale: ScaleConfig()),
            Question(id: "a", kind: .scale, label: "A", position: 0, scale: ScaleConfig()),
        ])
        #expect(Analytics.defaultMoodQuestion(in: survey)?.id == "a")
    }

    @Test("includes spectrum questions and returns nil without an active mood question")
    func none() {
        let noScale = Survey(name: "Test", questions: [
            Question(id: "text", kind: .text, label: "Notes", position: 0),
            Question(id: "old", kind: .scale, label: "Old", position: 1, isArchived: true, scale: ScaleConfig()),
            Question(id: "spectrum", kind: .spectrum, label: "Mood", position: 2, spectrum: SpectrumConfig()),
        ])
        #expect(Analytics.defaultMoodQuestion(in: noScale)?.id == "spectrum")
        #expect(Analytics.defaultMoodQuestion(in: Survey(name: "Empty")) == nil)
    }
}

// MARK: - moodSeries

@Suite("Analytics.moodSeries")
struct MoodSeriesTests {
    @Test("one point per completed scale answer, ascending by date, prompted carried through")
    func basics() {
        let snap = snapshot(entries: [
            entry("e3", at: at(2026, 3, 3), prompted: false, mood: 6),
            entry("e1", at: at(2026, 3, 1), mood: 4),
            entry("e2", at: at(2026, 3, 2), mood: 5),
        ])
        let series = Analytics.moodSeries(questionId: scaleQ, snapshot: snap)
        #expect(series == [
            MoodPoint(id: "e1/\(scaleQ)", entryId: "e1", date: at(2026, 3, 1), value: 4, prompted: true),
            MoodPoint(id: "e2/\(scaleQ)", entryId: "e2", date: at(2026, 3, 2), value: 5, prompted: true),
            MoodPoint(id: "e3/\(scaleQ)", entryId: "e3", date: at(2026, 3, 3), value: 6, prompted: false),
        ])
    }

    @Test("excludes partial entries")
    func excludesPartial() {
        let snap = snapshot(entries: [
            entry("done", at: at(2026, 3, 1), mood: 4),
            entry("partial", at: at(2026, 3, 2), completed: false, mood: 7),
        ])
        #expect(Analytics.moodSeries(questionId: scaleQ, snapshot: snap).map(\.entryId) == ["done"])
    }

    @Test("ignores answers that are not scale values and entries without the question")
    func ignoresNonScale() {
        let snap = snapshot(entries: [
            entry("text", at: at(2026, 3, 1), answers: [(scaleQ, .text("five"), nil)]),
            entry("yesno", at: at(2026, 3, 2), answers: [(scaleQ, .yesNo(true), nil)]),
            entry("other", at: at(2026, 3, 3), answers: [(textQ, .text("hi"), nil)]),
            entry("none", at: at(2026, 3, 4), answers: []),
            entry("ok", at: at(2026, 3, 5), mood: 3),
        ])
        #expect(Analytics.moodSeries(questionId: scaleQ, snapshot: snap).map(\.entryId) == ["ok"])
    }

    @Test("only the requested question contributes")
    func otherQuestion() {
        let snap = snapshot(entries: [entry("e1", at: at(2026, 3, 1), mood: 4)])
        #expect(Analytics.moodSeries(questionId: textQ, snapshot: snap).isEmpty)
        #expect(Analytics.moodSeries(questionId: "missing", snapshot: snap).isEmpty)
    }

    @Test("the point date is the answer's answeredAt, not the entry's dates")
    func usesAnsweredAt() {
        var exportEntry = entry("e1", at: at(2026, 3, 1, 8), mood: 4)
        exportEntry.answers[0].answeredAt = at(2026, 3, 1, 8, 5)
        let series = Analytics.moodSeries(questionId: scaleQ, snapshot: snapshot(entries: [exportEntry]))
        #expect(series.map(\.date) == [at(2026, 3, 1, 8, 5)])
    }

    @Test("orders by answeredAt, not by when the entry started")
    func ordersByAnsweredAt() {
        var early = entry("startedEarly", at: at(2026, 3, 1, 8), mood: 4)   // started 08:00
        early.answers[0].answeredAt = at(2026, 3, 1, 9)                     // answered 09:00
        var late = entry("startedLate", at: at(2026, 3, 1, 8, 30), mood: 5) // started 08:30
        late.answers[0].answeredAt = at(2026, 3, 1, 8, 45)                  // answered 08:45
        let series = Analytics.moodSeries(questionId: scaleQ, snapshot: snapshot(entries: [early, late]))
        #expect(series.map(\.entryId) == ["startedLate", "startedEarly"])
    }

    @Test("prompted comes from the entry's promptId, not from whether the prompt row was joined")
    func promptedFromEntry() {
        var orphaned = entry("orphaned", at: at(2026, 3, 1), prompted: true, mood: 4)
        orphaned.prompt = nil
        var stray = entry("stray", at: at(2026, 3, 2), prompted: false, mood: 5)
        stray.prompt = prompt(id: "p-stray", status: .answered)
        let series = Analytics.moodSeries(questionId: scaleQ, snapshot: snapshot(entries: [orphaned, stray]))
        #expect(series.map(\.prompted) == [true, false])
    }

    @Test("a lowest-ID answer of the wrong shape hides a later scale answer to the same question")
    func mixedShapeDuplicates() {
        let snap = snapshot(entries: [
            entry("e1", at: at(2026, 3, 1), answers: [
                (scaleQ, .text("five"), "a-first"),
                (scaleQ, .scale(5), "b-second"),
            ]),
        ])
        #expect(Analytics.moodSeries(questionId: scaleQ, snapshot: snap).isEmpty)
    }

    @Test("duplicate answers to one question resolve to the first by answer ID")
    func duplicateAnswers() {
        let snap = snapshot(entries: [
            entry("e1", at: at(2026, 3, 1), answers: [
                (scaleQ, .scale(7), "b-second"),
                (scaleQ, .scale(2), "a-first"),
            ]),
        ])
        let series = Analytics.moodSeries(questionId: scaleQ, snapshot: snap)
        #expect(series.map(\.id) == ["a-first"])
        #expect(series.map(\.value) == [2])
    }

    @Test("same-instant points are ordered by answer ID")
    func sameInstant() {
        let snap = snapshot(entries: [
            entry("e1", at: at(2026, 3, 1), answers: [(scaleQ, .scale(1), "z")]),
            entry("e2", at: at(2026, 3, 1), answers: [(scaleQ, .scale(2), "a")]),
        ])
        #expect(Analytics.moodSeries(questionId: scaleQ, snapshot: snap).map(\.id) == ["a", "z"])
    }

    @Test("spectrum answers are converted to 0 through 100")
    func spectrum() {
        let snap = snapshot(entries: [
            entry("low", at: at(2026, 3, 1), answers: [(scaleQ, .spectrum(0), nil)]),
            entry("middle", at: at(2026, 3, 2), answers: [(scaleQ, .spectrum(0.425), nil)]),
            entry("high", at: at(2026, 3, 3), answers: [(scaleQ, .spectrum(1), nil)]),
        ])
        #expect(Analytics.moodSeries(questionId: scaleQ, snapshot: snap).map(\.value) == [0, 42.5, 100])
    }
}

// MARK: - moodAxis

@Suite("Analytics.moodAxis")
struct MoodAxisTests {
    @Test("scale uses its configured range and endpoint labels")
    func scale() throws {
        let question = Question(
            kind: .scale, label: "Mood", position: 0,
            scale: ScaleConfig(min: -2, max: 8, minLabel: "Low", maxLabel: "High"))
        let axis = try #require(Analytics.moodAxis(for: question))
        #expect(axis.domain == -2...8)
        #expect(axis.minLabel == "Low")
        #expect(axis.maxLabel == "High")
    }

    @Test("spectrum uses 0 through 100 and the outer zone labels")
    func spectrum() throws {
        let config = SpectrumConfig(zones: [
            .init(label: "Calm", color: .init(red: 0, green: 0, blue: 0)),
            .init(label: "Alert", color: .init(red: 1, green: 1, blue: 1)),
        ], breakpoints: [0.5])
        let axis = try #require(Analytics.moodAxis(
            for: Question(kind: .spectrum, label: "Energy", position: 0, spectrum: config)))
        #expect(axis.domain == 0...100)
        #expect(axis.minLabel == "Calm")
        #expect(axis.maxLabel == "Alert")
    }

    @Test("returns nil for non-mood questions and missing or invalid configurations")
    func invalid() {
        #expect(Analytics.moodAxis(for: Question(kind: .text, label: "Notes", position: 0)) == nil)
        #expect(Analytics.moodAxis(for: Question(kind: .scale, label: "Mood", position: 0)) == nil)
        let empty = SpectrumConfig(zones: [], breakpoints: [])
        #expect(Analytics.moodAxis(
            for: Question(kind: .spectrum, label: "Mood", position: 0, spectrum: empty)) == nil)
        let blankLabel = SpectrumConfig(zones: [
            .init(label: "Low", color: .init(red: 0, green: 0, blue: 0)),
            .init(label: " ", color: .init(red: 1, green: 1, blue: 1)),
        ], breakpoints: [0.5])
        #expect(Analytics.moodAxis(
            for: Question(kind: .spectrum, label: "Mood", position: 0, spectrum: blankLabel)) == nil)
    }
}

// MARK: - rollingMean

@Suite("Analytics.rollingMean")
struct RollingMeanTests {
    private let points = [
        point("a", at: at(2026, 3, 1), value: 1),
        point("b", at: at(2026, 3, 2), value: 2, prompted: false),
        point("c", at: at(2026, 3, 3), value: 3),
        point("d", at: at(2026, 3, 4), value: 4, prompted: false),
        point("e", at: at(2026, 3, 5), value: 5),
    ]

    @Test("window 3 over five points matches hand-computed values")
    func windowThree() {
        let smoothed = Analytics.rollingMean(points, window: 3)
        #expect(smoothed.map(\.value) == [1, 1.5, 2, 3, 4])
    }

    @Test("IDs, entry IDs, dates and prompted pass through unchanged")
    func passThrough() {
        let smoothed = Analytics.rollingMean(points, window: 3)
        #expect(smoothed.map(\.id) == points.map(\.id))
        #expect(smoothed.map(\.entryId) == points.map(\.entryId))
        #expect(smoothed.map(\.date) == points.map(\.date))
        #expect(smoothed.map(\.prompted) == points.map(\.prompted))
    }

    @Test("a window of one, zero or less is the identity")
    func identity() {
        #expect(Analytics.rollingMean(points, window: 1) == points)
        #expect(Analytics.rollingMean(points, window: 0) == points)
        #expect(Analytics.rollingMean(points, window: -3) == points)
    }

    @Test("a window wider than the input averages everything so far")
    func wideWindow() {
        let smoothed = Analytics.rollingMean(points, window: 100)
        #expect(smoothed.map(\.value) == [1, 1.5, 2, 2.5, 3])
    }

    @Test("empty input returns empty")
    func empty() {
        #expect(Analytics.rollingMean([], window: 7).isEmpty)
        #expect(Analytics.rollingMean([], window: 1).isEmpty)
    }
}

// MARK: - byHour

@Suite("Analytics.byHour")
struct ByHourTests {
    @Test("returns 24 buckets in order with digit ids and labels")
    func shape() {
        let buckets = Analytics.byHour([], calendar: toronto)
        #expect(buckets.count == 24)
        #expect(buckets.map(\.id) == (0..<24).map(String.init))
        #expect(buckets.map(\.label) == (0..<24).map(String.init))
        #expect(buckets.allSatisfy { $0.mean == nil && $0.count == 0 })
    }

    @Test("a point at 23:30 local lands in hour 23 even though its UTC day is the next one")
    func lateEvening() {
        let lateLocal = at(2026, 3, 2, 23, 30)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.component(.day, from: lateLocal) == 3)
        #expect(utc.component(.hour, from: lateLocal) == 4)

        let buckets = Analytics.byHour([point("a", at: lateLocal, value: 5)], calendar: toronto)
        #expect(buckets[23].count == 1)
        #expect(buckets[23].mean == 5)
        #expect(buckets[0].count == 0)
        #expect(buckets[4].count == 0)
    }

    @Test("means and counts accumulate per hour; empty hours have a nil mean")
    func accumulates() {
        let buckets = Analytics.byHour([
            point("a", at: at(2026, 3, 1, 9, 5), value: 2),
            point("b", at: at(2026, 3, 4, 9, 55), value: 5),
            point("c", at: at(2026, 3, 2, 0, 0), value: 7),
        ], calendar: toronto)
        #expect(buckets[9] == BucketStat(id: "9", label: "9", mean: 3.5, count: 2))
        #expect(buckets[0] == BucketStat(id: "0", label: "0", mean: 7, count: 1))
        #expect(buckets[10].mean == nil)
        #expect(buckets.map(\.count).reduce(0, +) == 3)
    }

    @Test("the hour follows the calendar's time zone")
    func timeZone() {
        var tokyo = toronto
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let noonToronto = at(2026, 3, 2, 12)  // 17:00 UTC, 02:00 next day in Tokyo
        let buckets = Analytics.byHour([point("a", at: noonToronto, value: 1)], calendar: tokyo)
        #expect(buckets[2].count == 1)
        #expect(buckets[12].count == 0)
    }
}

// MARK: - byWeekday

@Suite("Analytics.byWeekday")
struct ByWeekdayTests {
    @Test("returns 7 buckets starting from firstWeekday with the calendar's short symbols")
    func shape() {
        let buckets = Analytics.byWeekday([], calendar: toronto)
        #expect(buckets.map(\.id) == ["2", "3", "4", "5", "6", "7", "1"])
        let symbols = toronto.shortWeekdaySymbols
        #expect(buckets.map(\.label) == Array(symbols[1...]) + [symbols[0]])
        #expect(buckets.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(buckets.allSatisfy { $0.mean == nil && $0.count == 0 })
    }

    @Test("a Sunday point lands in the Sunday bucket, which is last for a Monday-first calendar")
    func sunday() {
        let sunday = at(2026, 3, 15)  // third Sunday of March, so weekdayOrdinal != weekday
        #expect(toronto.component(.weekday, from: sunday) == 1)
        #expect(toronto.component(.weekdayOrdinal, from: sunday) == 3)
        let buckets = Analytics.byWeekday([point("a", at: sunday, value: 6)], calendar: toronto)
        #expect(buckets.last == BucketStat(id: "1", label: "Sun", mean: 6, count: 1))
        #expect(buckets.dropLast().allSatisfy { $0.count == 0 })
    }

    @Test("a Sunday-first calendar puts Sunday first")
    func sundayFirst() {
        var sundayFirst = toronto
        sundayFirst.firstWeekday = 1
        let buckets = Analytics.byWeekday([point("a", at: at(2026, 3, 15), value: 6)], calendar: sundayFirst)
        #expect(buckets.map(\.id) == ["1", "2", "3", "4", "5", "6", "7"])
        #expect(buckets.map(\.label) == sundayFirst.shortWeekdaySymbols)
        #expect(buckets.first?.count == 1)
    }

    @Test("means accumulate across weeks and late-evening points use the local weekday")
    func accumulates() {
        let buckets = Analytics.byWeekday([
            point("a", at: at(2026, 3, 2, 9), value: 1),    // Monday
            point("b", at: at(2026, 3, 9, 23, 30), value: 4),  // Monday local, Tuesday UTC
            point("c", at: at(2026, 3, 4), value: 7),      // Wednesday
        ], calendar: toronto)
        #expect(buckets[0] == BucketStat(id: "2", label: "Mon", mean: 2.5, count: 2))
        #expect(buckets[1].count == 0)
        #expect(buckets[2] == BucketStat(id: "4", label: "Wed", mean: 7, count: 1))
    }

    @Test("the weekday follows the calendar's time zone")
    func timeZone() {
        var tokyo = toronto
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let saturdayNight = at(2026, 3, 14, 23)  // Saturday in Toronto, Sunday noon in Tokyo
        #expect(toronto.component(.weekday, from: saturdayNight) == 7)
        let buckets = Analytics.byWeekday([point("a", at: saturdayNight, value: 1)], calendar: tokyo)
        #expect(buckets.first { $0.id == "1" }?.count == 1)
        #expect(buckets.first { $0.id == "7" }?.count == 0)
    }
}

// MARK: - byOption

@Suite("Analytics.byOption")
struct ByOptionTests {
    private func stats(_ entries: [ExportEntry]) -> [BucketStat] {
        Analytics.byOption(moodQuestionId: scaleQ, choiceQuestionId: choiceQ, snapshot: snapshot(entries: entries))
    }

    @Test("an entry selecting two options counts toward both")
    func multiSelect() {
        let buckets = stats([
            entry("e1", at: at(2026, 3, 1), mood: 2, options: ["opt-a", "opt-b"]),
            entry("e2", at: at(2026, 3, 2), mood: 6, options: ["opt-b"]),
        ])
        #expect(buckets == [
            BucketStat(id: "opt-a", label: "Alpha", mean: 2, count: 1),
            BucketStat(id: "opt-b", label: "Bravo", mean: 4, count: 2),
        ])
    }

    @Test("unselected live options are present with count 0 and nil mean")
    func unselected() {
        let buckets = stats([entry("e1", at: at(2026, 3, 1), mood: 5, options: ["opt-b"])])
        #expect(buckets.map(\.id) == ["opt-a", "opt-b"])
        #expect(buckets[0] == BucketStat(id: "opt-a", label: "Alpha", mean: nil, count: 0))
    }

    @Test("an archived option is present with data and absent without")
    func archived() {
        let buckets = stats([entry("e1", at: at(2026, 3, 1), mood: 3, options: ["opt-c"])])
        #expect(buckets.map(\.id) == ["opt-a", "opt-b", "opt-c"])
        #expect(buckets[2] == BucketStat(id: "opt-c", label: "Charlie", mean: 3, count: 1))
        #expect(!buckets.contains { $0.id == "opt-d" })
    }

    @Test("an archived option with data keeps its position among live options")
    func archivedKeepsPosition() {
        let survey = Survey(id: "s1", name: "Test", createdAt: at(2026, 1, 1), questions: [
            Question(id: scaleQ, kind: .scale, label: "Mood", position: 0, scale: ScaleConfig()),
            Question(id: choiceQ, kind: .multiChoice, label: "Where", position: 1, options: [
                ChoiceOption(id: "live", label: "Live", position: 1),
                ChoiceOption(id: "retired", label: "Retired", position: 0, isArchived: true),
                ChoiceOption(id: "gone", label: "Gone", position: 2, isArchived: true),
            ]),
        ])
        let snap = snapshot(survey, entries: [entry("e1", at: at(2026, 3, 1), mood: 3, options: ["retired"])])
        let buckets = Analytics.byOption(moodQuestionId: scaleQ, choiceQuestionId: choiceQ, snapshot: snap)
        #expect(buckets.map(\.id) == ["retired", "live"])
    }

    @Test("duplicate answers to the choice or scale question resolve to the first by answer ID")
    func duplicateAnswers() {
        let buckets = stats([
            entry("e1", at: at(2026, 3, 1), answers: [
                (choiceQ, .multi(optionIds: ["opt-b"]), "z-choice-second"),
                (choiceQ, .multi(optionIds: ["opt-a"]), "a-choice-first"),
                (scaleQ, .scale(7), "z-scale-second"),
                (scaleQ, .scale(2), "a-scale-first"),
            ]),
        ])
        #expect(buckets == [
            BucketStat(id: "opt-a", label: "Alpha", mean: 2, count: 1),
            BucketStat(id: "opt-b", label: "Bravo", mean: nil, count: 0),
        ])
    }

    @Test("order follows option position with identifier as tiebreaker")
    func order() {
        let tied = Survey(id: "s1", name: "Tied", createdAt: at(2026, 1, 1), questions: [
            Question(id: scaleQ, kind: .scale, label: "Mood", position: 0, scale: ScaleConfig()),
            Question(id: choiceQ, kind: .singleChoice, label: "Where", position: 1, options: [
                ChoiceOption(id: "z", label: "Z", position: 1),
                ChoiceOption(id: "m", label: "M", position: 1),
                ChoiceOption(id: "a", label: "A", position: 2),
                ChoiceOption(id: "q", label: "Q", position: 0),
            ]),
        ])
        let snap = snapshot(tied, entries: [
            entry("e1", at: at(2026, 3, 1), answers: [(scaleQ, .scale(4), nil), (choiceQ, .single(optionId: "a"), nil)]),
        ])
        let buckets = Analytics.byOption(moodQuestionId: scaleQ, choiceQuestionId: choiceQ, snapshot: snap)
        #expect(buckets.map(\.id) == ["q", "m", "z", "a"])
        #expect(buckets[3] == BucketStat(id: "a", label: "A", mean: 4, count: 1))
    }

    @Test("partial entries, entries without a scale value and duplicate option IDs do not count")
    func exclusions() {
        let buckets = stats([
            entry("partial", at: at(2026, 3, 1), completed: false, mood: 7, options: ["opt-a"]),
            entry("noMood", at: at(2026, 3, 2), options: ["opt-a"]),
            entry("textMood", at: at(2026, 3, 3), answers: [
                (scaleQ, .text("seven"), nil), (choiceQ, .multi(optionIds: ["opt-a"]), nil),
            ]),
            entry("dupes", at: at(2026, 3, 4), mood: 1, options: ["opt-a", "opt-a"]),
        ])
        #expect(buckets[0] == BucketStat(id: "opt-a", label: "Alpha", mean: 1, count: 1))
    }

    @Test("two definition rows sharing an option ID produce one bucket, the first by (position, id)")
    func duplicateDefinitions() {
        let survey = Survey(id: "s1", name: "Test", createdAt: at(2026, 1, 1), questions: [
            Question(id: scaleQ, kind: .scale, label: "Mood", position: 0, scale: ScaleConfig()),
            Question(id: choiceQ, kind: .multiChoice, label: "Where", position: 1, options: [
                ChoiceOption(id: "twin", label: "Later", position: 1, isArchived: true),
                ChoiceOption(id: "twin", label: "Earlier", position: 0),
                ChoiceOption(id: "other", label: "Other", position: 2),
            ]),
        ])
        let snap = snapshot(survey, entries: [entry("e1", at: at(2026, 3, 1), mood: 4, options: ["twin"])])
        let buckets = Analytics.byOption(moodQuestionId: scaleQ, choiceQuestionId: choiceQ, snapshot: snap)
        #expect(buckets == [
            BucketStat(id: "twin", label: "Earlier", mean: 4, count: 1),
            BucketStat(id: "other", label: "Other", mean: nil, count: 0),
        ])
    }

    @Test("selected option IDs that the question does not define are ignored")
    func unknownOption() {
        let buckets = stats([entry("e1", at: at(2026, 3, 1), mood: 5, options: ["ghost"])])
        #expect(buckets.map(\.id) == ["opt-a", "opt-b"])
        #expect(buckets.allSatisfy { $0.count == 0 })
    }

    @Test("an unknown choice question yields no buckets")
    func unknownQuestion() {
        let snap = snapshot(entries: [entry("e1", at: at(2026, 3, 1), mood: 5, options: ["opt-a"])])
        #expect(Analytics.byOption(moodQuestionId: scaleQ, choiceQuestionId: "missing", snapshot: snap).isEmpty)
    }

    @Test("spectrum answers are converted to 0 through 100")
    func spectrum() {
        let buckets = stats([
            entry("e1", at: at(2026, 3, 1), answers: [
                (scaleQ, .spectrum(0.25), nil), (choiceQ, .multi(optionIds: ["opt-a"]), nil),
            ]),
            entry("e2", at: at(2026, 3, 2), answers: [
                (scaleQ, .spectrum(0.75), nil), (choiceQ, .multi(optionIds: ["opt-a"]), nil),
            ]),
        ])
        #expect(buckets.first { $0.id == "opt-a" } == BucketStat(id: "opt-a", label: "Alpha", mean: 50, count: 2))
    }
}

// MARK: - compliance

@Suite("Analytics.compliance")
struct ComplianceTests {
    @Test("counts a mixed list and rates answered over outcomes")
    func mixed() {
        let stats = Analytics.compliance(prompts: [
            prompt(id: "1", status: .answered),
            prompt(id: "2", status: .missed),
            prompt(id: "3", status: .answered),
            prompt(id: "4", status: .dismissed),
            prompt(id: "5", status: .pending),
            prompt(id: "6", status: .answered),
            prompt(id: "7", status: .pending),
            prompt(id: "8", status: .missed),
        ])
        #expect(stats == ComplianceStats(answered: 3, missed: 2, dismissed: 1, pending: 2, rate: 0.5))
    }

    @Test("rate is nil when only pending prompts exist")
    func onlyPending() {
        let stats = Analytics.compliance(prompts: [
            prompt(id: "1", status: .pending),
            prompt(id: "2", status: .pending),
        ])
        #expect(stats == ComplianceStats(answered: 0, missed: 0, dismissed: 0, pending: 2, rate: nil))
    }

    @Test("all missed gives a rate of zero, not nil")
    func allMissed() {
        let stats = Analytics.compliance(prompts: [prompt(id: "1", status: .missed)])
        #expect(stats == ComplianceStats(answered: 0, missed: 1, dismissed: 0, pending: 0, rate: 0))
    }

    @Test("no prompts gives zeros and a nil rate")
    func empty() {
        #expect(Analytics.compliance(prompts: []) == ComplianceStats(answered: 0, missed: 0, dismissed: 0, pending: 0, rate: nil))
    }
}

// MARK: - Empty snapshot

@Suite("Analytics with an empty snapshot")
struct EmptySnapshotTests {
    private let empty = ExportSnapshot(
        survey: Survey(name: "Empty"), entries: [],
        questionLabelHistory: [:], optionLabelHistory: [:], questionVersionLabels: [:]
    )

    @Test("every function returns empty or zeroed output")
    func everything() {
        #expect(Analytics.defaultMoodQuestion(in: empty.survey) == nil)
        let series = Analytics.moodSeries(questionId: scaleQ, snapshot: empty)
        #expect(series.isEmpty)
        #expect(Analytics.rollingMean(series, window: 7).isEmpty)
        let hours = Analytics.byHour(series, calendar: toronto)
        #expect(hours.count == 24 && hours.allSatisfy { $0.count == 0 && $0.mean == nil })
        let weekdays = Analytics.byWeekday(series, calendar: toronto)
        #expect(weekdays.count == 7 && weekdays.allSatisfy { $0.count == 0 && $0.mean == nil })
        #expect(Analytics.byOption(moodQuestionId: scaleQ, choiceQuestionId: choiceQ, snapshot: empty).isEmpty)
        #expect(Analytics.compliance(prompts: []).rate == nil)
    }

    @Test("a survey with questions but no entries yields empty series and zeroed option buckets")
    func noEntries() {
        let snap = snapshot(entries: [])
        #expect(Analytics.moodSeries(questionId: scaleQ, snapshot: snap).isEmpty)
        let buckets = Analytics.byOption(moodQuestionId: scaleQ, choiceQuestionId: choiceQ, snapshot: snap)
        #expect(buckets == [
            BucketStat(id: "opt-a", label: "Alpha", mean: nil, count: 0),
            BucketStat(id: "opt-b", label: "Bravo", mean: nil, count: 0),
        ])
    }
}
