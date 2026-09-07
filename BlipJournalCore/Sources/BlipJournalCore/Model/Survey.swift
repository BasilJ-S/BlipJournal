import Foundation

/// One selectable answer of a ``QuestionKind/singleChoice`` or
/// ``QuestionKind/multiChoice`` question.
///
/// Options are definitions: storage never updates or deletes one. Renaming or
/// reordering inserts a new version row, and retiring an option sets ``isArchived``
/// on a new version so answers that already reference it stay readable.
public struct ChoiceOption: Identifiable, Sendable, Equatable, Hashable, Codable {
    /// Stable identity, shared by every version of this option.
    public var id: String
    /// The current label. Answers never store this text, only ``id``.
    public var label: String
    /// Sort order within the question. Lower comes first.
    public var position: Int
    /// Whether the option is retired: hidden from the runner, kept for old answers.
    public var isArchived: Bool

    /// Creates an option. A fresh identifier is generated unless one is supplied.
    public init(
        id: String = Identifier.make(),
        label: String,
        position: Int,
        isArchived: Bool = false
    ) {
        self.id = id
        self.label = label
        self.position = position
        self.isArchived = isArchived
    }
}

/// One question in a survey, in its current version.
///
/// A `Question` is a flattened view of the newest version row plus the current
/// versions of its options, including archived ones. Which fields apply depends on
/// ``kind``: ``scale`` is non-nil only for scale questions, and ``options`` and
/// ``allowsCustomOptions`` are only meaningful when ``QuestionKind/usesOptions``.
public struct Question: Identifiable, Sendable, Equatable, Hashable, Codable {
    /// Stable identity, shared by every version of this question.
    public var id: String
    /// The kind of answer accepted. Fixed for the life of the question, because
    /// changing it would orphan existing answers.
    public var kind: QuestionKind
    /// The current wording. Answers reference ``id``, never this text.
    public var label: String
    /// Sort order within the survey. Lower comes first.
    public var position: Int
    /// Whether an entry cannot be completed while this question is unanswered.
    public var isRequired: Bool
    /// Whether the question is retired: hidden from the runner, kept for old answers.
    public var isArchived: Bool
    /// Bounds and endpoint labels. Non-nil only when ``kind`` is ``QuestionKind/scale``.
    public var scale: ScaleConfig?
    /// Whether the runner offers an "add option" chip while answering.
    /// Only meaningful when ``kind`` uses options.
    public var allowsCustomOptions: Bool
    /// Every option, archived included, in no guaranteed order.
    /// Empty unless ``kind`` uses options. See ``activeOptions`` for display order.
    public var options: [ChoiceOption]

    /// Creates a question. A fresh identifier is generated unless one is supplied.
    public init(
        id: String = Identifier.make(),
        kind: QuestionKind,
        label: String,
        position: Int,
        isRequired: Bool = false,
        isArchived: Bool = false,
        scale: ScaleConfig? = nil,
        allowsCustomOptions: Bool = false,
        options: [ChoiceOption] = []
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.position = position
        self.isRequired = isRequired
        self.isArchived = isArchived
        self.scale = scale
        self.allowsCustomOptions = allowsCustomOptions
        self.options = options
    }

    /// The options to show while answering: not archived, sorted by ``position``.
    ///
    /// Identifier is the tiebreaker so equal positions still yield a stable order.
    public var activeOptions: [ChoiceOption] {
        options
            .filter { !$0.isArchived }
            .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }
}

/// A survey definition in its current version: the questionnaire plus its schedule.
///
/// Like ``Question``, this is the flattened newest-version view. Archived questions
/// are present so historical answers can still be labelled; ``activeQuestions`` is
/// what the runner shows.
public struct Survey: Identifiable, Sendable, Equatable, Hashable, Codable {
    /// Stable identity, shared by every version of this survey.
    public var id: String
    /// The current name.
    public var name: String
    /// When the survey was first created. Never changes across versions.
    public var createdAt: Date
    /// Whether the survey is retired: no prompts are scheduled, entries are kept.
    public var isArchived: Bool
    /// This survey's own prompt schedule. Surveys do not share one.
    public var sampling: SamplingConfig
    /// What a prompt notification for this survey shows before it is opened.
    public var notificationPreview: NotificationPreview
    /// Up to two questions whose answers summarize an entry in the Journal, in display order.
    public var journalSummaryQuestionIds: [String]
    /// Every question, archived included, in no guaranteed order.
    /// See ``activeQuestions`` for display order.
    public var questions: [Question]

    /// Creates a survey. A fresh identifier is generated unless one is supplied.
    public init(
        id: String = Identifier.make(),
        name: String,
        createdAt: Date = Date(),
        isArchived: Bool = false,
        sampling: SamplingConfig = .default,
        notificationPreview: NotificationPreview = .default,
        journalSummaryQuestionIds: [String] = [],
        questions: [Question] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isArchived = isArchived
        self.sampling = sampling
        self.notificationPreview = notificationPreview
        self.journalSummaryQuestionIds = Array(
            journalSummaryQuestionIds.reduce(into: [String]()) { ids, id in
                if !ids.contains(id) { ids.append(id) }
            }.prefix(2))
        self.questions = questions
    }

    /// The questions to ask: not archived, sorted by ``Question/position``.
    ///
    /// Identifier is the tiebreaker so equal positions still yield a stable order.
    public var activeQuestions: [Question] {
        questions
            .filter { !$0.isArchived }
            .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
    }

    /// Active summary questions in the order chosen for Journal rows.
    public var journalSummaryQuestions: [Question] {
        journalSummaryQuestionIds.compactMap { id in
            questions.first { $0.id == id && !$0.isArchived }
        }
    }
}
