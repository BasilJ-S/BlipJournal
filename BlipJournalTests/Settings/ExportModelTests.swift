import Foundation
import Testing
import BlipJournalCore
@testable import BlipJournal

@MainActor
struct ExportModelTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel() throws -> (ExportModel, URL) {
        let store = try Store.inMemory()
        let survey = SurveyTemplate.makeDefault(now: now)
        _ = try store.createSurvey(name: survey.name, sampling: survey.sampling, questions: survey.questions, now: now)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ExportModel(store: store, baseDirectory: directory), directory)
    }

    @Test func csvFilesHaveBomAndDocumentedNames() throws {
        let (model, directory) = try makeModel()
        defer { model.cleanUp(); try? FileManager.default.removeItem(at: directory) }

        let wide = try model.makeFile(now: now)
        let bytes = try Data(contentsOf: wide)
        #expect(bytes.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(wide.lastPathComponent == "BlipJournal-check-in-20270115-wide.csv")

        model.format = .longCSV
        let long = try model.makeFile(now: now)
        #expect(try Data(contentsOf: long).starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test func jsonHasNoBomAndDecodes() throws {
        let (model, directory) = try makeModel()
        defer { model.cleanUp(); try? FileManager.default.removeItem(at: directory) }
        model.format = .jsonBackup
        let url = try model.makeFile(now: now)
        let data = try Data(contentsOf: url)
        #expect(!data.starts(with: [0xEF, 0xBB, 0xBF]))
        _ = try BackupExporter.decode(data)
    }

    @Test func customDatesArePreservedWhenRangeChanges() throws {
        let (model, directory) = try makeModel()
        defer { model.cleanUp(); try? FileManager.default.removeItem(at: directory) }
        model.setRange(.custom, now: now)
        let start = now.addingTimeInterval(-86_400 * 2)
        model.customStart = start
        model.customEnd = now
        model.setRange(.sevenDays, now: now.addingTimeInterval(86_400))
        model.setRange(.custom, now: now.addingTimeInterval(86_400 * 10))
        #expect(model.customStart == start)
        #expect(model.customEnd == now)
    }

    @Test func cleanupEmptiesExportDirectory() throws {
        let (model, directory) = try makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try model.makeFile(now: now)
        model.cleanUp()
        #expect(try FileManager.default.contentsOfDirectory(atPath: model.exportsDirectory.path).isEmpty)
    }
}
