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

/// A survey file read and waiting for the person to look it over, or a request to paste
/// one. Every way a survey enters from outside (Files, another app's share sheet, pasted
/// text) ends here and in `SurveyImportSheet`.
struct PendingSurveyImport: Identifiable {
    let id = UUID()
    /// Nil asks the person to paste survey text first.
    let outcome: Result<SurveyFileContents, SurveyFileError>?

    private init(outcome: Result<SurveyFileContents, SurveyFileError>?) {
        self.outcome = outcome
    }

    static func paste() -> PendingSurveyImport {
        PendingSurveyImport(outcome: nil)
    }

    /// Reads a file picked in Files or handed over by another app, inside its security
    /// scope when it has one. Bundled files take the same path.
    init(fileAt url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        self.init(outcome: SurveyFile.decode(contentsOf: url))
    }
}
