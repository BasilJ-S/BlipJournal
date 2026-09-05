import Foundation
import Testing
import OpenBlipCore

@Suite("SamplingConfig")
struct SamplingConfigTests {
    @Test("the default schedule matches the README and validates")
    func defaultIsValid() {
        let config = SamplingConfig.default
        #expect(config.promptsPerDay == 3)
        #expect(config.windowStartMinutes == 540)
        #expect(config.windowEndMinutes == 1380)
        #expect(config.minGapMinutes == 60)
        #expect(config.expiryMinutes == 20)
        #expect(config.isEnabled)
        #expect(config.validationErrors.isEmpty)
    }

    @Test("promptsPerDay outside 0...20 is the only error raised", arguments: [-1, 21, 100])
    func promptsPerDayOutOfRange(count: Int) {
        // A whole-day window with a short gap, so the count is the only rule broken.
        var config = SamplingConfig(
            windowStartMinutes: 0,
            windowEndMinutes: 1440,
            minGapMinutes: 1
        )
        config.promptsPerDay = count
        #expect(config.validationErrors == [.promptsPerDayOutOfRange])
    }

    @Test("a count that is both out of range and too dense reports both rules")
    func promptsPerDayBreaksGapToo() {
        var config = SamplingConfig.default
        config.promptsPerDay = 21
        #expect(config.validationErrors == [.promptsPerDayOutOfRange, .gapDoesNotFit])
    }

    @Test("the edges of the promptsPerDay range are accepted")
    func promptsPerDayEdges() {
        var none = SamplingConfig.default
        none.promptsPerDay = 0
        #expect(none.validationErrors.isEmpty)

        var many = SamplingConfig.default
        many.promptsPerDay = 20
        many.minGapMinutes = 10
        #expect(many.validationErrors.isEmpty)
    }

    @Test("a malformed window is the only error raised", arguments: [
        (start: -1, end: 1380),
        (start: 600, end: 600),
        (start: 900, end: 600),
        (start: 540, end: 1441),
    ])
    func windowOutOfRange(window: (start: Int, end: Int)) {
        var config = SamplingConfig.default
        config.windowStartMinutes = window.start
        config.windowEndMinutes = window.end
        #expect(config.validationErrors == [.windowOutOfRange])
    }

    @Test("a full-day window is well formed")
    func fullDayWindow() {
        var config = SamplingConfig.default
        config.windowStartMinutes = 0
        config.windowEndMinutes = 1440
        #expect(config.validationErrors.isEmpty)
    }

    @Test("3 prompts with a 60 minute gap fit a 14 hour window")
    func gapFits() {
        let config = SamplingConfig(
            promptsPerDay: 3,
            windowStartMinutes: 540,
            windowEndMinutes: 1380,
            minGapMinutes: 60
        )
        #expect(config.validationErrors.isEmpty)
    }

    @Test("20 prompts with a 60 minute gap do not fit a 14 hour window")
    func gapDoesNotFit() {
        let config = SamplingConfig(
            promptsPerDay: 20,
            windowStartMinutes: 540,
            windowEndMinutes: 1380,
            minGapMinutes: 60
        )
        #expect(config.validationErrors == [.gapDoesNotFit])
    }

    @Test("the gap rule needs the prompts to fit strictly inside the window")
    func gapBoundary() {
        // 15 prompts, 60 minute gap: 14 gaps need 840 minutes, the window is 840.
        var exact = SamplingConfig.default
        exact.promptsPerDay = 15
        #expect(exact.validationErrors == [.gapDoesNotFit])

        var justFits = exact
        justFits.minGapMinutes = 59
        #expect(justFits.validationErrors.isEmpty)
    }

    @Test("a malformed window does not also report gapDoesNotFit")
    func windowErrorDoesNotCascade() {
        var config = SamplingConfig.default
        config.windowStartMinutes = 1380
        config.windowEndMinutes = 540
        #expect(config.validationErrors == [.windowOutOfRange])
    }

    @Test("a gap outside 0...1440 is the only error raised", arguments: [-1, -60, 1441])
    func minGapOutOfRange(gap: Int) {
        var config = SamplingConfig.default
        config.minGapMinutes = gap
        #expect(config.validationErrors == [.minGapOutOfRange])
    }

    @Test("the edges of the gap range are accepted")
    func minGapEdges() {
        var none = SamplingConfig.default
        none.minGapMinutes = 0
        #expect(none.validationErrors.isEmpty)

        // A whole-day gap only fits a schedule that asks for at most one prompt.
        var whole = SamplingConfig.default
        whole.promptsPerDay = 1
        whole.minGapMinutes = 1440
        #expect(whole.validationErrors.isEmpty)
    }

    @Test("a negative gap does not also report gapDoesNotFit")
    func gapErrorDoesNotCascade() {
        var config = SamplingConfig.default
        config.minGapMinutes = -600
        #expect(config.validationErrors == [.minGapOutOfRange])
    }

    @Test("expiry outside 1...240 is the only error raised", arguments: [0, -5, 241])
    func expiryOutOfRange(expiry: Int) {
        var config = SamplingConfig.default
        config.expiryMinutes = expiry
        #expect(config.validationErrors == [.expiryOutOfRange])
    }

    @Test("the edges of the expiry range are accepted")
    func expiryEdges() {
        var short = SamplingConfig.default
        short.expiryMinutes = 1
        #expect(short.validationErrors.isEmpty)

        var long = SamplingConfig.default
        long.expiryMinutes = 240
        #expect(long.validationErrors.isEmpty)
    }

    @Test("independent mistakes are all reported, in a fixed order")
    func errorsAreOrdered() {
        let config = SamplingConfig(
            promptsPerDay: 50,
            windowStartMinutes: 900,
            windowEndMinutes: 100,
            minGapMinutes: -1,
            expiryMinutes: 0
        )
        #expect(config.validationErrors == [
            .promptsPerDayOutOfRange, .windowOutOfRange, .minGapOutOfRange, .expiryOutOfRange,
        ])
    }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        let config = SamplingConfig(
            promptsPerDay: 5,
            windowStartMinutes: 480,
            windowEndMinutes: 1200,
            minGapMinutes: 30,
            expiryMinutes: 15,
            isEnabled: false
        )
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(SamplingConfig.self, from: data) == config)
    }
}
