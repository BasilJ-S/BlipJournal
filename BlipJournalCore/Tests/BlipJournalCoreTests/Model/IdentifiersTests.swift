import Foundation
import Testing
import BlipJournalCore

@Suite("Identifier")
struct IdentifierTests {
    @Test("make() returns a lowercase UUID")
    func makeReturnsLowercaseUUID() {
        let id = Identifier.make()
        #expect(id == id.lowercased())
        #expect(UUID(uuidString: id) != nil)
        #expect(id.count == 36)
    }

    @Test("make() returns a different value every call")
    func makeIsUnique() {
        let ids = Set((0..<1000).map { _ in Identifier.make() })
        #expect(ids.count == 1000)
    }
}
