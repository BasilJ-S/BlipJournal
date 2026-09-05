import Foundation

/// What became of a prompt.
///
/// The raw values are persisted and exported, so they are part of the on-disk and
/// CSV contract.
public enum PromptStatus: String, CaseIterable, Sendable, Equatable, Hashable, Codable {
    /// Scheduled and still answerable.
    case pending
    /// The user completed an entry for it.
    case answered
    /// It expired unanswered. Recorded rather than deleted so compliance is visible.
    case missed
    /// The user explicitly declined it.
    case dismissed
}

/// One scheduled ping: an invitation to answer a survey at a particular moment.
///
/// Prompts are generated ahead of time by the planner, persisted, and mirrored into
/// the notification centre. Unlike definitions they are mutable, because their
/// ``status`` changes as the user responds or the prompt expires.
public struct Prompt: Identifiable, Sendable, Equatable, Hashable, Codable {
    /// Stable identity. Also the notification request identifier.
    public var id: String
    /// The survey to present.
    public var surveyId: String
    /// The local calendar day this prompt was generated for, as `yyyy-MM-dd`.
    ///
    /// Stored as a string rather than derived from ``scheduledAt`` so the planner can
    /// ask "does this survey already have prompts for this day?" without redoing time
    /// zone arithmetic, and so the answer does not drift if the device changes zone.
    public var day: String
    /// When the prompt fires.
    public var scheduledAt: Date
    /// When the prompt stops being answerable, `scheduledAt` plus the survey's expiry.
    public var expiresAt: Date
    /// Current disposition.
    public var status: PromptStatus
    /// When the status last moved off ``PromptStatus/pending``. Nil while pending.
    public var respondedAt: Date?

    /// Creates a prompt. A fresh identifier is generated unless one is supplied.
    public init(
        id: String = Identifier.make(),
        surveyId: String,
        day: String,
        scheduledAt: Date,
        expiresAt: Date,
        status: PromptStatus = .pending,
        respondedAt: Date? = nil
    ) {
        self.id = id
        self.surveyId = surveyId
        self.day = day
        self.scheduledAt = scheduledAt
        self.expiresAt = expiresAt
        self.status = status
        self.respondedAt = respondedAt
    }

    /// Whether this prompt is still pending but its window has closed.
    ///
    /// Expiry is inclusive: a prompt is expired at exactly ``expiresAt``. Prompts that
    /// already have an outcome are never expired, whatever the time.
    public func isExpired(at now: Date) -> Bool {
        status == .pending && expiresAt <= now
    }
}
