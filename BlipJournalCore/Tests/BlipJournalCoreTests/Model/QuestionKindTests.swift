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
        #expect(!QuestionKind.spectrum.usesOptions)
        #expect(!QuestionKind.yesNo.usesOptions)
        #expect(!QuestionKind.text.usesOptions)
    }

    @Test("raw values are the persisted contract")
    func rawValues() {
        #expect(QuestionKind.allCases.map(\.rawValue) == [
            "scale", "spectrum", "singleChoice", "multiChoice", "yesNo", "text",
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

@Suite("SpectrumConfig")
struct SpectrumConfigTests {
    @Test("defaults are the three-band pleasantness spectrum")
    func defaults() {
        let spectrum = SpectrumConfig()
        #expect(spectrum.zones.map(\.label) == ["Very unpleasant", "Neutral", "Very pleasant"])
        #expect(spectrum.breakpoints == [1.0 / 3.0, 2.0 / 3.0])
        #expect(spectrum.isValid)
    }

    @Test("every preset is valid")
    func presetsAreValid() {
        #expect(SpectrumConfig.presets.allSatisfy { $0.config.isValid })
    }

    @Test("isValid rejects a breakpoint count that does not match zones minus one")
    func rejectsMismatchedBreakpointCount() {
        var spectrum = SpectrumConfig()
        spectrum.breakpoints = [0.5]
        #expect(!spectrum.isValid)
        spectrum.breakpoints = [0.2, 0.5, 0.8]
        #expect(!spectrum.isValid)
    }

    @Test("isValid rejects breakpoints out of order, out of range, or repeated")
    func rejectsMalformedBreakpoints() {
        var spectrum = SpectrumConfig()
        spectrum.breakpoints = [2.0 / 3.0, 1.0 / 3.0]
        #expect(!spectrum.isValid)
        spectrum.breakpoints = [0, 2.0 / 3.0]
        #expect(!spectrum.isValid)
        spectrum.breakpoints = [1.0 / 3.0, 1]
        #expect(!spectrum.isValid)
        spectrum.breakpoints = [0.5, 0.5]
        #expect(!spectrum.isValid)
    }

    @Test("isValid rejects fewer than two zones")
    func rejectsTooFewZones() {
        let spectrum = SpectrumConfig(zones: [SpectrumConfig.Zone(label: "Only", color: SpectrumColor(red: 0, green: 0, blue: 0))], breakpoints: [])
        #expect(!spectrum.isValid)
    }

    @Test("isValid rejects blank and whitespace-only zone labels")
    func rejectsBlankLabels() {
        var spectrum = SpectrumConfig()
        spectrum.zones[0].label = ""
        #expect(!spectrum.isValid)
        spectrum.zones[0].label = " \n "
        #expect(!spectrum.isValid)
    }

    @Test("zoneIndex(for:) picks the zone the value falls in, clamped to 0...1")
    func zoneIndexPicksTheRightBand() {
        let spectrum = SpectrumConfig()
        #expect(spectrum.zoneIndex(for: 0) == 0)
        #expect(spectrum.zoneIndex(for: 0.2) == 0)
        #expect(spectrum.zoneIndex(for: 1.0 / 3.0) == 1)
        #expect(spectrum.zoneIndex(for: 0.5) == 1)
        #expect(spectrum.zoneIndex(for: 2.0 / 3.0) == 2)
        #expect(spectrum.zoneIndex(for: 1) == 2)
        #expect(spectrum.zoneIndex(for: -1) == 0)
        #expect(spectrum.zoneIndex(for: 2) == 2)
    }

    @Test("zone(for:) returns the zone at that index")
    func zoneReturnsTheZone() {
        let spectrum = SpectrumConfig()
        #expect(spectrum.zone(for: 0.9)?.label == "Very pleasant")
    }

    @Test("zone lookup returns nil for an invalid configuration")
    func invalidZoneLookup() {
        let empty = SpectrumConfig(zones: [], breakpoints: [])
        #expect(empty.zoneIndex(for: 0.5) == nil)
        #expect(empty.zone(for: 0.5) == nil)

        var malformed = SpectrumConfig()
        malformed.breakpoints = []
        #expect(malformed.zoneIndex(for: 0.5) == nil)
        #expect(malformed.zone(for: 0.5) == nil)
    }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        let spectrum = SpectrumConfig()
        let data = try JSONEncoder().encode(spectrum)
        #expect(try JSONDecoder().decode(SpectrumConfig.self, from: data) == spectrum)
    }
}
