import Foundation
import Testing
@testable import BlipJournalCore

/// Issue #47: a JSON backup carries a SHA-256 checksum, and restore refuses a file whose
/// contents no longer match it.
@Suite("Backup checksum")
struct BackupChecksumTests {
    private let t = Fixture.at

    /// A store with an edit history and a scale, a multi-choice and a text answer.
    private func populated() throws -> Store {
        let store = try Store.inMemory()
        let survey = try Fixture.seed(store, now: t(0))
        try store.renameSurvey(survey.id, to: "Renamed", now: t(1))
        let feeling = try survey.question(labelled: "How are you feeling right now?")
        let describes = try survey.question(labelled: "What best describes this feeling?")
        let anything = try survey.question(labelled: "Anything else?")
        try store.record(in: survey, startedAt: t(100), answers: [
            (feeling, .scale(4)),
            (describes, .multi(optionIds: [try describes.option(labelled: "Calm").id])),
            (anything, .text("Walked to the lake with Sam")),
        ])
        return store
    }

    /// `data` as text with the first occurrence of `target` replaced.
    private func replacingFirst(in data: Data, _ target: String, with replacement: String) throws -> Data {
        let text = String(decoding: data, as: UTF8.self)
        let range = try #require(text.range(of: target), "no \(target) in the file")
        return Data(text.replacingCharacters(in: range, with: replacement).utf8)
    }

    @Test("the checksum is lowercase hex SHA-256")
    func knownVectors() {
        #expect(BackupExporter.checksum(of: Data())
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(BackupExporter.checksum(of: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("export writes a checksum of exactly the canonical bytes, and restore accepts it")
    func roundTrip() throws {
        let store = try populated()
        let backup = try store.backup(now: t(300))
        let file = try BackupExporter.json(backup)
        let canonical = try BackupExporter.canonicalJSON(backup)
        let checksum = BackupExporter.checksum(of: canonical)

        #expect(String(decoding: file, as: UTF8.self)
            .hasPrefix("{\n  \"checksum\" : \"\(checksum)\",\n  \"answerOptions\" : ["))
        #expect(!String(decoding: canonical, as: UTF8.self).contains("checksum"))
        // The checksum covers the file minus its checksum key, value and comma.
        let split = try #require(BackupExporter.splitChecksum(file))
        #expect(split.checksum == checksum)
        #expect(split.canonical == canonical)

        // R6: repeat exports are byte-identical, and decode inverts json.
        #expect(try BackupExporter.json(store.backup(now: t(300))) == file)
        #expect(try BackupExporter.decode(file) == backup)
        #expect(try BackupExporter.decodeForRestore(file) == backup)

        try store.eraseEverything(now: t(310))
        try store.restore(BackupExporter.decodeForRestore(file))
        #expect(try store.backup(now: t(300)) == backup)
    }

    @Test("one changed character inside a text answer is refused and nothing changes")
    func alteredTextAnswer() throws {
        let store = try populated()
        let file = try BackupExporter.json(store.backup(now: t(300)))
        let altered = try replacingFirst(in: file, "with Sam", with: "with Pam")
        // Still a well-formed backup: only the checksum stands between it and a restore.
        #expect(try BackupExporter.decode(altered).answers
            .contains { $0.textValue == "Walked to the lake with Pam" })

        try Fixture.seed(store, name: "Since the backup", now: t(400))
        let before = try store.backup(now: t(500))
        #expect(throws: RestoreError.unreadable) {
            try store.restore(BackupExporter.decodeForRestore(altered))
        }
        #expect(try store.backup(now: t(500)) == before)
    }

    @Test("a backup with no checksum, as written before checksums, still restores")
    func missingChecksumAccepted() throws {
        let store = try populated()
        let backup = try store.backup(now: t(300))
        // Before this change `json` wrote exactly what `canonicalJSON` writes now.
        let legacy = try BackupExporter.canonicalJSON(backup)
        #expect(BackupExporter.splitChecksum(legacy)?.checksum == nil)
        #expect(try BackupExporter.decodeForRestore(legacy) == backup)

        try store.eraseEverything(now: t(310))
        try store.restore(BackupExporter.decodeForRestore(legacy))
        #expect(try store.backup(now: t(300)) == backup)
    }

