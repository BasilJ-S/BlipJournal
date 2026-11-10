import BlipJournalCore
import Testing
import Foundation
@testable import BlipJournal

@MainActor
struct EntryDetailViewTests {
    @Test func reloadReadsPersistedCompletionInsteadOfInitialEntry() async throws {
        let store = try Store.inMemory()
        let survey = try store.createSurvey(name: "Test", sampling: .default, questions: [])
        let stale = Entry(surveyId: survey.id, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.saveEntry(stale, answers: [])
        let first = try await EntryDetailView.read(store: store, entry: stale)
        #expect(first.entry.completedAt == nil)
        var completed = stale
        completed.completedAt = stale.startedAt.addingTimeInterval(30)
        try store.saveEntry(completed, answers: [])
        let refreshed = try await EntryDetailView.read(store: store, entry: stale)
        #expect(refreshed.entry == completed)
        #expect(refreshed.prompt == nil)
    }

    @Test func reloadAfterDeletionReportsMissingEntry() async throws {
        let store = try Store.inMemory()
        let survey = try store.createSurvey(name: "Test", sampling: .default, questions: [])
        let entry = Entry(surveyId: survey.id, startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.saveEntry(entry, answers: [])
        try store.deleteEntry(entry.id)
        await #expect(throws: StoreError.notFound) {
            try await EntryDetailView.read(store: store, entry: entry)
        }
    }

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
