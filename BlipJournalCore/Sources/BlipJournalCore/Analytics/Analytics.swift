import Foundation

/// Pure functions that turn an `ExportSnapshot` and a list of prompts into chart-ready
/// series and summary numbers.
///
/// Nothing here formats a date, picks a colour, or reads the clock. The Insights
/// screen draws what these return and does no arithmetic of its own.
public enum Analytics {
    /// The first active scale or spectrum question by `(position, id)`, or nil when the survey has
    /// none. What Insights charts by default.
    public static func defaultMoodQuestion(in survey: Survey) -> Question? {
        survey.activeQuestions.first { $0.kind == .scale || $0.kind == .spectrum }
    }

    /// One point per completed entry that answered `questionId` with a mood value,
    /// ascending by date. Partial entries are excluded.
    ///
    /// Two points with the same date are ordered by answer identifier so the series is
    /// stable across runs.
    public static func moodSeries(questionId: String, snapshot: ExportSnapshot) -> [MoodPoint] {
        snapshot.entries
            .filter(isCompleted)
            .compactMap { exportEntry -> MoodPoint? in
                guard let answer = firstAnswer(to: questionId, in: exportEntry),
                      let value = moodValue(answer.value)
                else { return nil }
                return MoodPoint(
                    id: answer.id,
                    entryId: exportEntry.entry.id,
                    date: answer.answeredAt,
                    value: value,
                    prompted: exportEntry.entry.isPrompted
                )
            }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    /// Numeric domain and endpoint labels for a scale or spectrum mood question.
    public static func moodAxis(
        for question: Question
    ) -> (domain: ClosedRange<Double>, minLabel: String, maxLabel: String)? {
        switch question.kind {
        case .scale:
            guard let scale = question.scale else { return nil }
            return (Double(scale.min)...Double(scale.max), scale.minLabel, scale.maxLabel)
        case .spectrum:
            guard let spectrum = question.spectrum, spectrum.isValid,
                  let first = spectrum.zones.first,
                  let last = spectrum.zones.last
            else { return nil }
            return (0...100, first.label, last.label)
        case .singleChoice, .multiChoice, .yesNo, .text:
            return nil
        }
    }

    /// Trailing mean over the previous `window` points including the current one.
    ///
    /// The first `window - 1` points average what is available so far. The result has
    /// the same length and order as the input; `prompted`, IDs and dates are carried
    /// through unchanged. A `window` of one or less returns the input unchanged.
    public static func rollingMean(_ points: [MoodPoint], window: Int) -> [MoodPoint] {
        guard window > 1 else { return points }
        var result = points
        for index in points.indices {
            let start = max(points.startIndex, index - (window - 1))
            let slice = points[start...index]
            let sum = slice.reduce(0.0) { $0 + $1.value }
            result[index].value = sum / Double(slice.count)
        }
        return result
    }

    /// Exactly 24 buckets, id and label `"0"`...`"23"`, ordered by hour, using the
    /// hour of each point's `date` in `calendar`.
    public static func byHour(_ points: [MoodPoint], calendar: Calendar) -> [BucketStat] {
        var accumulators = [Accumulator](repeating: Accumulator(), count: 24)
        for point in points {
            let hour = calendar.component(.hour, from: point.date)
            guard accumulators.indices.contains(hour) else { continue }
            accumulators[hour].add(point.value)
        }
        return accumulators.enumerated().map { hour, accumulator in
            BucketStat(id: String(hour), label: String(hour), mean: accumulator.mean, count: accumulator.count)
        }
    }

    /// Exactly 7 buckets ordered from `calendar.firstWeekday`, id the weekday number
    /// (1 through 7, as `Calendar` numbers them) as a string, label the matching entry
    /// of `calendar.shortWeekdaySymbols`.
    public static func byWeekday(_ points: [MoodPoint], calendar: Calendar) -> [BucketStat] {
        var accumulators = [Int: Accumulator]()
        for point in points {
            let weekday = calendar.component(.weekday, from: point.date)
            accumulators[weekday, default: Accumulator()].add(point.value)
        }
        let symbols = calendar.shortWeekdaySymbols
        // `firstWeekday` is 1-based; normalise defensively in case a caller set it
        // outside 1...7.
        let firstOffset = ((calendar.firstWeekday - 1) % 7 + 7) % 7
        return (0..<7).map { step in
            let weekday = (firstOffset + step) % 7 + 1
            let accumulator = accumulators[weekday] ?? Accumulator()
            let label = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : String(weekday)
            return BucketStat(id: String(weekday), label: label, mean: accumulator.mean, count: accumulator.count)
        }
    }

    /// One bucket per option of `choiceQuestionId`, ordered by `(position, id)`,
    /// archived options included only when their count is greater than zero.
    ///
    /// The mean is over the mood value of `moodQuestionId` in every completed entry
    /// whose answer to the choice question selected that option. An entry that selected
    /// several options counts toward each of them. An entry with no mood value
    /// contributes to no bucket, so `count` is always the number of values behind
    /// `mean`. Returns empty when the survey has no question with `choiceQuestionId`.
    public static func byOption(
        moodQuestionId: String,
        choiceQuestionId: String,
        snapshot: ExportSnapshot
    ) -> [BucketStat] {
        guard let choiceQuestion = snapshot.survey.questions.first(where: { $0.id == choiceQuestionId })
        else { return [] }

        var accumulators = [String: Accumulator]()
        for exportEntry in snapshot.entries where isCompleted(exportEntry) {
            guard let answer = firstAnswer(to: moodQuestionId, in: exportEntry),
                  let value = moodValue(answer.value)
            else { continue }
            for optionId in selectedOptionIds(for: choiceQuestionId, in: exportEntry) {
                accumulators[optionId, default: Accumulator()].add(value)
            }
        }

        var seen = Set<String>()
        return choiceQuestion.options
            .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
            .compactMap { option in
                // Definitions are one row per option, but guard anyway: `BucketStat`
                // is `Identifiable`, and a chart cannot draw two buckets with one ID.
                guard seen.insert(option.id).inserted else { return nil }
                let accumulator = accumulators[option.id] ?? Accumulator()
                if option.isArchived && accumulator.count == 0 { return nil }
                return BucketStat(id: option.id, label: option.label, mean: accumulator.mean, count: accumulator.count)
            }
    }

    /// Counts by status over the given prompts.
    public static func compliance(prompts: [Prompt]) -> ComplianceStats {
        var answered = 0, missed = 0, dismissed = 0, pending = 0
        for prompt in prompts {
            switch prompt.status {
            case .answered: answered += 1
            case .missed: missed += 1
            case .dismissed: dismissed += 1
            case .pending: pending += 1
            }
        }
        let denominator = answered + missed + dismissed
        return ComplianceStats(
            answered: answered,
            missed: missed,
            dismissed: dismissed,
            pending: pending,
            rate: denominator == 0 ? nil : Double(answered) / Double(denominator)
        )
    }

    // MARK: - Helpers

    /// A running sum and count; `mean` is nil until something has been added.
    private struct Accumulator {
        var sum = 0.0
        var count = 0

        var mean: Double? { count == 0 ? nil : sum / Double(count) }

        mutating func add(_ value: Double) {
            sum += value
            count += 1
        }
    }

    /// The completed-entry rule: everything but `compliance` ignores partial entries.
    private static func isCompleted(_ exportEntry: ExportEntry) -> Bool {
        exportEntry.entry.completedAt != nil
    }

    private static func moodValue(_ value: AnswerValue) -> Double? {
        switch value {
        case .scale(let value): Double(value)
        case .spectrum(let value): value * 100
        case .single, .multi, .yesNo, .text: nil
        }
    }

    /// The entry's answer to `questionId`, whatever its shape. There should be at most
    /// one; if there are several, the lowest answer identifier wins so the choice is
    /// deterministic. Callers check the value's shape themselves.
    private static func firstAnswer(to questionId: String, in exportEntry: ExportEntry) -> Answer? {
        exportEntry.answers
            .filter { $0.questionId == questionId }
            .min { $0.id < $1.id }
    }

    /// The option identifiers the entry's answer to `questionId` selected, each at
    /// most once, in the order given. Empty when there is no answer or its value is not
    /// a choice.
    private static func selectedOptionIds(for questionId: String, in exportEntry: ExportEntry) -> [String] {
        guard let answer = firstAnswer(to: questionId, in: exportEntry) else { return [] }
        switch answer.value {
        case .single(let optionId):
            return [optionId]
        case .multi(let optionIds):
            var seen = Set<String>()
            return optionIds.filter { seen.insert($0).inserted }
        case .scale, .spectrum, .yesNo, .text:
            return []
        }
    }
}


extension Analytics {
    /// Distributions use the same completed-entry and duplicate-answer rules as the
    /// series. Multi-choice entries contribute once to each selected, defined option.
    public static func optionDistributions(
        moodQuestionId: String, choiceQuestionId: String, snapshot: ExportSnapshot
    ) -> [AnswerDistribution] {
        guard let question = snapshot.survey.questions.first(where: { $0.id == choiceQuestionId }),
              question.kind == .singleChoice || question.kind == .multiChoice else { return [] }
        let pairs = choicePoints(moodQuestionId: moodQuestionId, choiceQuestionId: choiceQuestionId, snapshot: snapshot)
        var seen = Set<String>()
        return question.options.sorted { ($0.position, $0.id) < ($1.position, $1.id) }.compactMap { option in
            guard seen.insert(option.id).inserted else { return nil }
            let points = pairs.filter { $0.options.contains(option.id) }.map(\.point)
            guard !option.isArchived || !points.isEmpty else { return nil }
            return AnswerDistribution(id: option.id, label: option.label, points: points)
        }
    }

