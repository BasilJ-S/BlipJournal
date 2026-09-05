import Foundation
import Testing
import OpenBlipCore

@Suite("ID")
struct IdentifiersTests {
    @Test("make() returns a lowercase UUID")
    func makeReturnsLowercaseUUID() {
        let id = ID.make()
        #expect(id == id.lowercased())
        #expect(UUID(uuidString: id) != nil)
        #expect(id.count == 36)
    }

    @Test("make() returns a different value every call")
    func makeIsUnique() {
        let ids = Set((0..<1000).map { _ in ID.make() })
        #expect(ids.count == 1000)
    }
}
