import Foundation
import Observation
import BlipJournalCore

/// Drives the Insights screen: which survey and range are selected, and every
/// chart-ready value derived from them. All arithmetic lives in `Analytics`; this
/// model only loads data, applies the selected range, and picks questions.
@MainActor @Observable
final class InsightsModel {
    /// The five range choices `InsightsView` offers. `custom` reveals start/end pickers.
    enum RangeSelection: String, CaseIterable, Identifiable, Sendable {
        case sevenDays, thirtyDays, ninetyDays, all, custom

        var id: Self { self }

        var label: String {
            switch self {
            case .sevenDays: "7 days"
            case .thirtyDays: "30 days"
            case .ninetyDays: "90 days"
            case .all: "All"
            case .custom: "Custom"
            }
        }
    }

    let store: Store
    let calendar: Calendar

    /// Every survey, active first then archived, each group in store order.
    private(set) var surveys: [Survey] = []
    /// First active survey, else first archived, else nil. Settable so the survey
    /// picker can change it; call `load` afterwards to reload for the new survey.
    var selectedSurveyId: String?
    private(set) var snapshot: ExportSnapshot?
    /// Every prompt of the selected survey, all statuses, unfiltered by range.
    private(set) var prompts: [Prompt] = []

    /// The scale question every scale-derived chart reads. User-changeable among the
    /// selected survey's active scale questions; defaults to `Analytics.defaultScaleQuestion`.
    var scaleQuestion: Question?
    /// The choice question the "By option" chart reads. User-changeable among the
    /// selected survey's active choice questions; defaults to the first by position.
    var choiceQuestion: Question?

    var range: RangeSelection = .thirtyDays {
        didSet {
            guard range == .custom, oldValue != .custom, !hasInitializedCustomRange else { return }
            let today = calendar.startOfDay(for: now)
            let start: Date
            switch oldValue {
            case .sevenDays: start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            case .thirtyDays: start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            case .ninetyDays: start = calendar.date(byAdding: .day, value: -89, to: today) ?? today
            case .all, .custom: start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            }
            // Suppressed during this programmatic batch set: `customStart` alone can
            // look invalid against the not-yet-updated `customEnd` (or vice versa), so
            // per-property validation only runs once both are in their final state.
            isAdjustingCustomRange = true
            customStart = start
            customEnd = today
            isAdjustingCustomRange = false
            hasInitializedCustomRange = true
        }
    }

    /// Local calendar date, inclusive. Rejects a future date or one after `customEnd`
    /// by reverting to the previous value.
    var customStart: Date {
        didSet {
            guard !isAdjustingCustomRange else { return }
            guard isValidCustomRange else {
                isAdjustingCustomRange = true
                customStart = oldValue
                isAdjustingCustomRange = false
                return
            }
            hasInitializedCustomRange = true
        }
    }

    /// Local calendar date, inclusive. Rejects a future date or one before `customStart`
    /// by reverting to the previous value.
    var customEnd: Date {
        didSet {
            guard !isAdjustingCustomRange else { return }
            guard isValidCustomRange else {
                isAdjustingCustomRange = true
                customEnd = oldValue
                isAdjustingCustomRange = false
                return
            }
            hasInitializedCustomRange = true
        }
    }

    @ObservationIgnored private var now: Date
    @ObservationIgnored private var hasInitializedCustomRange = false
    @ObservationIgnored private var isAdjustingCustomRange = false

    init(store: Store, calendar: Calendar = .autoupdatingCurrent) {
        self.store = store
        self.calendar = calendar
        let now = Date()
        self.now = now
        let today = calendar.startOfDay(for: now)
        self.customStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        self.customEnd = today
    }

