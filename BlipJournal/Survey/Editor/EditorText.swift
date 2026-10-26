import BlipJournalCore
import Foundation

/// Wording the editor and the survey file preview share, so a kind or a time reads the
/// same everywhere.
enum EditorText {
    /// `HH:MM` for minutes after midnight, or "midnight" for the end of the day.
    static func clock(_ minutes: Int) -> String {
        minutes == 1440 ? "midnight" : String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "3 prompts a day, 09:00 to 23:00".
    static func window(_ sampling: SamplingConfig) -> String {
        "\(sampling.promptsPerDay) prompts a day, \(clock(sampling.windowStartMinutes)) to \(clock(sampling.windowEndMinutes))"
    }
}

extension QuestionKind {
    /// The kind's name with what answering it involves, as the question type picker shows it.
    var editorDescription: String {
        switch self {
        case .scale: "Scale — choose a number"
        case .spectrum: "Spectrum — slide between feelings"
        case .singleChoice: "Single choice — choose one"
        case .multiChoice: "Multiple choice — choose any"
        case .yesNo: "Yes or no"
        case .text: "Quick note — short text"
        }
    }
}
