import Foundation

/// What a survey's prompt notification shows before it is opened.
///
/// Defaults to `.private` so a locked screen tells a stranger nothing about what is
/// being asked. Nothing here ever includes an answer; ``surveyName`` is the only case
/// that exposes anything about the survey at all, and only its current name.
public enum NotificationPreview: Sendable, Equatable, Hashable, Codable {
    /// A generic title and body. Reveals nothing about the survey.
    case `private`
    /// The survey's current name as the title, with the same generic body.
    case surveyName
    /// A person-authored body, shown under the generic title.
    case custom(message: String)

    /// What every new survey starts with, and what an absent preview row resolves to.
    public static let `default` = NotificationPreview.private

    /// Whether this preview is safe to save: only ``custom`` can be invalid, and only by
    /// being blank once trimmed.
    public var isValid: Bool {
        switch self {
        case .private, .surveyName: true
        case .custom(let message): !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The notification title and body this preview produces for a survey named
    /// `surveyName`. Pure and total: every case produces content, valid or not.
    public func content(surveyName: String) -> NotificationContent {
        switch self {
        case .private:
            NotificationContent(title: "Blip Journal", body: "Time for a check-in.")
        case .surveyName:
            NotificationContent(title: surveyName, body: "Time for a check-in.")
        case .custom(let message):
            NotificationContent(title: "Blip Journal", body: message)
        }
    }
}

/// The title and body a notification shows, computed from a ``NotificationPreview`` and
/// nothing else. Never carries an answer or anything from inside the survey.
public struct NotificationContent: Sendable, Equatable, Hashable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}