    /// Reloads surveys, the selected survey's snapshot and prompts, and resolves the
    /// scale and choice question selections. Call on appear and whenever
    /// `selectedSurveyId` changes.
    func load(now: Date = Date()) throws {
        self.now = now

        let ordered = Self.ordered(try store.surveys(includeArchived: true))
        surveys = ordered
        if let selectedSurveyId, !ordered.contains(where: { $0.id == selectedSurveyId }) {
            self.selectedSurveyId = nil
        }
        if selectedSurveyId == nil {
            selectedSurveyId = Self.defaultSelection(ordered)
        }

        guard let selectedSurveyId else {
            snapshot = nil
            prompts = []
            scaleQuestion = nil
            choiceQuestion = nil
            return
        }

        let snapshot = try store.exportSnapshot(surveyId: selectedSurveyId)
        self.snapshot = snapshot
        prompts = try store.prompts(status: nil).filter { $0.surveyId == selectedSurveyId }

        scaleQuestion = Self.resolve(scaleQuestion, among: scaleQuestions)
            ?? Analytics.defaultScaleQuestion(in: snapshot.survey)
        choiceQuestion = Self.resolve(choiceQuestion, among: choiceQuestions)
            ?? choiceQuestions.first
    }

    // MARK: - Question choices

    /// Active scale questions of the selected survey, in position order.
    var scaleQuestions: [Question] {
        (snapshot?.survey.activeQuestions ?? [])
            .filter { $0.kind == .scale }
            .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }

    /// Active choice questions (single or multi) of the selected survey, in position order.
    var choiceQuestions: [Question] {
        (snapshot?.survey.activeQuestions ?? [])
            .filter { $0.kind == .singleChoice || $0.kind == .multiChoice }
            .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }

    // MARK: - Chart data

    /// `Analytics.scaleSeries` for `scaleQuestion`, filtered to the selected range.
    var series: [MoodPoint] {
        guard let snapshot, let scaleQuestion else { return [] }
        let bounds = computeBounds()
        return Analytics.scaleSeries(questionId: scaleQuestion.id, snapshot: snapshot)
            .filter { contains($0.date, in: bounds) }
    }

    /// A trailing 7-point mean of `series`.
    var rolling: [MoodPoint] {
        Analytics.rollingMean(series, window: 7)
    }

    var byHour: [BucketStat] {
        Analytics.byHour(series, calendar: calendar)
    }

    var byWeekday: [BucketStat] {
        Analytics.byWeekday(series, calendar: calendar)
    }

    /// `Analytics.byOption`, restricted to the same entries `series` includes so every
    /// chart shares one set of bounds.
    var byOption: [BucketStat] {
        guard let snapshot, let scaleQuestion, let choiceQuestion else { return [] }
        let includedEntryIds = Set(series.map(\.entryId))
        let boundedSnapshot = ExportSnapshot(
            survey: snapshot.survey,
            entries: snapshot.entries.filter { includedEntryIds.contains($0.entry.id) },
            questionLabelHistory: snapshot.questionLabelHistory,
            optionLabelHistory: snapshot.optionLabelHistory,
            questionVersionLabels: snapshot.questionVersionLabels)
        return Analytics.byOption(
            scaleQuestionId: scaleQuestion.id, choiceQuestionId: choiceQuestion.id, snapshot: boundedSnapshot)
    }

    /// `Analytics.compliance` over `prompts` restricted to the selected range by
    /// `scheduledAt`. Future scheduled prompts are always excluded.
    var compliance: ComplianceStats {
        let bounds = computeBounds()
        return Analytics.compliance(prompts: prompts.filter { contains($0.scheduledAt, in: bounds) })
    }

    // MARK: - Accessibility summaries

    /// "{question label}. Average {mean} over {count} entries." or a no-data summary.
    var seriesAccessibilitySummary: String {
        let label = scaleQuestion?.label ?? "Scale"
        guard !series.isEmpty else { return "\(label). No entries in this range." }
        let mean = series.map(\.value).reduce(0, +) / Double(series.count)
        let entryWord = series.count == 1 ? "entry" : "entries"
        return "\(label). Average \(Self.formatted(mean)) over \(series.count) \(entryWord)."
    }

