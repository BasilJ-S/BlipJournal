import Foundation
import Testing
import BlipJournalCore

@Suite("Store restore")
struct StoreRestoreTests {
    private let t = Fixture.at

    /// A store holding two surveys, an edit history, a prompt and entries with answers.
    private func populated(_ store: Store) throws {
        let survey = try Fixture.seed(store, now: t(0))
        try Fixture.seed(store, name: "Other", now: t(1))
        try store.renameSurvey(survey.id, to: "Renamed", now: t(2))
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let describes = try survey.question(labelled: "What best describes this feeling?")
        let prompt = Fixture.prompt(survey, scheduledAt: t(50))
        try store.insertPrompts([prompt])
        try store.record(
            in: survey, promptId: prompt.id, startedAt: t(100),
            answers: [
                (feeling, .scale(4)),
                (describes, .multi(optionIds: [
                    try describes.option(labelled: "Calm").id, try describes.option(labelled: "Happy").id])),
            ])
        try store.record(in: survey, startedAt: t(200), answers: [])
    }

    @Test("round trip: backup, mutate, restore gives back the backup")
    func roundTrip() throws {
        let store = try Store.inMemory()
        try populated(store)
        let original = try store.backup(now: t(300))
        #expect(original.entries.count == 2)

        // Mutate: add data and erase the rest.
        try Fixture.seed(store, name: "Added later", now: t(310))
        try store.eraseEverything(now: t(320))
        #expect(try store.backup(now: t(330)).surveys.count == 1)

        // Through JSON, as the app does.
        let decoded = try BackupExporter.decodeForRestore(BackupExporter.json(original))
        try store.restore(decoded)

        #expect(try store.backup(now: t(300)) == original)
        #expect(try store.summary() == BackupSummary(exportedAt: nil, surveys: 2, entries: 2))
        #expect(original.summary == BackupSummary(exportedAt: original.exportedAt, surveys: 2, entries: 2))
    }

    @Test("restoring into a populated store replaces rather than merges")
    func replaces() throws {
        let source = try Store.inMemory()
        try populated(source)
        let backup = try source.backup(now: t(300))

        let target = try Store.inMemory()
        try Fixture.seed(target, name: "Only on the phone", now: t(5))
        try target.restore(backup)

        let after = try target.backup(now: t(300))
        #expect(after == backup)
        #expect(!(try after.jsonString().contains("Only on the phone")))
    }

    @Test("a failing row rolls everything back")
    func rollback() throws {
        let store = try Store.inMemory()
        try populated(store)
        let before = try store.backup(now: t(300))

        var bad = before
        bad.surveys = []                       // keep the rows, drop their parents
        #expect(throws: (any Error).self) { try store.restore(bad) }
        #expect(try store.backup(now: t(300)) == before)

        var dangling = before
        dangling.answers[0].entryId = "no-such-entry"
        #expect(throws: (any Error).self) { try store.restore(dangling) }
        #expect(try store.backup(now: t(300)) == before)

        var duplicate = before
        duplicate.entries.append(duplicate.entries[0])
        #expect(throws: (any Error).self) { try store.restore(duplicate) }
        #expect(try store.backup(now: t(300)) == before)
    }

    @Test("a newer schemaVersion is refused and changes nothing")
    func newerSchema() throws {
        let store = try Store.inMemory()
        try populated(store)
        let before = try store.backup(now: t(300))

        var newer = before
        newer.schemaVersion = CoreSchema.version + 1
        let expected = RestoreError.newerSchema(found: CoreSchema.version + 1, supported: CoreSchema.version)
        #expect(throws: expected) { try store.restore(newer) }
        #expect(try store.backup(now: t(300)) == before)

        // The file route refuses it too, even when the rest of the file is unreadable.
        let json = Data(#"{"schemaVersion": \#(CoreSchema.version + 1), "somethingNew": true}"#.utf8)
        #expect(throws: expected) { try BackupExporter.decodeForRestore(json) }
    }

    @Test("a file that is not a backup is unreadable")
    func unreadable() throws {
        for text in ["", "not json", "[]", #"{"hello": "world"}"#, #"{"schemaVersion": 4}"#] {
            #expect(throws: RestoreError.unreadable) { try BackupExporter.decodeForRestore(Data(text.utf8)) }
        }
    }

    @Test("a backup from an older schema still restores")
    func olderSchema() throws {
        let store = try Store.inMemory()
        try populated(store)
        var old = try store.backup(now: t(300))
        old.schemaVersion = 1
        try store.restore(old)
        #expect(try store.backup(now: t(300)).surveys.count == 2)
    }
}
