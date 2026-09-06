import Foundation

/// Turns an ``ExportSnapshot`` into CSV text.
///
/// Two shapes: ``wide(_:calendar:)`` is one row per entry with a column per question,
/// for spreadsheets; ``long(_:calendar:)`` is one row per answer (per selected option
/// for choice questions) with both the label at the time of the answer and the current
/// label, for analysis. Both are pure functions: no file I/O, no store, no UI. The app
/// writes the returned string to a file and hands it to the share sheet.
///
/// See `Export/DESIGN.md` for the column lists and formatting rules.
public enum CSVExporter {
    /// Fixed columns of the wide format, before the per-question columns.
    static let wideFixedColumns = [
        "entry_id", "survey", "prompted", "prompt_scheduled_at", "started_at",
        "completed_at", "latency_seconds",
    ]

    /// Every column of the long format.
    static let longColumns = [
        "entry_id", "prompted", "prompt_scheduled_at", "started_at", "completed_at",
        "answered_at",
        "question_id", "question_kind", "question_label_at_time", "question_label_current",
        "option_id", "option_label_at_time", "option_label_current",
        "numeric_value", "bool_value", "text_value",
    ]

    // MARK: Wide

    /// One row per entry: fixed entry columns, then one column per question in
    /// `(position, id)` order, archived questions included. Cells hold current labels.
    ///
    /// Timestamps are written in the offset of `calendar.timeZone`.
    public static func wide(_ snapshot: ExportSnapshot, calendar: Calendar) -> String {
        let context = Context(snapshot: snapshot, calendar: calendar)
        let questions = context.questions
        var output = CSV.row(wideFixedColumns + wideQuestionHeaders(questions))
        for exportEntry in snapshot.entries {
            var fields = [
                exportEntry.entry.id,
                snapshot.survey.name,
            ]
            fields += context.promptFields(exportEntry)
            fields.append(latencySeconds(exportEntry))
            for question in questions {
                let answer = context.answers(to: question.id, in: exportEntry).first
                fields.append(answer.map { context.wideCell($0, question: question) } ?? "")
            }
            output += CSV.row(fields)
        }
        return output
    }

    /// Current labels, with ` [` + first 8 characters of the ID + `]` appended to every
    /// question whose label another question shares, so headers stay unique.
    static func wideQuestionHeaders(_ questions: [Question]) -> [String] {
        var counts: [String: Int] = [:]
        for question in questions {
            counts[question.label, default: 0] += 1
        }
        return questions.map { question in
            if counts[question.label, default: 0] > 1 {
                return question.label + " [" + question.id.prefix(8) + "]"
            }
            return question.label
        }
    }

    /// Whole seconds from the prompt's scheduled time to completion, rounded toward
    /// zero. Empty for manual or incomplete entries.
    static func latencySeconds(_ exportEntry: ExportEntry) -> String {
        guard let prompt = prompt(of: exportEntry), let completedAt = exportEntry.entry.completedAt else {
            return ""
        }
        let seconds = completedAt.timeIntervalSince(prompt.scheduledAt).rounded(.towardZero)
        // `Int(exactly:)` rather than `Int(_:)` so a non-finite interval cannot trap.
        return Int(exactly: seconds).map(String.init) ?? ""
    }

    /// The prompt behind an entry, but only when the entry says it was prompted.
    /// `prompted` follows `entry.promptId`; the prompt columns must agree with it.
    static func prompt(of exportEntry: ExportEntry) -> Prompt? {
        exportEntry.entry.promptId == nil ? nil : exportEntry.prompt
    }

    // MARK: Long

    /// One row per answer, or per selected option for choice answers. An empty
    /// multi-choice answer is one row with empty option columns.
    ///
    /// Rows are ordered by entry, then question `(position, id)`, then selected option
    /// `(position, id)`. Answers whose question is not in the survey come after the
    /// known questions of their entry, with empty label columns. An entry with no
    /// answers produces no rows.
    public static func long(_ snapshot: ExportSnapshot, calendar: Calendar) -> String {
        let context = Context(snapshot: snapshot, calendar: calendar)
        var output = CSV.row(longColumns)
        for exportEntry in snapshot.entries {
            let entryFields = [exportEntry.entry.id] + context.promptFields(exportEntry)
            for question in context.questions {
                for answer in context.answers(to: question.id, in: exportEntry) {
                    for row in context.longRows(answer, question: question) {
                        output += CSV.row(entryFields + row)
                    }
                }
            }
            let orphans = exportEntry.answers
                .filter { context.questionsById[$0.questionId] == nil }
                .sorted { ($0.questionId, $0.answeredAt, $0.id) < ($1.questionId, $1.answeredAt, $1.id) }
            for answer in orphans {
                for row in context.longRows(answer, question: nil) {
                    output += CSV.row(entryFields + row)
                }
            }
        }
        return output
    }

    // MARK: Shared

    /// Per-call state: the formatter, the ordered questions, and the label lookups.
    struct Context {
        let snapshot: ExportSnapshot
        let formatter: ISO8601DateFormatter
        /// `survey.questions` sorted by `(position, id)`, archived included. Should two
        /// entries share an ID, only the first in that order is kept (input order breaks
        /// a full tie; the sort is stable).
        let questions: [Question]
        /// Current questions keyed by ID.
        let questionsById: [String: Question]
        /// Each question's options sorted by `(position, id)`, keyed by question ID.
        let orderedOptions: [String: [ChoiceOption]]
        /// Current options keyed by option ID.
        let optionsById: [String: ChoiceOption]