    @Test("a malformed, misplaced or wrong checksum is refused")
    func malformedChecksumRefused() throws {
        let store = try populated()
        let file = try BackupExporter.json(store.backup(now: t(300)))
        let good = try #require(BackupExporter.splitChecksum(file)).checksum
        let field = "\"checksum\" : \"\(good)\""
        let variants = [
            "\"checksum\" : \"\(good.uppercased())\"",                   // not lowercase
            "\"checksum\" : \"\(good.dropLast())\"",                     // 63 digits
            "\"checksum\" : \"\(good)0\"",                               // 65 digits
            "\"checksum\" : \"\(good.dropLast())g\"",                    // not hex
            "\"checksum\" : \"sha256:\(good)\"",                         // prefixed
            "\"checksum\" : \"\(String(repeating: "0", count: 64))\"",   // well formed, wrong
            "\"checksum\" : \"\"",
            "\"checksum\" : null",
            "\"checksum\" : 42",
            "\"checksum\": \"\(good)\"",                                 // right value, layout changed
        ]
        for variant in variants {
            let data = try replacingFirst(in: file, field, with: variant)
            #expect(throws: RestoreError.unreadable, "\(variant)") { try BackupExporter.decodeForRestore(data) }
        }

        // Same keys and values, reformatted: the checksum is no longer where json puts it.
        let reformatted = try JSONSerialization.data(
            withJSONObject: try JSONSerialization.jsonObject(with: file), options: [.prettyPrinted, .sortedKeys])
        #expect(throws: RestoreError.unreadable) { try BackupExporter.decodeForRestore(reformatted) }
    }

    @Test("a single changed character anywhere in string content is refused (seeded sweep)")
    func byteFlipSweep() throws {
        let store = try populated()
        let backup = try store.backup(now: t(300))
        let bytes = [UInt8](try BackupExporter.json(backup))
        let canonical = try BackupExporter.canonicalJSON(backup)
        // Skip the checksum itself: everything after it is the canonical encoding.
        let positions = Self.stringContentPositions(bytes, from: bytes.count - canonical.count + 1)
        #expect(positions.count > 1_000)
        try #require(!positions.isEmpty)

        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
        var rng = SeededRandomNumberGenerator(seed: 47)
        var stillDecodable = 0
        for _ in 0..<200 {
            let position = positions[Int.random(in: positions.indices, using: &rng)]
            var altered = bytes
            repeat {
                altered[position] = alphabet[Int.random(in: alphabet.indices, using: &rng)]
            } while altered[position] == bytes[position]
            let data = Data(altered)
            if (try? BackupExporter.decode(data)) != nil { stillDecodable += 1 }
            #expect(throws: RestoreError.unreadable, "byte \(position)") {
                try BackupExporter.decodeForRestore(data)
            }
        }
        // Many flips leave a well-formed backup that only the checksum refuses.
        #expect(stillDecodable > 0)
    }

    /// Indices of printable ASCII characters inside JSON strings (keys and values) from
    /// `start` on, skipping quotes and escape sequences so that replacing one with a
    /// letter or digit keeps the JSON well formed.
    private static func stringContentPositions(_ bytes: [UInt8], from start: Int) -> [Int] {
        let quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\")
        var positions: [Int] = []
        var inString = false
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if !inString {
                if byte == quote { inString = true }
                index += 1
            } else if byte == quote {
                inString = false
                index += 1
            } else if byte == backslash {
                index += bytes[index + 1] == UInt8(ascii: "u") ? 6 : 2
            } else {
                if (0x20..<0x7f).contains(byte) { positions.append(index) }
                index += 1
            }
        }
        return positions
    }
}
