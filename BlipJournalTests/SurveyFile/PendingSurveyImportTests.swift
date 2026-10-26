import BlipJournalCore
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import BlipJournal

struct PendingSurveyImportTests {
    private func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("blipsurvey")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func readsASurveyFileFromDisk() throws {
        let url = try write(#"{"formatVersion": 1, "name": "Shared", "questions": [{"kind": "text", "label": "Note"}]}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .success(let contents)? = PendingSurveyImport(fileAt: url).outcome else {
            Issue.record("a valid file did not read")
            return
        }
        #expect(contents.name == "Shared")
    }

    @Test func reportsABrokenFileWithoutThrowing() throws {
        let url = try write(#"{"formatVersion": 1}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        guard case .failure(let error)? = PendingSurveyImport(fileAt: url).outcome else {
            Issue.record("a broken file read")
            return
        }
        #expect(error.issues.map(\.path).contains("name"))
    }

    @Test func pasteStartsWithNothingRead() {
        #expect(PendingSurveyImport.paste().outcome == nil)
    }

    @Test func surveyFilesAreJSON() {
        #expect(UTType.blipSurvey.conforms(to: .json))
    }
}