    var byHourAccessibilitySummary: String {
        Self.bucketSummary(byHour, label: scaleQuestion?.label ?? "Scale", axis: "hour of day")
    }

    var byWeekdayAccessibilitySummary: String {
        Self.bucketSummary(byWeekday, label: scaleQuestion?.label ?? "Scale", axis: "day of week")
    }

    var byOptionAccessibilitySummary: String {
        // "selections", not "entries": an entry that chose several options is counted
        // once per bucket by `Analytics.byOption`, so summing bucket counts here would
        // overcount any multi-choice question.
        Self.bucketSummary(
            byOption, label: scaleQuestion?.label ?? "Scale", axis: choiceQuestion?.label ?? "option",
            unit: "selections")
    }

    var complianceAccessibilitySummary: String {
        let stats = compliance
        let total = stats.answered + stats.missed + stats.dismissed + stats.pending
        guard total > 0 else { return "Response rate. No prompts yet." }
        guard let rate = stats.rate else { return "Response rate. No responses yet, \(stats.pending) pending." }
        return "Response rate \(Self.formatted(rate * 100))%. \(stats.answered) answered, \(stats.missed) missed, "
            + "\(stats.dismissed) dismissed, \(stats.pending) pending."
    }

    private static func bucketSummary(_ buckets: [BucketStat], label: String, axis: String, unit: String = "entries") -> String {
        let withData = buckets.filter { $0.count > 0 }
        guard !withData.isEmpty else { return "\(label) by \(axis). No entries in this range." }
        let totalCount = withData.reduce(0) { $0 + $1.count }
        return "\(label) by \(axis). \(withData.count) of \(buckets.count) groups have data, "
            + "\(totalCount) \(unit) total."
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    // MARK: - Range bounds

    private struct Bounds {
        let start: Date
        let exclusiveEnd: Date
        let now: Date
    }

    private func computeBounds() -> Bounds {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        switch range {
        case .all:
            return Bounds(start: .distantPast, exclusiveEnd: tomorrow, now: now)
        case .sevenDays:
            return Bounds(start: calendar.date(byAdding: .day, value: -6, to: today) ?? today, exclusiveEnd: tomorrow, now: now)
        case .thirtyDays:
            return Bounds(start: calendar.date(byAdding: .day, value: -29, to: today) ?? today, exclusiveEnd: tomorrow, now: now)
        case .ninetyDays:
            return Bounds(start: calendar.date(byAdding: .day, value: -89, to: today) ?? today, exclusiveEnd: tomorrow, now: now)
        case .custom:
            let start = calendar.startOfDay(for: customStart)
            let endDay = calendar.startOfDay(for: customEnd)
            let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return Bounds(start: start, exclusiveEnd: exclusiveEnd, now: now)
        }
    }

    private func contains(_ date: Date, in bounds: Bounds) -> Bool {
        date >= bounds.start && date < bounds.exclusiveEnd && date <= bounds.now
    }

    /// Whether `customStart...customEnd` is a valid, non-future range under `calendar`.
    private var isValidCustomRange: Bool {
        let today = calendar.startOfDay(for: now)
        let start = calendar.startOfDay(for: customStart)
        let end = calendar.startOfDay(for: customEnd)
        return start <= today && end <= today && start <= end
    }

    // MARK: - Selection helpers

    /// Active surveys first, then archived, each group in the order the store returned.
    private static func ordered(_ surveys: [Survey]) -> [Survey] {
        surveys.filter { !$0.isArchived } + surveys.filter(\.isArchived)
    }

    /// First active survey, else first archived, else nil. `surveys` is already ordered
    /// active-first, so this is just its first element.
    private static func defaultSelection(_ surveys: [Survey]) -> String? {
        surveys.first?.id
    }

    /// `current` if it still names one of `candidates`, refreshed to that candidate's
    /// current version; nil (falling to the default) otherwise.
    private static func resolve(_ current: Question?, among candidates: [Question]) -> Question? {
        guard let current else { return nil }
        return candidates.first { $0.id == current.id }
    }
}
