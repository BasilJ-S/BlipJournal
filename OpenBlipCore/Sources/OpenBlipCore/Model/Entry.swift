import Foundation

/// One filled-in (or partly filled-in) survey response.
///
/// An entry is created the moment the runner opens and is saved on every change, so a
/// row can exist with no ``completedAt`` and only some of its answers.
public struct Entry: Identifiable, Sendable, Equatable, Hashable, Codable {
    /// Stable identity.
    public var id: String
    /// The survey that was answered.
    public var surveyId: String
    /// The prompt this entry responds to. Nil means a manual, unprompted entry.
    public var promptId: String?
    /// When the runner opened.
    public var startedAt: Date
    /// When the user finished. Nil while the entry is a partial autosave.
    public var completedAt: Date?

    /// Creates an entry. A fresh identifier is generated unless one is supplied.
    public init(
        id: String = Identifier.make(),
        surveyId: String,
        promptId: String? = nil,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.surveyId = surveyId
        self.promptId = promptId
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    /// Whether the entry answers a prompt rather than being started by hand.
    ///
    /// Exports surface this so self-selected entries can be told apart from sampled
    /// ones.
    public var isPrompted: Bool {
        promptId != nil
    }
}

/// The answer to one question, in the shape that question's kind demands.
///
/// Choice cases carry option identifiers, never labels, so a later rename does not
/// rewrite history.
public enum AnswerValue: Sendable, Equatable, Hashable {
    /// A rating on the question's ``ScaleConfig`` range.
    case scale(Int)
    /// The single option selected.
    case single(optionId: String)
    /// Every option selected, possibly none.
    case multi(optionIds: [String])
    /// A boolean.
    case yesNo(Bool)
    /// Free text, possibly empty.
    case text(String)

    /// The question kind this value can answer.
    public var kind: QuestionKind {
        switch self {
        case .scale: .scale
        case .single: .singleChoice
        case .multi: .multiChoice
        case .yesNo: .yesNo
        case .text: .text
        }
    }

    /// Whether the user left the question effectively blank.
    ///
    /// Only an empty selection and an empty string count. A whitespace-only string is
    /// not trimmed here; the runner decides what to do with it before saving.
    public var isEmpty: Bool {
        switch self {
        case .multi(let optionIds): optionIds.isEmpty
        case .text(let text): text.isEmpty
        case .scale, .single, .yesNo: false
        }
    }
}

extension AnswerValue: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, value, optionId, optionIds
    }

    /// Writes a flat object: the ``kind`` discriminator plus this case's payload key.
    ///
    /// The discriminator is a ``QuestionKind`` raw value, the same vocabulary a
    /// question uses, so a backup file names question kinds exactly one way.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .scale(let value):
            try container.encode(value, forKey: .value)
        case .single(let optionId):
            try container.encode(optionId, forKey: .optionId)
        case .multi(let optionIds):
            try container.encode(optionIds, forKey: .optionIds)
        case .yesNo(let value):
            try container.encode(value, forKey: .value)
        case .text(let value):
            try container.encode(value, forKey: .value)
        }
    }

    /// Reads the ``QuestionKind`` discriminator, then the payload key that kind requires.
    ///
    /// Throws when the discriminator is not a known kind or the payload does not match it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(QuestionKind.self, forKey: .kind) {
        case .scale:
            self = .scale(try container.decode(Int.self, forKey: .value))
        case .singleChoice:
            self = .single(optionId: try container.decode(String.self, forKey: .optionId))
        case .multiChoice:
            self = .multi(optionIds: try container.decode([String].self, forKey: .optionIds))
        case .yesNo:
            self = .yesNo(try container.decode(Bool.self, forKey: .value))
        case .text:
            self = .text(try container.decode(String.self, forKey: .value))
        }
    }
}

/// One answer inside an ``Entry``.
///
/// Between ``questionVersionId`` and ``answeredAt``, an answer carries enough to
/// reconstruct exactly what the person saw when they gave it: the question's wording and
/// configuration, the options that were on offer, and which of them they picked. See
/// "Recoverability" in `Model/DESIGN.md` for the full recipe.
public struct Answer: Identifiable, Sendable, Equatable, Hashable, Codable {
    /// Stable identity.
    public var id: String
    /// The entry this answer belongs to.
    public var entryId: String
    /// The question answered, stable across renames.
    public var questionId: String
    /// The identifier of the question version row that was current when the answer was
    /// given. Storage assigns it; the model only carries it.
    ///
    /// This pins the question's wording, position, scale bounds and required flag
    /// exactly, with no time arithmetic involved.
    public var questionVersionId: String
    /// When this particular answer was given.
    ///
    /// Per answer rather than per entry, because an entry is autosaved as the person
    /// works through it and can stay open for minutes: a custom option added at question
    /// four must not appear in the reconstructed choices for question two. This is the
    /// timestamp every "what did it look like then" lookup keys on, including
    /// ``LabelVersion`` history for options, which carry no version identifier of their
    /// own.
    public var answeredAt: Date
    /// The answer itself.
    public var value: AnswerValue

    /// Creates an answer. A fresh identifier is generated unless one is supplied.
    public init(
        id: String = Identifier.make(),
        entryId: String,
        questionId: String,
        questionVersionId: String,
        answeredAt: Date = Date(),
        value: AnswerValue
    ) {
        self.id = id
        self.entryId = entryId
        self.questionId = questionId
        self.questionVersionId = questionVersionId
        self.answeredAt = answeredAt
        self.value = value
    }
}
