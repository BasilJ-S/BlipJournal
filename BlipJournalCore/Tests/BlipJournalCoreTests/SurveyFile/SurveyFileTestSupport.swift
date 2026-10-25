import Foundation
import Testing
import BlipJournalCore

/// Shared helpers for the survey file tests.
enum SurveyFileTestSupport {
    static func decode(_ json: String) throws -> SurveyFileContents {
        try SurveyFile.decode(Data(json.utf8)).get()
    }

    /// The issues a file is rejected with; empty when it imports.
    static func issues(_ json: String) -> [SurveyFileError.Issue] {
        guard case .failure(let error) = SurveyFile.decode(Data(json.utf8)) else { return [] }
        return error.issues
    }

    /// A file around one question, so a test only spells out what it is about.
    static func file(question: String) -> String {
        #"{"formatVersion": 1, "name": "Survey", "questions": ["# + question + "]}"#
    }

    /// A file with one text question and the given extra top-level fields.
    static func file(extra: String) -> String {
        #"{"formatVersion": 1, "name": "Survey", "questions": [{"id": "note", "kind": "text", "label": "Note"}], "#
            + extra + "}"
    }

    /// Questions with identity removed: identifiers become their display index and
    /// positions are renumbered from 0, archived options dropped. Two definitions that
    /// ask the same things in the same order canonicalise to the same value.
    static func canonical(_ questions: [Question]) -> [Question] {
        questions.enumerated().map { index, question in
            var copy = question
            copy.id = "q\(index)"
            copy.position = index
            copy.options = question.activeOptions.enumerated().map { optionIndex, option in
                ChoiceOption(id: "q\(index)o\(optionIndex)", label: option.label, position: optionIndex)
            }
            return copy
        }
    }

    /// The current definition of a survey as a survey file carries it: name, active
    /// questions in order, schedule apart from whether it is on, and the Journal summary
    /// as indexes into the active questions.
    struct Definition: Equatable {
        var name: String
        var questions: [Question]
        var sampling: SamplingConfig
        var summary: [Int]

        init(_ survey: Survey) {
            let active = survey.activeQuestions
            name = survey.name
            questions = SurveyFileTestSupport.canonical(active)
            var enabled = survey.sampling
            enabled.isEnabled = true
            sampling = enabled
            summary = survey.journalSummaryQuestions.compactMap { summaryQuestion in
                active.firstIndex { $0.id == summaryQuestion.id }
            }
        }

        init(_ contents: SurveyFileContents) {
            name = contents.name
            questions = SurveyFileTestSupport.canonical(contents.questions)
            sampling = contents.sampling
            summary = contents.journalSummaryQuestionIds.compactMap { id in
                contents.questions.firstIndex { $0.id == id }
            }
        }
    }

    /// The repository root, found from this file's own path.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SurveyFile
            .deletingLastPathComponent() // BlipJournalCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // BlipJournalCore
            .deletingLastPathComponent()
    }
}
