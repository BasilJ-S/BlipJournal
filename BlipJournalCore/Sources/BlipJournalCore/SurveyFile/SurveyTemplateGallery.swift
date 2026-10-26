import Foundation

/// The premade surveys bundled with the app, offered when creating a survey and once
/// during onboarding.
///
/// Each template is an ordinary survey file in `Templates/`, read through
/// ``SurveyFile/decode(contentsOf:)`` like any file a person opens, so the gallery and
/// shared files cannot drift apart. The file holds the survey; this list only adds what
/// the format has no field for: the order and a one-line purpose.
public enum SurveyTemplateGallery {
    /// One bundled template.
    public struct Template: Identifiable, Sendable, Equatable {
        /// The file name without its `.blipsurvey` extension.
        public let id: String
        /// One line on what the survey helps you notice.
        public let purpose: String

        /// Where the bundled file is.
        public var url: URL { SurveyTemplateGallery.url(for: id) }
    }

    static let fileExtension = "blipsurvey"

    /// The bundled file for a template id. A missing file still gives a URL, which then
    /// fails to read and is reported like any unreadable survey file.
    static func url(for id: String) -> URL {
        Bundle.module.url(forResource: id, withExtension: fileExtension, subdirectory: "Templates")
            ?? Bundle.module.bundleURL.appendingPathComponent("Templates/\(id).\(fileExtension)")
    }

    /// The template ``SurveyTemplate/makeDefault(now:)`` reads: the survey a fresh install
    /// already has.
    public static let defaultSurveyTemplateId = "mood-and-feelings"

    /// Every bundled template, in gallery order.
    public static let templates: [Template] = [
        Template(id: "mood-and-feelings", purpose: "How you feel through the day, and what is going on at the time."),
        Template(id: "focus-and-energy", purpose: "When you feel sharp or flat, and what you are doing then."),
        Template(id: "social-time", purpose: "Who you spend your time with, and how connected you feel."),
        Template(id: "mind-wandering", purpose: "How often your mind drifts from what you are doing, and where it goes."),
        Template(id: "phone-use", purpose: "What you pick up your phone for, and whether that time feels well spent."),
    ]
}
