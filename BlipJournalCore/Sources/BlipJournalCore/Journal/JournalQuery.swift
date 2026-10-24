import Foundation

/// Which entries to show by how they started.
public enum JournalSource: String, CaseIterable, Sendable, Hashable {
    case any
    case prompted
    case manual
}

/// Which entries to show by whether they were finished.
public enum JournalStatus: String, CaseIterable, Sendable, Hashable {
    case any
    case completed
    case draft
}

/// A condition on one answer of an entry. References IDs, never labels.
public enum JournalAnswerFilter: Sendable, Hashable {
    /// The single-choice answer is this option, or the multi-choice answer includes it.
    case option(questionId: String, optionId: String)
    /// The yes/no answer equals `value`.
    case yesNo(questionId: String, value: Bool)

    /// The question the condition reads.
    public var questionId: String {
        switch self {
        case .option(let questionId, _), .yesNo(let questionId, _): questionId
        }
    }

    /// Whether `value` satisfies the condition. A value of another kind never does.
    public func matches(_ value: AnswerValue) -> Bool {
        switch (self, value) {
        case (.option(_, let optionId), .single(let selected)):
            selected == optionId
        case (.option(_, let optionId), .multi(let selected)):
            selected.contains(optionId)
        case (.yesNo(_, let expected), .yesNo(let actual)):
            expected == actual
        default:
            false
        }
    }

    /// The default condition for `question`: its first active option, or "Yes".
    /// Nil for a kind that cannot be filtered on, or a choice question with no options.
    public static func defaultCondition(for question: Question) -> JournalAnswerFilter? {
        switch question.kind {
        case .singleChoice, .multiChoice:
            question.activeOptions.first.map { .option(questionId: question.id, optionId: $0.id) }
        case .yesNo:
            .yesNo(questionId: question.id, value: true)
        case .scale, .spectrum, .text:
            nil
        }
    }
}

/// What the Journal shows. The default value shows everything.
public struct JournalFilter: Sendable, Hashable {
    /// Nil means every survey. An answer condition needs a survey.
    public var surveyId: String?
    public var source: JournalSource
    public var status: JournalStatus
    /// Only meaningful with a `surveyId`; ``JournalQuery/normalized(filter:sort:surveys:)``
    /// drops it otherwise.
    public var answer: JournalAnswerFilter?

    public init(
        surveyId: String? = nil,
        source: JournalSource = .any,
        status: JournalStatus = .any,
        answer: JournalAnswerFilter? = nil
    ) {
        self.surveyId = surveyId
        self.source = source
        self.status = status
        self.answer = answer
    }

    /// Whether anything is narrowed.
    public var isActive: Bool {
        self != JournalFilter()
    }

    /// Whether `entry` passes every condition except the answer condition, which needs
    /// answers and is checked by ``JournalQuery/apply(_:filter:sort:answers:)``.
    public func matchesMetadata(_ entry: Entry) -> Bool {
        if let surveyId, entry.surveyId != surveyId { return false }
        switch source {
        case .any: break
        case .prompted: if !entry.isPrompted { return false }
        case .manual: if entry.isPrompted { return false }
        }
        switch status {
        case .any: break
        case .completed: if entry.completedAt == nil { return false }
        case .draft: if entry.completedAt != nil { return false }
        }
        return true
    }
}

/// The order the Journal lists entries in.
public enum JournalSort: Sendable, Hashable {
    case newestFirst
    case oldestFirst
    /// By a scale or spectrum answer. Entries without a numeric answer to the question
    /// come last, newest first.
    case answer(questionId: String, descending: Bool)

    /// The question the sort reads, if any.
    public var questionId: String? {
        switch self {
        case .newestFirst, .oldestFirst: nil
        case .answer(let questionId, _): questionId
        }
    }

    /// Whether the order follows `startedAt`, so day sections still make sense.
    public var isChronological: Bool {
        questionId == nil
    }
}

/// Filters and orders Journal entries. Pure: the caller loads the answers.
public enum JournalQuery {
    /// The questions whose answers ``apply(_:filter:sort:answers:)`` needs, in a stable
    /// order. Empty when metadata alone decides.
    public static func questionIds(filter: JournalFilter, sort: JournalSort) -> [String] {
        var ids: [String] = []
        if let id = filter.answer?.questionId { ids.append(id) }
        if let id = sort.questionId, !ids.contains(id) { ids.append(id) }
        return ids
    }

    /// Drops whatever no longer resolves against `surveys` (every survey, archived
    /// included): an unknown survey, an answer condition without a survey or naming a
    /// question or option the survey lacks, a sort question outside the filtered survey
    /// or of a non-numeric kind. A dropped answer sort falls back to newest first.
    public static func normalized(
        filter: JournalFilter, sort: JournalSort, surveys: [String: Survey]
    ) -> (filter: JournalFilter, sort: JournalSort) {
        var filter = filter
        var sort = sort
        let survey = filter.surveyId.flatMap { surveys[$0] }
        if survey == nil { filter.surveyId = nil }

        if let answer = filter.answer {
            let question = survey?.questions.first { $0.id == answer.questionId }
            let valid: Bool
            switch (answer, question?.kind) {
            case (.option(_, let optionId), .singleChoice?), (.option(_, let optionId), .multiChoice?):
                valid = question?.options.contains { $0.id == optionId } ?? false
            case (.yesNo, .yesNo?):
                valid = true
            default:
                valid = false
            }
            if !valid { filter.answer = nil }
        }

        if let questionId = sort.questionId {
            let kind = survey?.questions.first { $0.id == questionId }?.kind
            if !(kind.map(isSortable) ?? false) { sort = .newestFirst }
        }
        return (filter, sort)
    }

