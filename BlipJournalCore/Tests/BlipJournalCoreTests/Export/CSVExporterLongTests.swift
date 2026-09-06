import Foundation
import Testing
import OpenBlipCore

@Suite("CSVExporter.long")
struct CSVExporterLongTests {
    typealias F = ExportFixture

    private let columns = [
        "entry_id", "prompted", "prompt_scheduled_at", "started_at", "completed_at",
        "answered_at",
        "question_id", "question_kind", "question_label_at_time", "question_label_current",
        "option_id", "option_label_at_time", "option_label_current",
        "numeric_value", "bool_value", "text_value",
    ]

    private var output: String { CSVExporter.long(F.snapshot, calendar: F.calendar) }
    private var table: CSVTable { CSVTable(output) }

    private func field(_ row: [String], _ name: String) -> String? {
        guard let index = columns.firstIndex(of: name), index < row.count else { return nil }
        return row[index]
    }

    @Test("header is the documented column list")
    func header() {
        #expect(table.header == columns)
    }

    @Test("one row per non-choice answer, one per selected option, one for an empty multi")
    func rowCounts() {
        let table = table
        // entry 1: scale, single, multi x2, yesNo, text, archived scale
        #expect(table.rows(entry: F.entry1).count == 7)
        // entry 2: scale, single, empty multi, yesNo, text
        #expect(table.rows(entry: F.entry2).count == 5)
        // entry 3: scale, single, multi x1, yesNo, text
        #expect(table.rows(entry: F.entry3).count == 5)
        // entry 4: scale, single
        #expect(table.rows(entry: F.entry4).count == 2)
        #expect(table.rows.count == 19)
    }

    @Test("every row has as many fields as the header, embedded newlines included")
    func fieldCounts() {
        let table = table
        for row in table.rows {
            #expect(row.count == columns.count)
        }
        let family = table.rows(entry: F.entry3).first { field($0, "option_id") == F.optFamily }
        #expect(family.map { field($0, "option_label_current") } == F.familyLabel)
        let text = table.rows(entry: F.entry2).first { field($0, "question_id") == F.textQ }
        #expect(text.map { field($0, "text_value") } == "Line one\nline two")
    }

    @Test("commas, quotes and newlines are quoted in the raw text")
    func rawQuoting() {
        let output = output
        #expect(output.contains("\"Family\nmembers\""))
        #expect(output.contains("\"Line one\nline two\""))
        #expect(output.contains("\"Resting, quietly\""))
        #expect(output.contains("\"Other \"\"stuff\"\"\""))
        #expect(output.contains("\"He said \"\"hi\"\"\""))
        #expect(output.contains("\"Outside, or \"\"out\"\"?\""))
    }

    @Test("lines end with CRLF and the output has no BOM")
    func lineEndings() {
        let output = output
        #expect(output.hasSuffix("\r\n"))
        #expect(output.components(separatedBy: "\r\n").count - 1 == 20)
        #expect(output.unicodeScalars.first == "e")
        #expect(!output.unicodeScalars.contains("\u{FEFF}"))
    }

