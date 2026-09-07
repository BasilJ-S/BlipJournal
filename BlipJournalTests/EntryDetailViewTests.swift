import BlipJournalCore
import Testing
@testable import BlipJournal

@MainActor
struct EntryDetailViewTests {
    @Test func spectrumRenderingDoesNotDependOnCurrentZones() {
        let first = Question(kind: .spectrum, label: "Mood", position: 0, spectrum: SpectrumConfig())
        let changed = Question(kind: .spectrum, label: "Mood", position: 0, spectrum: SpectrumConfig(
            zones: [
                .init(label: "Low", color: .init(red: 0, green: 0, blue: 0)),
                .init(label: "High", color: .init(red: 1, green: 1, blue: 1)),
            ],
            breakpoints: [0.8]))

        #expect(EntryDetailView.render(.spectrum(0.4), for: first) == "40%")
        #expect(EntryDetailView.render(.spectrum(0.4), for: changed) == "40%")
    }
}
