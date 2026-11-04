/// Question fields are saved explicitly; option edits are persisted independently.
public struct QuestionEditDraft: Sendable {
    private var questionId: String?
    public var label = ""
    public var isRequired = false
    public var scale = ScaleConfig()
    public var spectrum = SpectrumConfig()
    public var allowsCustomOptions = false

    public init() {}

    public mutating func load(_ question: Question) {
        guard questionId != question.id else { return }
        questionId = question.id
        label = question.label
        isRequired = question.isRequired
        scale = question.scale ?? ScaleConfig()
        spectrum = question.spectrum ?? SpectrumConfig()
        allowsCustomOptions = question.allowsCustomOptions
    }

    /// Merge editable fields into the latest question, retaining its current options.
    public func applying(to question: Question) -> Question {
        var result = question
        result.label = label
        result.isRequired = isRequired
        result.scale = question.kind == .scale ? scale : nil
        result.spectrum = question.kind == .spectrum ? spectrum : nil
        result.allowsCustomOptions = question.kind.usesOptions && allowsCustomOptions
        return result
    }
}
