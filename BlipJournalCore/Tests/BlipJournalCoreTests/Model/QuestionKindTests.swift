import Foundation
import Testing
import BlipJournalCore

@Suite("QuestionKind")
struct QuestionKindTests {
    @Test("only choice kinds use options")
    func usesOptions() {
        #expect(QuestionKind.singleChoice.usesOptions)
        #expect(QuestionKind.multiChoice.usesOptions)
        #expect(!QuestionKind.scale.usesOptions)
        #expect(!QuestionKind.yesNo.usesOptions)
        #expect(!QuestionKind.text.usesOptions)
    }

    @Test("raw values are the persisted contract")
    func rawValues() {
        #expect(QuestionKind.allCases.map(\.rawValue) == [
            "scale", "singleChoice", "multiChoice", "yesNo", "text",
        ])
    }
}

@Suite("ScaleConfig")
struct ScaleConfigTests {
    @Test("defaults are the 1 to 7 pleasantness scale")
    func defaults() {
        let scale = ScaleConfig()
        #expect(scale.min == 1)
        #expect(scale.max == 7)
        #expect(scale.minLabel == "Very unpleasant")
        #expect(scale.maxLabel == "Very pleasant")
        #expect(scale.isValid)
    }

    @Test("isValid rejects a max at or below min", arguments: [
        (min: 5, max: 5),
        (min: 5, max: 4),
        (min: 0, max: -3),
    ])
    func rejectsCollapsedRange(bounds: (min: Int, max: Int)) {
        #expect(!ScaleConfig(min: bounds.min, max: bounds.max).isValid)
    }

    @Test("isValid accepts the full -100...100 span and rejects one step past either end")
    func acceptsFullRange() {
        #expect(ScaleConfig(min: -100, max: 100).isValid)
        #expect(!ScaleConfig(min: -101, max: 100).isValid)
        #expect(!ScaleConfig(min: -100, max: 101).isValid)
    }

    @Test("isValid accepts a negative-only and a crossing-zero range, zero included", arguments: [
        (min: -100, max: -1), (min: -50, max: 0), (min: 0, max: 1), (min: -1, max: 1),
    ])
    func acceptsNegativeAndCrossingZero(bounds: (min: Int, max: Int)) {
        #expect(ScaleConfig(min: bounds.min, max: bounds.max).isValid)
    }

    @Test("isValid rejects equal and reversed endpoints")
    func rejectsEqualAndReversed() {
        #expect(!ScaleConfig(min: 0, max: 0).isValid)
        #expect(!ScaleConfig(min: 5, max: -5).isValid)
    }

    @Test("isValid compares bounds directly, so extreme Int values never overflow")
    func extremeValuesDoNotTrap() {
        #expect(!ScaleConfig(min: Int.min, max: Int.max).isValid)
        #expect(!ScaleConfig(min: Int.min, max: 0).isValid)
        #expect(!ScaleConfig(min: 0, max: Int.max).isValid)
        #expect(!ScaleConfig(min: Int.max, max: Int.max).isValid)
        #expect(!ScaleConfig(min: Int.min, max: Int.min).isValid)
    }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        let scale = ScaleConfig(min: 0, max: 10, minLabel: "Low", maxLabel: "High")
        let data = try JSONEncoder().encode(scale)
        #expect(try JSONDecoder().decode(ScaleConfig.self, from: data) == scale)
    }
}
