import Foundation
import Testing
import BlipJournalCore
@testable import BlipJournal

@MainActor
struct RestoreBackupModelTests {
    @Test func refusalMessagesAreWordedForAPersonAndPromiseNothingChanged() {
        let newer = RestoreBackupModel.message(for: RestoreError.newerSchema(found: 9, supported: 4))
        let unreadable = RestoreBackupModel.message(for: RestoreError.unreadable)
        for message in [newer, unreadable] {
            #expect(message.contains("Blip Journal"))
            #expect(message.contains("Nothing was changed"))
            #expect(!message.contains("BlipJournal"))
        }
        #expect(newer != unreadable)

        let damaged = RestoreBackupModel.message(for: RestoreError.rejected)
        #expect(damaged.contains("Nothing was changed"))
        struct DatabaseLike: LocalizedError { var errorDescription: String? { "SQLite error 19: FOREIGN KEY constraint failed" } }
        let other = RestoreBackupModel.message(for: DatabaseLike())
        #expect(!other.contains("SQLite"))
        #expect(!other.contains("Nothing was changed"))   // the data may have been replaced
    }
}