    @Test("rows are ordered by entry, then question position, then option position")
    func ordering() {
        let table = table
        #expect(table.rows.map { field($0, "entry_id") } == [
            Array(repeating: F.entry1, count: 7), Array(repeating: F.entry2, count: 5),
            Array(repeating: F.entry3, count: 5), Array(repeating: F.entry4, count: 2),
        ].flatMap { $0 })
        #expect(table.rows(entry: F.entry1).map { field($0, "question_id") } == [
            F.scaleQ, F.singleQ, F.multiQ, F.multiQ, F.yesNoQ, F.textQ, F.archivedQ,
        ])
        let multiRows = table.rows(entry: F.entry1).filter { field($0, "question_id") == F.multiQ }
        #expect(multiRows.map { field($0, "option_id") } == [F.optAlone, F.optFriends])
    }

    @Test("output does not depend on the order of questions, options or answers")
    func inputOrderIndependent() {
        #expect(CSVExporter.long(F.reorderedSnapshot, calendar: F.calendar) == output)
    }

    @Test("two answers to one question are both written, oldest first, whatever the array order")
    func duplicateAnswers() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        let later = Answer(
            id: "dup", entryId: F.entry1, questionId: F.scaleQ, questionVersionId: F.scaleV1,
            answeredAt: F.entry1Answered.addingTimeInterval(30), value: .scale(9)
        )
        snapshot.entries[0].answers.append(later)
        let appended = CSVExporter.long(snapshot, calendar: F.calendar)
        let rows = CSVTable(appended).rows(entry: F.entry1)
        #expect(rows.count == 8)
        #expect(rows.prefix(2).map { field($0, "question_id") } == [F.scaleQ, F.scaleQ])
        #expect(rows.prefix(2).map { field($0, "numeric_value") } == ["5", "9"])
        snapshot.entries[0].answers.insert(later, at: 0)
        snapshot.entries[0].answers.removeLast()
        #expect(CSVExporter.long(snapshot, calendar: F.calendar) == appended)
    }

    @Test("two answers with the same answeredAt are broken by ID, not array order")
    func duplicateAnswersTie() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        let tied = Answer(
            id: "aaa-dup", entryId: F.entry1, questionId: F.scaleQ, questionVersionId: F.scaleV1,
            answeredAt: F.entry1Answered, value: .scale(9)
        )
        snapshot.entries[0].answers.append(tied)
        let rows = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar)).rows(entry: F.entry1)
        #expect(rows.prefix(2).map { field($0, "numeric_value") } == ["9", "5"])
    }

    @Test("duplicate question and option IDs in the survey yield one answer row and one option row")
    func duplicateIds() {
        let output = CSVExporter.long(F.duplicateIdsSnapshot, calendar: F.calendar)
        #expect(output == self.output)
        let rows = CSVTable(output).rows(entry: F.entry1)
        #expect(rows.count == 7)
        #expect(field(rows[0], "question_label_current") == F.scaleLabelNew)
        #expect(rows.filter { field($0, "option_id") == F.optAlone }.count == 1)
        #expect(field(rows[2], "option_label_current") == F.aloneLabel)
    }

    @Test("an entry with no answers produces no rows")
    func entryWithoutAnswers() {
        var snapshot = F.emptySnapshot
        snapshot.entries = [F.exportEntry4]
        snapshot.entries[0].answers = []
        #expect(CSVExporter.long(snapshot, calendar: F.calendar) == columns.joined(separator: ",") + "\r\n")
    }

    @Test("entry columns repeat on every row of the entry")
    func entryColumns() {
        let table = table
        #expect(!table.rows(entry: F.entry1).isEmpty)
        #expect(!table.rows(entry: F.entry3).isEmpty)
        #expect(!table.rows(entry: F.entry4).isEmpty)
        for row in table.rows(entry: F.entry1) {
            #expect(field(row, "prompted") == "yes")
            #expect(field(row, "prompt_scheduled_at") == "2026-09-01T10:00:00-04:00")
            #expect(field(row, "started_at") == "2026-09-01T10:01:00-04:00")
            #expect(field(row, "completed_at") == "2026-09-01T10:03:00-04:00")
            #expect(field(row, "answered_at") == "2026-09-01T10:02:00-04:00")
        }
        for row in table.rows(entry: F.entry3) {
            #expect(field(row, "prompted") == "no")
            #expect(field(row, "prompt_scheduled_at") == "")
        }
        for row in table.rows(entry: F.entry4) {
            #expect(field(row, "prompted") == "yes")
            #expect(field(row, "completed_at") == "")
            #expect(field(row, "answered_at") == "2026-09-05T09:00:45-04:00")
        }
    }

    @Test("question_kind is the raw value")
    func questionKind() {
        let rows = table.rows(entry: F.entry1)
        #expect(rows.map { field($0, "question_kind") } == [
            "scale", "singleChoice", "multiChoice", "multiChoice", "yesNo", "text", "scale",
        ])
    }

    @Test("only the value column matching the kind is set; none for choices")
    func valueColumns() {
        let table = table
        for row in table.rows {
            let numeric = field(row, "numeric_value") ?? ""
            let bool = field(row, "bool_value") ?? ""
            let text = field(row, "text_value") ?? ""
            switch field(row, "question_kind") {
            case "scale":
                #expect(!numeric.isEmpty && bool.isEmpty && text.isEmpty, "\(row)")
            case "yesNo":
                #expect(numeric.isEmpty && !bool.isEmpty && text.isEmpty, "\(row)")
            case "text":
                #expect(numeric.isEmpty && bool.isEmpty && !text.isEmpty, "\(row)")
            default:
                #expect(numeric.isEmpty && bool.isEmpty && text.isEmpty, "\(row)")
            }
        }
        let e1 = table.rows(entry: F.entry1)
        #expect(field(e1[0], "numeric_value") == "5")
        #expect(field(e1[4], "bool_value") == "yes")
        #expect(field(e1[5], "text_value") == "Fine, thanks")
        #expect(field(e1[6], "numeric_value") == "3")
        #expect(field(e1[6], "question_label_at_time") == F.notesLabel)
        #expect(field(e1[6], "question_label_current") == F.notesLabel)
        #expect(field(table.rows(entry: F.entry2)[3], "bool_value") == "no")
    }

    @Test("an empty text answer is one row with every value column empty")
    func emptyText() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        snapshot.entries[0].answers = [
            F.answer(F.entry1, F.textQ, F.textV1, at: F.entry1Answered, .text("")),
        ]
        let table = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar))
        #expect(table.rows.count == 1)
        #expect(table[0, column: "question_id"] == F.textQ)
        #expect(table[0, column: "question_kind"] == "text")
        #expect(table[0, column: "numeric_value"] == "")
        #expect(table[0, column: "bool_value"] == "")
        #expect(table[0, column: "text_value"] == "")
    }

    @Test("choice rows carry option IDs and labels; scale rows have empty option columns")
    func optionColumns() {
        let e1 = table.rows(entry: F.entry1)
        #expect(field(e1[1], "option_id") == F.optWork)
        #expect(field(e1[2], "option_id") == F.optAlone)
        #expect(field(e1[2], "option_label_at_time") == F.aloneLabel)
        #expect(field(e1[2], "option_label_current") == F.aloneLabel)
        #expect(field(e1[3], "option_label_at_time") == F.friendsLabel)
        #expect(field(e1[3], "option_label_current") == F.friendsLabel)
        for index in [0, 4, 5, 6] {
            #expect(field(e1[index], "option_id") == "")
            #expect(field(e1[index], "option_label_at_time") == "")
            #expect(field(e1[index], "option_label_current") == "")
        }
    }

    @Test("an empty multi-choice answer is one row with empty option columns")
    func emptyMulti() {
        let rows = table.rows(entry: F.entry2).filter { field($0, "question_id") == F.multiQ }
        #expect(rows.count == 1)
        #expect(field(rows[0], "question_kind") == "multiChoice")
        #expect(field(rows[0], "question_label_current") == F.multiLabel)
        #expect(field(rows[0], "option_id") == "")
        #expect(field(rows[0], "option_label_at_time") == "")
        #expect(field(rows[0], "option_label_current") == "")
    }

    @Test("question label at time differs from current after a rename, for the older answer only")
    func questionRename() {
        let table = table
        let before = table.rows(entry: F.entry1)[0]
        #expect(field(before, "question_label_at_time") == F.scaleLabelOld)
        #expect(field(before, "question_label_current") == F.scaleLabelNew)
        let after = table.rows(entry: F.entry2)[0]
        #expect(field(after, "question_label_at_time") == F.scaleLabelNew)
        #expect(field(after, "question_label_current") == F.scaleLabelNew)
    }

    @Test("option label at time differs from current after a rename, for the older answer only")
    func optionRename() {
        let table = table
        let before = table.rows(entry: F.entry1)[1]
        #expect(field(before, "option_id") == F.optWork)
        #expect(field(before, "option_label_at_time") == F.workLabelOld)
        #expect(field(before, "option_label_current") == F.workLabelNew)
        let after = table.rows(entry: F.entry2)[1]
        #expect(field(after, "option_id") == F.optWork)
        #expect(field(after, "option_label_at_time") == F.workLabelNew)
        #expect(field(after, "option_label_current") == F.workLabelNew)
    }

    @Test("the version ID wins over the history when both are present")
    func versionPathWins() {
        var snapshot = F.snapshot
        snapshot.questionVersionLabels[F.scaleV1] = "Pinned wording"
        let table = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar))
        #expect(field(table.rows(entry: F.entry1)[0], "question_label_at_time") == "Pinned wording")
        // Entry 2 uses a different version and is unaffected.
        #expect(field(table.rows(entry: F.entry2)[0], "question_label_at_time") == F.scaleLabelNew)
    }

    @Test("an unknown version ID falls back to the history at answeredAt")
    func historyPath() {
        // Entry 3's scale answer has no version row and was given after the rename.
        let table = table
        let after = table.rows(entry: F.entry3)[0]
        #expect(field(after, "question_label_at_time") == F.scaleLabelNew)

        // Move it before the rename: the history now yields the old label.
        var snapshot = F.snapshot
        let earlier = F.renamedAt.addingTimeInterval(-3600)
        snapshot.entries[2].answers = snapshot.entries[2].answers.map { answer in
            var copy = answer
            copy.answeredAt = earlier
            return copy
        }
        let moved = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar))
        let row = moved.rows(entry: F.entry3)[0]
        #expect(field(row, "question_label_at_time") == F.scaleLabelOld)
        #expect(field(row, "question_label_current") == F.scaleLabelNew)
    }

    @Test("with no version row and no history, the current label is used")
    func currentLabelFallback() {
        var snapshot = F.snapshot
        snapshot.questionVersionLabels = [:]
        snapshot.questionLabelHistory = [:]
        snapshot.optionLabelHistory = [:]
        let table = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar))
        let scale = table.rows(entry: F.entry1)[0]
        #expect(field(scale, "question_label_at_time") == F.scaleLabelNew)
        let work = table.rows(entry: F.entry1)[1]
        #expect(field(work, "option_label_at_time") == F.workLabelNew)
    }

    @Test("timestamps carry the calendar's offset")
    func timeZoneOffset() {
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let table = CSVTable(CSVExporter.long(F.snapshot, calendar: kolkata))
        #expect(field(table.rows[0], "answered_at") == "2026-09-01T19:32:00+05:30")
    }

    @Test("an empty snapshot yields only the header row")
    func emptySnapshot() {
        let output = CSVExporter.long(F.emptySnapshot, calendar: F.calendar)
        #expect(output == columns.joined(separator: ",") + "\r\n")
    }

    @Test("an unknown option ID is written as the ID and does not crash")
    func unknownOption() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        snapshot.entries[0].answers = [
            F.answer(F.entry1, F.singleQ, F.singleV1, at: F.entry1Answered, .single(optionId: "ghost-1")),
            F.answer(F.entry1, F.multiQ, F.multiV1, at: F.entry1Answered,
                     .multi(optionIds: ["ghost-2", F.optFriends])),
        ]
        let table = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar))
        #expect(table.rows.count == 3)
        #expect(field(table.rows[0], "option_id") == "ghost-1")
        #expect(field(table.rows[0], "option_label_at_time") == "ghost-1")
        #expect(field(table.rows[0], "option_label_current") == "ghost-1")
        #expect(table.rows.dropFirst().map { field($0, "option_id") } == [F.optFriends, "ghost-2"])
    }

    @Test("an answer to an unknown question is written after the known ones with empty labels")
    func unknownQuestion() {
        var snapshot = F.snapshot
        snapshot.entries[0].answers.insert(
            F.answer(F.entry1, "ghost-q", "ghost-v", at: F.entry1Answered, .text("orphan")), at: 0
        )
        let table = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar))
        let rows = table.rows(entry: F.entry1)
        #expect(rows.count == 8)
        let orphan = rows[7]
        #expect(field(orphan, "question_id") == "ghost-q")
        #expect(field(orphan, "question_kind") == "text")
        #expect(field(orphan, "question_label_at_time") == "")
        #expect(field(orphan, "question_label_current") == "")
        #expect(field(orphan, "text_value") == "orphan")
        #expect(field(orphan, "answered_at") == "2026-09-01T10:02:00-04:00")

        // Even a resolvable version ID or history does not fill the label columns.
        snapshot.questionVersionLabels["ghost-v"] = "Ghost wording"
        snapshot.questionLabelHistory["ghost-q"] = [LabelVersion(label: "Ghost history", validFrom: F.createdAt)]
        let resolvable = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar)).rows(entry: F.entry1)[7]
        #expect(field(resolvable, "question_label_at_time") == "")
        #expect(field(resolvable, "question_label_current") == "")
    }

    @Test("a choice answer to an unknown question still resolves its option columns")
    func unknownQuestionChoice() {
        var snapshot = F.snapshot
        snapshot.entries = [F.exportEntry1]
        snapshot.entries[0].answers = [
            F.answer(F.entry1, "ghost-q", "ghost-v", at: F.entry1Answered, .multi(optionIds: [F.optWork, "ghost-o"])),
        ]
        let rows = CSVTable(CSVExporter.long(snapshot, calendar: F.calendar)).rows(entry: F.entry1)
        #expect(rows.count == 2)
        #expect(rows.map { field($0, "question_kind") } == ["multiChoice", "multiChoice"])
        #expect(rows.map { field($0, "question_label_current") } == ["", ""])
        #expect(rows.map { field($0, "option_id") } == [F.optWork, "ghost-o"])
        #expect(field(rows[0], "option_label_at_time") == F.workLabelOld)
        #expect(field(rows[0], "option_label_current") == F.workLabelNew)
        #expect(field(rows[1], "option_label_current") == "ghost-o")
    }
}