        init(snapshot: ExportSnapshot, calendar: Calendar) {
            self.snapshot = snapshot
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = calendar.timeZone
            self.formatter = formatter
            var seenQuestions = Set<String>()
            let sortedQuestions = snapshot.survey.questions
                .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
                .filter { seenQuestions.insert($0.id).inserted }
            let sortedOptions = sortedQuestions.map { question in
                var seenOptions = Set<String>()
                let options = question.options
                    .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
                    .filter { seenOptions.insert($0.id).inserted }
                return (question.id, options)
            }
            questions = sortedQuestions
            questionsById = Dictionary(uniqueKeysWithValues: sortedQuestions.map { ($0.id, $0) })
            orderedOptions = Dictionary(uniqueKeysWithValues: sortedOptions)
            // Built from the sorted arrays, not a dictionary's values, so a duplicate
            // option ID resolves to the same label on every run.
            optionsById = Dictionary(
                sortedOptions.flatMap(\.1).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        func timestamp(_ date: Date?) -> String {
            date.map(formatter.string(from:)) ?? ""
        }

        /// `prompted`, `prompt_scheduled_at`, `started_at`, `completed_at`.
        func promptFields(_ exportEntry: ExportEntry) -> [String] {
            [
                yesNo(exportEntry.entry.promptId != nil),
                timestamp(prompt(of: exportEntry)?.scheduledAt),
                timestamp(exportEntry.entry.startedAt),
                timestamp(exportEntry.entry.completedAt),
            ]
        }

        /// The entry's answers to `questionId`, oldest first, ID as the tiebreaker.
        /// Normally zero or one; `ExportEntry.answers` promises no order, so sorting
        /// keeps the output stable if storage ever hands back more.
        func answers(to questionId: String, in exportEntry: ExportEntry) -> [Answer] {
            exportEntry.answers
                .filter { $0.questionId == questionId }
                .sorted { ($0.answeredAt, $0.id) < ($1.answeredAt, $1.id) }
        }

        // MARK: Labels

        /// The question's wording when the answer was given: the version row's label if
        /// the version ID is known, else the label history replayed at `answeredAt`,
        /// else the current label.
        func questionLabelAtTime(_ answer: Answer, current: Question) -> String {
            if let label = snapshot.questionVersionLabels[answer.questionVersionId] {
                return label
            }
            if let label = snapshot.questionLabelHistory[answer.questionId]?.label(at: answer.answeredAt) {
                return label
            }
            return current.label
        }

        /// The option's current label, or its ID if the survey no longer has it.
        func optionLabelCurrent(_ optionId: String) -> String {
            optionsById[optionId]?.label ?? optionId
        }

        /// The option's wording when the answer was given: the label history replayed
        /// at `answeredAt`, else the current label (or the ID if unknown).
        func optionLabelAtTime(_ optionId: String, answeredAt: Date) -> String {
            snapshot.optionLabelHistory[optionId]?.label(at: answeredAt) ?? optionLabelCurrent(optionId)
        }

        /// `optionIds` in the question's `(position, id)` order, deduplicated. IDs the
        /// question does not have follow in the order given.
        func orderedSelection(_ optionIds: [String], questionId: String) -> [String] {
            let selected = Set(optionIds)
            let known = (orderedOptions[questionId] ?? [])
                .map(\.id)
                .filter { selected.contains($0) }
            let knownSet = Set(known)
            var unknown: [String] = []
            for id in optionIds where !knownSet.contains(id) && !unknown.contains(id) {
                unknown.append(id)
            }
            return known + unknown
        }

        // MARK: Cells

        /// The wide-format cell for one answer.
        func wideCell(_ answer: Answer, question: Question) -> String {
            switch answer.value {
            case .scale(let value):
                return String(value)
            case .single(let optionId):
                return optionLabelCurrent(optionId)
            case .multi(let optionIds):
                return orderedSelection(optionIds, questionId: question.id)
                    .map(optionLabelCurrent)
                    .joined(separator: "; ")
            case .yesNo(let value):
                return yesNo(value)
            case .text(let text):
                return text
            }
        }

        /// The long-format rows for one answer, from `answered_at` onwards. `question`
        /// is nil when the survey has no question with the answer's ID; both question
        /// label columns are then empty and the kind comes from the value. Option
        /// columns resolve as usual, since option IDs are looked up survey-wide.
        func longRows(_ answer: Answer, question: Question?) -> [[String]] {
            let head = [
                timestamp(answer.answeredAt),
                answer.questionId,
                (question?.kind ?? answer.value.kind).rawValue,
                question.map { questionLabelAtTime(answer, current: $0) } ?? "",
                question?.label ?? "",
            ]
            func optionRow(_ optionId: String?) -> [String] {
                guard let optionId else { return head + ["", "", "", "", "", ""] }
                return head + [
                    optionId,
                    optionLabelAtTime(optionId, answeredAt: answer.answeredAt),
                    optionLabelCurrent(optionId),
                    "", "", "",
                ]
            }
            switch answer.value {
            case .scale(let value):
                return [head + ["", "", "", String(value), "", ""]]
            case .single(let optionId):
                return [optionRow(optionId)]
            case .multi(let optionIds):
                let ordered = orderedSelection(optionIds, questionId: answer.questionId)
                return ordered.isEmpty ? [optionRow(nil)] : ordered.map { optionRow($0) }
            case .yesNo(let value):
                return [head + ["", "", "", "", yesNo(value), ""]]
            case .text(let text):
                return [head + ["", "", "", "", "", text]]
            }
        }
    }

    static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}
