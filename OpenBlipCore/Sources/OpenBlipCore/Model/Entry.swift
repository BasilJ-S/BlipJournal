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
    /// The `kind` discriminator written to JSON.
    ///
    /// These are the case names, not ``QuestionKind`` raw values, so the JSON names
    /// the shape of the payload rather than the question it happens to answer.
    private enum Discriminator: String, Codable {
        case scale, single, multi, yesNo, text
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, optionId, optionIds
    }

    /// Writes a flat object: the `kind` discriminator plus this case's payload key.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .scale(let value):
            try container.encode(Discriminator.scale, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .single(let optionId):
            try container.encode(Discriminator.single, forKey: .kind)
            try container.encode(optionId, forKey: .optionId)
        case .multi(let optionIds):
            try container.encode(Discriminator.multi, forKey: .kind)
            try container.encode(optionIds, forKey: .optionIds)
        case .yesNo(let value):
            try container.encode(Discriminator.yesNo, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .text(let value):
            try container.encode(Discriminator.text, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }

    /// Reads the `kind` discriminator, then the payload key that kind requires.
    ///
    /// Throws when the discriminator is unknown or the payload does not match it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Discriminator.self, forKey: .kind)
        switch kind {
        case .scale:
            self = .scale(try container.decode(Int.self, forKey: .value))
        case .single:
            self = .single(optionId: try container.decode(String.self, forKey: .optionId))
        case .multi:
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
/// Every answer pins the exact definition it was given against, so an export can show
/// either the wording at the time or the wording today.
public struct Answer: Identifiable, Sendable, Equatable, Hashable, Codable {
    /// Stable identity.
    public var id: String
    /// The entry this answer belongs to.
    public var entryId: String
    /// The question answered, stable across renames.
    public var questionId: String
    /// The identifier of the question version row that was current when the answer was
    /// given. Storage assigns it; the model only carries it.
    public var questionVersionId: String
    /// The answer itself.
    public var value: AnswerValue

    /// Creates an answer. A fresh identifier is generated unless one is supplied.
    public init(
        id: String = Identifier.make(),
        entryId: String,
        questionId: String,
        questionVersionId: String,
        value: AnswerValue
    ) {
        self.id = id
        self.entryId = entryId
        self.questionId = questionId
        self.questionVersionId = questionVersionId
        self.value = value
    }
}
