import BlipJournalCore
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A survey file with the `.blipsurvey` extension: plain JSON in the survey file
    /// format. Declared under `UTExportedTypeDeclarations` in Info.plist.
    static let blipSurvey = UTType(exportedAs: "io.github.basilj-s.BlipJournal.survey", conformingTo: .json)
}

/// A survey's current definition as a shareable `.blipsurvey` file, named after the survey.
struct SurveyFileDocument: Transferable {
    let survey: Survey

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .blipSurvey) { document in
            SurveyFile.encode(document.survey)
        }
        .suggestedFileName { document in
            // A slash or colon would read as a folder separator in Files.
            let name = document.survey.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            return "\(name).blipsurvey"
        }
    }
}