    /// Only explicit choice answers enter either group. Empty multi-choice is an
    /// explicit "none selected"; missing, malformed and unknown-option answers are excluded.
    public static func optionComparison(
        moodQuestionId: String, choiceQuestionId: String, optionId: String, snapshot: ExportSnapshot
    ) -> [AnswerDistribution] {
        guard let question = snapshot.survey.questions.first(where: { $0.id == choiceQuestionId }),
              let option = question.options.first(where: { $0.id == optionId }) else { return [] }
        let pairs = choicePoints(moodQuestionId: moodQuestionId, choiceQuestionId: choiceQuestionId, snapshot: snapshot)
        return [
            AnswerDistribution(id: "selected", label: "Selected “\(option.label)”",
                points: pairs.filter { $0.options.contains(optionId) }.map(\.point)),
            AnswerDistribution(id: "not-selected", label: "Didn’t select “\(option.label)”",
                points: pairs.filter { !$0.options.contains(optionId) }.map(\.point))
        ]
    }

    private static func choicePoints(
        moodQuestionId: String, choiceQuestionId: String, snapshot: ExportSnapshot
    ) -> [(point: MoodPoint, options: Set<String>)] {
        guard let question = snapshot.survey.questions.first(where: { $0.id == choiceQuestionId }),
              question.kind == .singleChoice || question.kind == .multiChoice else { return [] }
        let defined = Set(question.options.map(\.id))
        let points = Dictionary(moodSeries(questionId: moodQuestionId, snapshot: snapshot)
            .map { ($0.entryId, $0) }, uniquingKeysWith: { first, _ in first })
        return snapshot.entries.compactMap { entry in
            guard let point = points[entry.id], point.value.isFinite,
                  let answer = firstAnswer(to: choiceQuestionId, in: entry) else { return nil }
            let options: Set<String>
            switch answer.value {
            case .single(let id): options = [id]
            case .multi(let ids): options = Set(ids)
            default: return nil
            }
            guard options.isSubset(of: defined) else { return nil }
            return (point, options)
        }
    }
}
