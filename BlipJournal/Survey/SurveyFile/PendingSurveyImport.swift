import BlipJournalCore
import Foundation

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
    /// scope when it has one. The read is coordinated so a file still in iCloud is
    /// downloaded first; if coordination fails, the direct read reports why.
    init(fileAt url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        var coordinated: Result<SurveyFileContents, SurveyFileError>?
        // A coordination failure leaves `coordinated` nil, so its error is not needed.
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { readableURL in
            coordinated = SurveyFile.decode(contentsOf: readableURL)
        }
        self.init(outcome: coordinated ?? SurveyFile.decode(contentsOf: url))
    }
}
