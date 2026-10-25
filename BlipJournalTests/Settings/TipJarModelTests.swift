import Testing
@testable import BlipJournal

@MainActor
struct TipJarModelTests {
    @Test func offersExactlyThreeTipProducts() {
        #expect(TipJarModel.productIDs == [
            "io.github.basilj-s.BlipJournal.tip.small",
            "io.github.basilj-s.BlipJournal.tip.medium",
            "io.github.basilj-s.BlipJournal.tip.large",
        ])
    }

    @Test func cancellingShowsNoMessageAndOtherOutcomesDo() {
        #expect(TipJarModel.Outcome.cancelled.message == nil)
        for outcome in [TipJarModel.Outcome.thanked, .pending, .failed] {
            #expect(outcome.message != nil)
        }
    }
}
