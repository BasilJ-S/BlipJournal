import Foundation
import Testing
import BlipJournalCore

/// Spectrum coverage kept separate from `ExportFixture`'s big shared snapshot: a
/// minimal survey and entry are enough to prove a spectrum answer's cell shape in both
/// formats, without threading a new question through every fixture-dependent assertion.
@Suite("CSVExporter spectrum answers")
struct CSVExporterSpectrumTests {
    @Test("wide and long both write the raw 0...1 value")
    func spectrumValueIsWritten() throws {
        let question = Question(
            id: "q1", kind: .spectrum, label: "How pleasant?", position: 0,
            spectrum: SpectrumConfig())
        let survey = Survey(id: "s1", name: "Survey", questions: [question])
        let entry = Entry(id: "e1", surveyId: "s1", startedAt: Date(timeIntervalSince1970: 0), completedAt: Date(timeIntervalSince1970: 60))
        let answer = Answer(
            id: "a1", entryId: "e1", questionId: "q1", questionVersionId: "v1",
            answeredAt: Date(timeIntervalSince1970: 30), value: .spectrum(0.75))
        let snapshot = ExportSnapshot(
            survey: survey,
            entries: [ExportEntry(entry: entry, answers: [answer])],
            questionLabelHistory: ["q1": [LabelVersion(label: "How pleasant?", validFrom: Date(timeIntervalSince1970: 0))]],
            optionLabelHistory: [:],
            questionVersionLabels: ["v1": "How pleasant?"])
        let calendar = Calendar(identifier: .gregorian)

        let wideTable = CSVTable(CSVExporter.wide(snapshot, calendar: calendar))
        #expect(wideTable.header.last == "How pleasant?")
        #expect(wideTable.rows[0].last == "0.75")

        let longTable = CSVTable(CSVExporter.long(snapshot, calendar: calendar))
        let numericValueIndex = try #require(longTable.header.firstIndex(of: "numeric_value"))
        #expect(longTable.rows[0][numericValueIndex] == "0.75")
    }
}
