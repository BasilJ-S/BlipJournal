import Foundation

/// Everything the exporters and the analytics functions need about one survey, loaded
/// once by `Store.exportSnapshot(surveyId:)` and then handed around as a value.
///
/// This type is the seam between Storage (which builds it) and Export and Analytics
/// (which consume it). It is defined here, ahead of both, so the three tasks can be
/// built in parallel against one shape. Changing it is a cross-task change: update the
/// builder, every consumer, and each component's `DESIGN.md` in the same PR.
public struct ExportSnapshot: Sendable, Equatable, Codable {
    /// The survey in its current view, archived questions and options included.
    public var survey: Survey
    /// Every entry of the survey with its prompt and answers, ascending by
    /// `entry.startedAt`. Partial entries (no `completedAt`) are included; consumers
    /// decide whether to keep them.
    public var entries: [ExportEntry]
    /// Rename history per question ID, in version order (oldest first). Every question
    /// in `survey.questions` has a key, even if its history has one element.
    public var questionLabelHistory: [String: [LabelVersion]]
    /// Rename history per option ID, in version order (oldest first). Every option of
    /// every question has a key.
    public var optionLabelHistory: [String: [LabelVersion]]
    /// The label of each question version row, keyed by version ID. This is what
    /// `Answer.questionVersionId` resolves against, and it is exact where the history
    /// lookup by `answeredAt` is a replay.
    public var questionVersionLabels: [String: String]

    public init(
        survey: Survey,
        entries: [ExportEntry],
        questionLabelHistory: [String: [LabelVersion]],
        optionLabelHistory: [String: [LabelVersion]],
        questionVersionLabels: [String: String]
    ) {
        self.survey = survey
        self.entries = entries
        self.questionLabelHistory = questionLabelHistory
        self.optionLabelHistory = optionLabelHistory
        self.questionVersionLabels = questionVersionLabels
    }
}

/// One entry joined with the prompt it answered and every answer it holds.
public struct ExportEntry: Identifiable, Sendable, Equatable, Codable {
    /// The entry row.
    public var entry: Entry
    /// The prompt behind it, or nil for a manual entry.
    public var prompt: Prompt?
    /// The entry's answers, in no guaranteed order. Consumers look them up by
    /// `questionId`.
    public var answers: [Answer]

    public var id: String { entry.id }

    public init(entry: Entry, prompt: Prompt? = nil, answers: [Answer]) {
        self.entry = entry
        self.prompt = prompt
        self.answers = answers
    }
}
