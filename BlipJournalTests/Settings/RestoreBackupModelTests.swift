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
    }
}
