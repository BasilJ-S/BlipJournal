import Foundation
import Testing
import OpenBlipCore

@Suite("LabelVersion")
struct LabelVersionTests {
    private let first = Date(timeIntervalSinceReferenceDate: 100)
    private let second = Date(timeIntervalSinceReferenceDate: 200)

    private var history: [LabelVersion] {
        [
            LabelVersion(label: "Original", validFrom: first),
            LabelVersion(label: "Renamed", validFrom: second),
        ]
    }

    @Test("a date before every version falls back to the earliest label")
    func beforeAllVersions() {
        #expect(history.label(at: first.addingTimeInterval(-1)) == "Original")
    }

    @Test("a date between versions picks the older label")
    func betweenVersions() {
        #expect(history.label(at: first) == "Original")
        #expect(history.label(at: first.addingTimeInterval(50)) == "Original")
        #expect(history.label(at: second.addingTimeInterval(-1)) == "Original")
    }

    @Test("a date at or after the newest version picks the newest label")
    func afterAllVersions() {
        #expect(history.label(at: second) == "Renamed")
        #expect(history.label(at: second.addingTimeInterval(10_000)) == "Renamed")
    }

    @Test("an empty history has no label")
    func emptyHistory() {
        #expect([LabelVersion]().label(at: first) == nil)
    }

    @Test("the receiver does not have to be sorted")
    func unsortedHistory() {
        let reversed = Array(history.reversed())
        #expect(reversed.label(at: first.addingTimeInterval(-1)) == "Original")
        #expect(reversed.label(at: first.addingTimeInterval(50)) == "Original")
        #expect(reversed.label(at: second) == "Renamed")
    }

    @Test("a single version answers for every date")
    func singleVersion() {
        let only = [LabelVersion(label: "Only", validFrom: second)]
        #expect(only.label(at: first) == "Only")
        #expect(only.label(at: second) == "Only")
    }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode([LabelVersion].self, from: data) == history)
    }
}