    // MARK: Choices to offer

    /// Whether an answer sort can read questions of `kind`: scale and spectrum.
    public static func isSortable(_ kind: QuestionKind) -> Bool {
        kind == .scale || kind == .spectrum
    }

    /// Whether an answer condition can read questions of `kind`: choice and yes/no.
    public static func isFilterable(_ kind: QuestionKind) -> Bool {
        switch kind {
        case .singleChoice, .multiChoice, .yesNo: true
        case .scale, .spectrum, .text: false
        }
    }

    /// The surveys to offer: `active` in the order given, then archived surveys that
    /// still have entries, plus the `keeping` survey if it is archived, by (name, ID).
    /// Keeping the current selection means a picker never loses what is filtering the list.
    public static func pickableSurveys(
        active: [Survey], all: [String: Survey], entries: [Entry], keeping surveyId: String?
    ) -> [Survey] {
        let withEntries = Set(entries.map(\.surveyId))
        let activeIds = Set(active.map(\.id))
        let archived = all.values
            .filter { !activeIds.contains($0.id) && (withEntries.contains($0.id) || $0.id == surveyId) }
            .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
        return active + archived
    }

    /// Active questions an answer condition can use, in display order, then the
    /// `keeping` question if it is archived but still filterable.
    public static func filterableQuestions(in survey: Survey, keeping questionId: String?) -> [Question] {
        offered(
            survey.activeQuestions.filter { JournalAnswerFilter.defaultCondition(for: $0) != nil },
            in: survey, keeping: questionId, where: isFilterable)
    }

    /// Active scale and spectrum questions in display order, then the `keeping`
    /// question if it is archived but still sortable.
    public static func sortableQuestions(in survey: Survey, keeping questionId: String?) -> [Question] {
        offered(
            survey.activeQuestions.filter { isSortable($0.kind) },
            in: survey, keeping: questionId, where: isSortable)
    }

    /// Active options in display order, then the `keeping` option if it is archived.
    public static func pickableOptions(of question: Question, keeping optionId: String?) -> [ChoiceOption] {
        var options = question.activeOptions
        if let optionId, !options.contains(where: { $0.id == optionId }),
           let kept = question.options.first(where: { $0.id == optionId }) {
            options.append(kept)
        }
        return options
    }

    private static func offered(
        _ questions: [Question], in survey: Survey, keeping questionId: String?,
        where allowed: (QuestionKind) -> Bool
    ) -> [Question] {
        var questions = questions
        if let questionId, !questions.contains(where: { $0.id == questionId }),
           let kept = survey.questions.first(where: { $0.id == questionId }), allowed(kept.kind) {
            questions.append(kept)
        }
        return questions
    }

    /// The entries that pass `filter`, in `sort` order.
    ///
    /// `answers` must hold every answer to ``questionIds(filter:sort:)`` for the
    /// entries; extra answers are ignored. Date ties break by ID so the order is
    /// stable; answer ties break newest first, then by ID.
    public static func apply(
        _ entries: [Entry], filter: JournalFilter, sort: JournalSort, answers: [Answer]
    ) -> [Entry] {
        let needed = Set(questionIds(filter: filter, sort: sort))
        var values: [AnswerKey: AnswerValue] = [:]
        for answer in answers where needed.contains(answer.questionId) {
            // One answer per question per entry is a store invariant; keep the first.
            let key = AnswerKey(entryId: answer.entryId, questionId: answer.questionId)
            if values[key] == nil { values[key] = answer.value }
        }

        let kept = entries.filter { entry in
            guard filter.matchesMetadata(entry) else { return false }
            guard let condition = filter.answer else { return true }
            let key = AnswerKey(entryId: entry.id, questionId: condition.questionId)
            return values[key].map(condition.matches) ?? false
        }

        let newestFirst: (Entry, Entry) -> Bool = {
            ($0.startedAt, $0.id) > ($1.startedAt, $1.id)
        }
        switch sort {
        case .newestFirst:
            return kept.sorted(by: newestFirst)
        case .oldestFirst:
            return kept.sorted { ($0.startedAt, $0.id) < ($1.startedAt, $1.id) }
        case .answer(let questionId, let descending):
            // Look each value up once, not on every comparison.
            let decorated = kept.map { entry in
                (entry: entry, number: values[AnswerKey(entryId: entry.id, questionId: questionId)].flatMap(numericValue))
            }
            return decorated.sorted { lhs, rhs in
                switch (lhs.number, rhs.number) {
                case let (left?, right?) where left != right:
                    return descending ? left > right : left < right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return newestFirst(lhs.entry, rhs.entry)
                }
            }.map(\.entry)
        }
    }

    /// A scale value, or a spectrum position in `0...1`. Nil for anything else or a
    /// non-finite spectrum value.
    static func numericValue(_ value: AnswerValue) -> Double? {
        switch value {
        case .scale(let value): Double(value)
        case .spectrum(let value): value.isFinite ? value : nil
        case .single, .multi, .yesNo, .text: nil
        }
    }

    private struct AnswerKey: Hashable {
        let entryId: String
        let questionId: String
    }
}
