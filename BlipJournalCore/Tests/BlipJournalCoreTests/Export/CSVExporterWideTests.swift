import Foundation
import Testing
import BlipJournalCore

@Suite("CSVExporter.wide")
struct CSVExporterWideTests {
    typealias F = ExportFixture

    private let fixedColumns = [
        "entry_id", "survey", "prompted", "prompt_scheduled_at", "started_at",
        "completed_at", "latency_seconds",
    ]

    private var output: String { CSVExporter.wide(F.snapshot, calendar: F.calendar) }
    private var table: CSVTable { CSVTable(output) }

    @Test("header is the fixed columns then one per question in position order, duplicates suffixed")
    func header() {
        let header = table.header
        #expect(header.count == fixedColumns.count + F.survey.questions.count)
        #expect(Array(header.prefix(fixedColumns.count)) == fixedColumns)
        #expect(Array(header.dropFirst(fixedColumns.count)) == [
            F.scaleLabelNew, F.singleLabel, F.multiLabel, F.yesNoLabel,
            "Notes [textnote]", "Notes [archived]",
        ])
        #expect(Set(header).count == header.count)
    }

    @Test("exactly one row per entry, in snapshot order")
    func oneRowPerEntry() {
        let table = table
        #expect(table.rows.count == F.entries.count)
        #expect(table.rows.map { $0[0] } == [F.entry1, F.entry2, F.entry3, F.entry4])
    }

    @Test("every row has as many fields as the header, embedded newlines included")
    func fieldCounts() {
        let table = table
        for row in table.rows {
            #expect(row.count == table.header.count)
        }
        // The embedded newlines survived parsing, so they were quoted, not split.
        #expect(table[1, column: "Notes [textnote]"] == "Line one\nline two")
        #expect(table[2, column: F.multiLabel] == F.familyLabel)
    }

    @Test("commas, quotes and newlines are quoted in the raw text")
    func rawQuoting() {
        let output = output
        #expect(output.contains("\"Outside, or \"\"out\"\"?\""))
        #expect(output.contains("\"Line one\nline two\""))
        #expect(output.contains("\"Family\nmembers\""))
        #expect(output.contains("\"Resting, quietly\""))
        #expect(output.contains("\"Other \"\"stuff\"\"\""))
        #expect(output.contains("\"He said \"\"hi\"\"\""))
        #expect(output.contains("\"Fine, thanks\""))
    }

    @Test("lines end with CRLF and the output has no BOM")
    func lineEndings() {
        let output = output
        #expect(output.hasSuffix("\r\n"))
        // One CRLF per row; the embedded newlines in entry 2's text and entry 3's
        // multi-choice cell are bare LFs, so they do not count.
        #expect(output.components(separatedBy: "\r\n").count - 1 == F.entries.count + 1)
        #expect(output.unicodeScalars.first == "e")
        #expect(!output.unicodeScalars.contains("\u{FEFF}"))
    }

    @Test("a prompted, completed entry has full prompt columns and latency")
    func promptedEntry() {
        let table = table
        #expect(table[0, column: "survey"] == F.surveyName)
        #expect(table[0, column: "prompted"] == "yes")
        #expect(table[0, column: "prompt_scheduled_at"] == "2026-09-01T10:00:00-04:00")
        #expect(table[0, column: "started_at"] == "2026-09-01T10:01:00-04:00")
        #expect(table[0, column: "completed_at"] == "2026-09-01T10:03:00-04:00")
        #expect(table[0, column: "latency_seconds"] == "180")
        #expect(table[1, column: "latency_seconds"] == "135")
    }

    @Test("cells hold current labels and values in the right shape")
    func cellValues() {
        let table = table
        #expect(table[0, column: F.scaleLabelNew] == "5")
        #expect(table[0, column: F.singleLabel] == F.workLabelNew)
        #expect(table[0, column: F.yesNoLabel] == "yes")
        #expect(table[0, column: "Notes [textnote]"] == "Fine, thanks")
        #expect(table[0, column: "Notes [archived]"] == "3")
        #expect(table[1, column: F.yesNoLabel] == "no")
        #expect(table[2, column: F.singleLabel] == F.restLabel)
        #expect(table[2, column: "Notes [textnote]"] == "He said \"hi\"")
        #expect(table[3, column: F.singleLabel] == F.otherLabel)
    }

    @Test("multi-choice cells follow option position, not selection order")
    func multiChoiceOrder() {
        let table = table
        #expect(table[0, column: F.multiLabel] == "Alone; Friends")
        #expect(table[2, column: F.multiLabel] == F.familyLabel)
    }

    @Test("an empty multi-choice answer is an empty cell")
    func emptyMulti() {
        #expect(table[1, column: F.multiLabel] == "")
    }

    @Test("a manual entry has empty prompt columns and prompted = no")
    func manualEntry() {
        let table = table
        #expect(table[2, column: "prompted"] == "no")
        #expect(table[2, column: "prompt_scheduled_at"] == "")
        #expect(table[2, column: "latency_seconds"] == "")
        #expect(table[2, column: "started_at"] == "2026-09-04T08:00:00-04:00")
        #expect(table[2, column: "completed_at"] == "2026-09-04T08:01:00-04:00")
    }

    @Test("a partial entry has empty completed_at and latency, unanswered cells empty")
    func partialEntry() {
        let table = table
        #expect(table[3, column: "prompted"] == "yes")
        #expect(table[3, column: "prompt_scheduled_at"] == "2026-09-05T09:00:00-04:00")
        #expect(table[3, column: "completed_at"] == "")
        #expect(table[3, column: "latency_seconds"] == "")
        #expect(table[3, column: F.scaleLabelNew] == "2")
        #expect(table[3, column: F.multiLabel] == "")
        #expect(table[3, column: F.yesNoLabel] == "")
        #expect(table[3, column: "Notes [textnote]"] == "")
        #expect(table[3, column: "Notes [archived]"] == "")
    }

    @Test("timestamps carry the calendar's offset")
    func timeZoneOffset() {
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let table = CSVTable(CSVExporter.wide(F.snapshot, calendar: kolkata))
        #expect(table[0, column: "prompt_scheduled_at"] == "2026-09-01T19:30:00+05:30")
        #expect(table[0, column: "latency_seconds"] == "180")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let utcTable = CSVTable(CSVExporter.wide(F.snapshot, calendar: utc))
        #expect(utcTable[0, column: "prompt_scheduled_at"] == "2026-09-01T14:00:00Z")
    }

    @Test("latency rounds toward zero, in both directions")
    func latencyRounding() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        snapshot.entries[0].entry.completedAt = F.prompt1At.addingTimeInterval(180.9)
        #expect(CSVTable(CSVExporter.wide(snapshot, calendar: F.calendar))[0, column: "latency_seconds"] == "180")
        snapshot.entries[0].entry.completedAt = F.prompt1At.addingTimeInterval(-1.5)
        #expect(CSVTable(CSVExporter.wide(snapshot, calendar: F.calendar))[0, column: "latency_seconds"] == "-1")
    }

    @Test("prompt columns follow promptId, not a stray or missing Prompt")
    func promptConsistency() {
        var snapshot = F.snapshot
        var dangling = F.exportEntry1
        dangling.prompt = nil
        var stray = F.exportEntry3
        stray.prompt = F.prompt("stray", at: F.prompt1At, status: .answered)
        snapshot.entries = [dangling, stray]
        let table = CSVTable(CSVExporter.wide(snapshot, calendar: F.calendar))
        #expect(table[0, column: "prompted"] == "yes")
        #expect(table[0, column: "prompt_scheduled_at"] == "")
        #expect(table[0, column: "latency_seconds"] == "")
        #expect(table[1, column: "prompted"] == "no")
        #expect(table[1, column: "prompt_scheduled_at"] == "")
        #expect(table[1, column: "latency_seconds"] == "")
    }

    @Test("an empty snapshot yields only the header row")
    func emptySnapshot() {
        let output = CSVExporter.wide(F.emptySnapshot, calendar: F.calendar)
        let expectedHeader = (fixedColumns + [
            F.scaleLabelNew, F.singleLabel, F.multiLabel, "\"Outside, or \"\"out\"\"?\"",
            "Notes [textnote]", "Notes [archived]",
        ]).joined(separator: ",")
        #expect(output == expectedHeader + "\r\n")
    }

    @Test("an entry with no answers is still a row")
    func entryWithoutAnswers() {
        var snapshot = F.emptySnapshot
        snapshot.entries = [F.exportEntry4]
        snapshot.entries[0].answers = []
        let table = CSVTable(CSVExporter.wide(snapshot, calendar: F.calendar))
        #expect(table.rows.count == 1)
        #expect(table[0, column: "entry_id"] == F.entry4)
        #expect(table.rows[0].count == table.header.count)
        #expect(table.rows[0].dropFirst(fixedColumns.count).allSatisfy { $0.isEmpty })
    }

    @Test("two answers to one question: the oldest wins, whatever the array order")
    func duplicateAnswers() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        let later = Answer(
            id: "dup", entryId: F.entry1, questionId: F.scaleQ, questionVersionId: F.scaleV1,
            answeredAt: F.entry1Answered.addingTimeInterval(30), value: .scale(9)
        )
        snapshot.entries[0].answers.append(later)
        let appended = CSVExporter.wide(snapshot, calendar: F.calendar)
        #expect(CSVTable(appended)[0, column: F.scaleLabelNew] == "5")
        snapshot.entries[0].answers.insert(later, at: 0)
        snapshot.entries[0].answers.removeLast()
        #expect(CSVExporter.wide(snapshot, calendar: F.calendar) == appended)
    }

    @Test("two answers with the same answeredAt are broken by ID, not array order")
    func duplicateAnswersTie() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        // "aaa-dup" sorts before the fixture's "entry-0001/scale-q-0001".
        let tied = Answer(
            id: "aaa-dup", entryId: F.entry1, questionId: F.scaleQ, questionVersionId: F.scaleV1,
            answeredAt: F.entry1Answered, value: .scale(9)
        )
        snapshot.entries[0].answers.append(tied)
        #expect(CSVTable(CSVExporter.wide(snapshot, calendar: F.calendar))[0, column: F.scaleLabelNew] == "9")
    }

    @Test("duplicate question and option IDs in the survey keep the first by position")
    func duplicateIds() {
        let output = CSVExporter.wide(F.duplicateIdsSnapshot, calendar: F.calendar)
        #expect(output == self.output)
        let table = CSVTable(output)
        #expect(table.header == self.table.header)
        #expect(table[0, column: F.scaleLabelNew] == "5")
        #expect(table[0, column: F.multiLabel] == "Alone; Friends")
    }

    @Test("an unknown option ID is written as the ID and does not crash")
    func unknownOption() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        snapshot.entries[0].answers = [
            F.answer(F.entry1, F.singleQ, F.singleV1, at: F.entry1Answered, .single(optionId: "ghost-1")),
            F.answer(F.entry1, F.multiQ, F.multiV1, at: F.entry1Answered,
                     .multi(optionIds: ["ghost-2", F.optFriends, "ghost-2"])),
        ]
        let table = CSVTable(CSVExporter.wide(snapshot, calendar: F.calendar))
        #expect(table[0, column: F.singleLabel] == "ghost-1")
        #expect(table[0, column: F.multiLabel] == "Friends; ghost-2")
    }

    @Test("an answer to an unknown question is skipped")
    func unknownQuestion() {
        var snapshot = F.snapshot
        snapshot.entries[0].answers.append(
            F.answer(F.entry1, "ghost-q", "ghost-v", at: F.entry1Answered, .text("orphan"))
        )
        let table = CSVTable(CSVExporter.wide(snapshot, calendar: F.calendar))
        #expect(table.header == self.table.header)
        #expect(table.rows[0].count == table.header.count)
        #expect(!table.rows[0].contains("orphan"))
    }

    @Test("output does not depend on the order of questions, options or answers")
    func inputOrderIndependent() {
        #expect(CSVExporter.wide(F.reorderedSnapshot, calendar: F.calendar) == output)
    }
}
