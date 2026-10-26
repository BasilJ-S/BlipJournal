import Foundation
import Testing
@testable import BlipJournalCore

@Suite("Store restore")
struct StoreRestoreTests {
    private let t = Fixture.at

    @Test("round trip: backup, mutate, restore gives back the backup")
    func roundTrip() throws {
        let store = try Store.inMemory()
        try Fixture.populated(store)
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
        try Fixture.populated(source)
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
        try Fixture.populated(store)
        let before = try store.backup(now: t(300))

        var bad = before
        bad.surveys = []                       // keep the rows, drop their parents
        #expect(throws: RestoreError.rejected) { try store.restore(bad) }
        #expect(try store.backup(now: t(300)) == before)

        var dangling = before
        dangling.answers[0].entryId = "no-such-entry"
        #expect(throws: RestoreError.rejected) { try store.restore(dangling) }
        #expect(try store.backup(now: t(300)) == before)

        var duplicate = before
        duplicate.entries.append(duplicate.entries[0])
        #expect(throws: RestoreError.rejected) { try store.restore(duplicate) }
        #expect(try store.backup(now: t(300)) == before)

        // Inserts cleanly but cannot be read back, as when a file's key is misspelled.
        var unreadable = before
        let valued = try #require(unreadable.answers.firstIndex { $0.spectrumValue != nil || $0.numericValue != nil })
        unreadable.answers[valued].spectrumValue = nil
        unreadable.answers[valued].numericValue = nil
        #expect(throws: RestoreError.rejected) { try store.restore(unreadable) }
        #expect(try store.backup(now: t(300)) == before)
    }

    @Test("a backup taken before schema v5 restores with every entry answered in the app")
    func restoresPreV5Backup() throws {
        let store = try Store.inMemory()
        try Fixture.populated(store)
        var flagged = try #require(try store.entries(surveyId: nil, from: nil, to: nil).first)
        flagged.answeredFromNotification = true
        try store.saveEntry(flagged, answers: try store.answers(entryId: flagged.id))
        let current = try store.backup(now: t(300))
        #expect(current.entries.map(\.answeredFromNotification) == [true, false])

        // A v4 backup has no `answeredFromNotification` key on its entries. Editing the
        // text would break a checksum, so start from the layout without one.
        var text = String(decoding: try BackupExporter.canonicalJSON(current), as: UTF8.self)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.filter { $0.contains("\"answeredFromNotification\"") }.count == 2)
        text = lines.filter { !$0.contains("\"answeredFromNotification\"") }.joined(separator: "\n")
        text = text.replacingOccurrences(of: "\"schemaVersion\" : 5", with: "\"schemaVersion\" : 4")
        let old = try BackupExporter.decodeForRestore(Data(text.utf8))
        #expect(old.schemaVersion == 4)

        try store.restore(old)
        #expect(try store.entries(surveyId: nil, from: nil, to: nil).map(\.answeredFromNotification) == [false, false])

        // And a current backup keeps the flag through JSON and restore.
        try store.restore(try BackupExporter.decodeForRestore(BackupExporter.json(current)))
        #expect(try store.backup(now: t(300)) == current)
    }

    @Test("a newer schemaVersion is refused and changes nothing")
    func newerSchema() throws {
        let store = try Store.inMemory()
        try Fixture.populated(store)
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

    @Test("the round-trip fixture has a row in every table, so a table missing from restore fails")
    func coversEveryTable() throws {
        let store = try Store.inMemory()
        try Fixture.populated(store)
        let original = try store.backup(now: t(300))
        #expect(Set(original.rowCounts.keys) == Set(Schema.tablesChildrenFirst))
        for (table, count) in original.rowCounts { #expect(count > 0, "no \(table) rows in the fixture") }

        try store.eraseEverything(now: t(310))
        try store.restore(original)
        for (table, count) in original.rowCounts {
            #expect(try store.backup(now: t(300)).rowCounts[table] == count, "\(table) not restored")
        }
    }

    @Test("restore keeps save order: selections, same-time answers and same-time entries")
    func preservesSaveOrder() throws {
        let store = try Store.inMemory()
        let survey = try Fixture.seed(store, now: t(0))
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let describes = try survey.question(labelled: "What best describes this feeling?")
        // Selections saved in descending ID order, the reverse of a sort by ID; entries
        // sharing a start time saved in descending ID order too.
        let optionIds = try describes.options.prefix(4).map(\.id).sorted(by: >)
        for id in ["zzz", "mmm", "aaa"] {
            try store.record(
                in: survey, id: id, startedAt: t(100),
                answers: [(feeling, .scale(3)), (describes, .multi(optionIds: optionIds))])
        }
        let entriesBefore = try store.entries(surveyId: nil, from: nil, to: nil)
        let answersBefore = try entriesBefore.map { try store.answers(entryId: $0.id) }
        let snapshotBefore = try store.exportSnapshot(surveyId: survey.id)
        #expect(entriesBefore.map(\.id) == ["zzz", "mmm", "aaa"])

        let backup = try BackupExporter.decodeForRestore(BackupExporter.json(store.backup(now: t(300))))
        try store.eraseEverything(now: t(310))
        try store.restore(backup)

        #expect(try store.entries(surveyId: nil, from: nil, to: nil) == entriesBefore)
        #expect(try entriesBefore.map { try store.answers(entryId: $0.id) } == answersBefore)
        #expect(try store.exportSnapshot(surveyId: survey.id) == snapshotBefore)
        let restored = try store.answers(entryId: "zzz").first { $0.questionId == describes.id }
        #expect(restored?.value == .multi(optionIds: optionIds))
    }
}
