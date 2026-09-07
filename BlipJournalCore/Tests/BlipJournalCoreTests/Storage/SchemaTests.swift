import Foundation
import GRDB
import Testing
@testable import BlipJournalCore

@Suite("Schema")
struct SchemaTests {
    @Test("the migration runs on an empty in-memory database and leaves every table empty")
    func migratesEmptyDatabase() throws {
        let store = try Store.inMemory()
        let backup = try store.backup(now: Fixture.t0)
        #expect(backup.schemaVersion == CoreSchema.version)
        #expect(CoreSchema.version == 3)
        #expect(backup.rowCounts.values.allSatisfy { $0 == 0 })
        #expect(backup.rowCounts.count == 12)
    }

    @Test("every connection runs with secure_delete on, temp_store in memory, and a rollback journal")
    func connectionPragmas() throws {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for (store, expectedJournal) in [(try Store.inMemory(), "memory"), (try Store.open(at: directory), "delete")] {
            let (secureDelete, tempStore, journalMode) = try store.dbQueue.read { db in
                (try Int.fetchOne(db, sql: "PRAGMA secure_delete"),
                 try Int.fetchOne(db, sql: "PRAGMA temp_store"),
                 try String.fetchOne(db, sql: "PRAGMA journal_mode"))
            }
            #expect(secureDelete == 1)
            #expect(tempStore == 2)    // MEMORY
            #expect(journalMode?.lowercased() == expectedJournal)
        }
    }

    @Test("open creates the directory and the database file")
    func openCreatesDirectory() throws {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))

        _ = try Store.open(at: directory)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(Store.databaseFileName).path))
    }

    @Test("opening the same file twice keeps its data and does not re-run the migration")
    func reopenKeepsData() throws {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try Store.open(at: directory)
        let survey = try Fixture.seed(first)

        // A second open on the same file: a re-run of "v1" would fail on CREATE TABLE.
        let second = try Store.open(at: directory)
        #expect(try second.surveys(includeArchived: true) == [survey])
        #expect(try second.backup(now: Fixture.t0) == first.backup(now: Fixture.t0))
    }

    @Test("opening a v2 database preserves existing data and adds spectrum storage")
    func migratesFromV2() throws {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(Store.databaseFileName).path

        do {
            var v2Only = DatabaseMigrator()
            v2Only.registerMigration("v1", migrate: Schema.migrateV1)
            v2Only.registerMigration("v2", migrate: Schema.migrateV2)
            let queue = try DatabaseQueue(path: path)
            try v2Only.migrate(queue)
            try queue.write { db in
                try db.execute(
                    sql: "INSERT INTO survey (id, createdAt) VALUES (?, ?)",
                    arguments: ["s1", Fixture.t0])
                try db.execute(
                    sql: "INSERT INTO surveyVersion (id, surveyId, name, isArchived, createdAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: ["sv1", "s1", "Existing", false, Fixture.t0])
                try db.execute(
                    sql: "INSERT INTO question (id, surveyId, kind, createdAt) VALUES (?, ?, ?, ?)",
                    arguments: ["q1", "s1", "scale", Fixture.t0])
                try db.execute(
                    sql: """
                        INSERT INTO questionVersion
                            (id, questionId, label, position, isRequired, isArchived,
                             scaleMin, scaleMax, scaleMinLabel, scaleMaxLabel,
                             allowsCustomOptions, createdAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: ["qv1", "q1", "Mood", 0, true, false, 1, 7, "Low", "High", false, Fixture.t0])
                try db.execute(
                    sql: "INSERT INTO entry (id, surveyId, startedAt, completedAt) VALUES (?, ?, ?, ?)",
                    arguments: ["e1", "s1", Fixture.t0, Fixture.t0])
                try db.execute(
                    sql: """
                        INSERT INTO answer
                            (id, entryId, questionId, questionVersionId, answeredAt, kind, numericValue)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: ["a1", "e1", "q1", "qv1", Fixture.t0, "scale", 4])
            }
        }

        let store = try Store.open(at: directory)
        #expect(try store.survey("s1")?.name == "Existing")
        #expect(try store.answers(entryId: "e1").first?.value == .scale(4))

        let spectrum = try store.addQuestion(
            surveyId: "s1", kind: .spectrum, label: "Energy", isRequired: false,
            scale: nil, spectrum: SpectrumConfig(), allowsCustomOptions: false,
            now: Fixture.t0.addingTimeInterval(1))
        let versionId = try #require(try store.currentQuestionVersionIds(surveyId: "s1")[spectrum.id])
        let entry = Entry(id: "e2", surveyId: "s1", startedAt: Fixture.t0, completedAt: Fixture.t0)
        try store.saveEntry(entry, answers: [Answer(
            id: "a2", entryId: entry.id, questionId: spectrum.id,
            questionVersionId: versionId, answeredAt: Fixture.t0, value: .spectrum(0.75))])
        #expect(try store.answers(entryId: "e2").first?.value == .spectrum(0.75))
    }
}
