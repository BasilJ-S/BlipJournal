import Foundation
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
}
