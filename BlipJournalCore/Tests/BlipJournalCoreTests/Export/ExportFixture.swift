import Foundation
import BlipJournalCore

/// A hand-built snapshot that exercises every rule of the CSV exporters: two prompted
/// entries, one manual, one partial; a scale, single, multi, yes/no and text question;
/// an archived question with an old answer; a renamed question and a renamed option
/// with answers on both sides of the rename; a multi-choice answer with zero
/// selections; labels with commas, quotes and newlines; a non-UTC time zone.
enum ExportFixture {
    static let timeZone = TimeZone(identifier: "America/Toronto")!

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    // MARK: Identifiers

    static let surveyId = "survey-0001"
    static let scaleQ = "scale-q-0001"
    static let singleQ = "single-q-0002"
    static let multiQ = "multi-q-0003"
    static let yesNoQ = "yesno-q-0004"
    static let textQ = "textnote-q-0005"
    static let archivedQ = "archived-q-0006"

    static let scaleV1 = "scale-v1"
    static let scaleV2 = "scale-v2"
    static let singleV1 = "single-v1"
    static let multiV1 = "multi-v1"
    static let yesNoV1 = "yesno-v1"
    static let textV1 = "text-v1"
    static let archivedV1 = "archived-v1"

    static let optWork = "opt-work"
    static let optRest = "opt-rest"
    static let optOther = "opt-other"
    static let optAlone = "opt-alone"
    static let optFriends = "opt-friends"
    static let optFamily = "opt-family"

    static let entry1 = "entry-0001"
    static let entry2 = "entry-0002"
    static let entry3 = "entry-0003"
    static let entry4 = "entry-0004"

    // MARK: Labels

    static let surveyName = "Daily mood"
    static let scaleLabelOld = "How do you feel?"
    static let scaleLabelNew = "How are you feeling?"
    static let singleLabel = "What are you doing?"
    static let multiLabel = "Who are you with?"
    static let yesNoLabel = "Outside, or \"out\"?"
    static let notesLabel = "Notes"
    static let workLabelOld = "Work"
    static let workLabelNew = "Working"
    static let restLabel = "Resting, quietly"
    static let otherLabel = "Other \"stuff\""
    static let aloneLabel = "Alone"
    static let friendsLabel = "Friends"
    static let familyLabel = "Family\nmembers"

    // MARK: Dates

    static let createdAt = date(2026, 8, 1, 9, 0)
    static let renamedAt = date(2026, 9, 2, 12, 0)

    static let prompt1At = date(2026, 9, 1, 10, 0)
    static let entry1Started = date(2026, 9, 1, 10, 1)
    static let entry1Answered = date(2026, 9, 1, 10, 2)
    static let entry1Completed = date(2026, 9, 1, 10, 3)

    static let prompt2At = date(2026, 9, 3, 14, 0)
    static let entry2Started = date(2026, 9, 3, 14, 0, 30)
    static let entry2Answered = date(2026, 9, 3, 14, 1)
    static let entry2Completed = date(2026, 9, 3, 14, 2, 15)

    static let entry3Started = date(2026, 9, 4, 8, 0)
    static let entry3Answered = date(2026, 9, 4, 8, 0, 30)
    static let entry3Completed = date(2026, 9, 4, 8, 1)

    static let prompt4At = date(2026, 9, 5, 9, 0)
    static let entry4Started = date(2026, 9, 5, 9, 0, 30)
    static let entry4Answered = date(2026, 9, 5, 9, 0, 45)

    // MARK: Survey

    static var survey: Survey {
        // Deliberately out of position order: the exporter must sort.
        Survey(
            id: surveyId,
            name: surveyName,
            createdAt: createdAt,
            questions: [
                Question(id: multiQ, kind: .multiChoice, label: multiLabel, position: 2, options: [
                    ChoiceOption(id: optFamily, label: familyLabel, position: 2),
                    ChoiceOption(id: optAlone, label: aloneLabel, position: 0),
                    ChoiceOption(id: optFriends, label: friendsLabel, position: 1),
                ]),
                Question(id: scaleQ, kind: .scale, label: scaleLabelNew, position: 0,
                         isRequired: true, scale: ScaleConfig()),
                Question(id: archivedQ, kind: .scale, label: notesLabel, position: 5,
                         isArchived: true, scale: ScaleConfig()),
                Question(id: yesNoQ, kind: .yesNo, label: yesNoLabel, position: 3),
                Question(id: textQ, kind: .text, label: notesLabel, position: 4),
                Question(id: singleQ, kind: .singleChoice, label: singleLabel, position: 1,
                         allowsCustomOptions: true, options: [
                    ChoiceOption(id: optOther, label: otherLabel, position: 2),
                    ChoiceOption(id: optWork, label: workLabelNew, position: 0),
                    ChoiceOption(id: optRest, label: restLabel, position: 1),
                ]),
            ]
        )
    }

    // MARK: Entries

    static func prompt(_ id: String, at scheduledAt: Date, status: PromptStatus) -> Prompt {
        Prompt(
            id: id, surveyId: surveyId, day: "", scheduledAt: scheduledAt,
            expiresAt: scheduledAt.addingTimeInterval(20 * 60), status: status,
            respondedAt: status == .pending ? nil : scheduledAt.addingTimeInterval(60)
        )
    }

    static func answer(
        _ entryId: String, _ questionId: String, _ versionId: String, at answeredAt: Date, _ value: AnswerValue
    ) -> Answer {
        Answer(
            id: "\(entryId)/\(questionId)", entryId: entryId, questionId: questionId,
            questionVersionId: versionId, answeredAt: answeredAt, value: value
        )
    }

    /// Prompted, completed, answered before the renames. Every question answered,
    /// including the archived one. Multi selection given out of position order.
    static var exportEntry1: ExportEntry {
        ExportEntry(
            entry: Entry(id: entry1, surveyId: surveyId, promptId: "prompt-1",
                         startedAt: entry1Started, completedAt: entry1Completed),
            prompt: prompt("prompt-1", at: prompt1At, status: .answered),
            answers: [
                answer(entry1, scaleQ, scaleV1, at: entry1Answered, .scale(5)),
                answer(entry1, singleQ, singleV1, at: entry1Answered, .single(optionId: optWork)),
                answer(entry1, multiQ, multiV1, at: entry1Answered, .multi(optionIds: [optFriends, optAlone])),
                answer(entry1, yesNoQ, yesNoV1, at: entry1Answered, .yesNo(true)),
                answer(entry1, textQ, textV1, at: entry1Answered, .text("Fine, thanks")),
                answer(entry1, archivedQ, archivedV1, at: entry1Answered, .scale(3)),
            ]
        )
    }

    /// Prompted, completed, answered after the renames. Empty multi selection, text
    /// with an embedded newline.
    static var exportEntry2: ExportEntry {
        ExportEntry(
            entry: Entry(id: entry2, surveyId: surveyId, promptId: "prompt-2",
                         startedAt: entry2Started, completedAt: entry2Completed),
            prompt: prompt("prompt-2", at: prompt2At, status: .answered),
            answers: [
                answer(entry2, scaleQ, scaleV2, at: entry2Answered, .scale(6)),
                answer(entry2, singleQ, singleV1, at: entry2Answered, .single(optionId: optWork)),
                answer(entry2, multiQ, multiV1, at: entry2Answered, .multi(optionIds: [])),
                answer(entry2, yesNoQ, yesNoV1, at: entry2Answered, .yesNo(false)),
                answer(entry2, textQ, textV1, at: entry2Answered, .text("Line one\nline two")),
            ]
        )
    }

    /// Manual, completed. The scale answer carries an unknown version ID so the label
    /// history path is used.
    static var exportEntry3: ExportEntry {
        ExportEntry(
            entry: Entry(id: entry3, surveyId: surveyId, promptId: nil,
                         startedAt: entry3Started, completedAt: entry3Completed),
            prompt: nil,
            answers: [
                answer(entry3, scaleQ, "scale-v-missing", at: entry3Answered, .scale(4)),
                answer(entry3, singleQ, singleV1, at: entry3Answered, .single(optionId: optRest)),
                answer(entry3, multiQ, multiV1, at: entry3Answered, .multi(optionIds: [optFamily])),
                answer(entry3, yesNoQ, yesNoV1, at: entry3Answered, .yesNo(true)),
                answer(entry3, textQ, textV1, at: entry3Answered, .text("He said \"hi\"")),
            ]
        )
    }

    /// Prompted, partial: no `completedAt`, only two answers.
    static var exportEntry4: ExportEntry {
        ExportEntry(
            entry: Entry(id: entry4, surveyId: surveyId, promptId: "prompt-4",
                         startedAt: entry4Started, completedAt: nil),
            prompt: prompt("prompt-4", at: prompt4At, status: .pending),
            answers: [
                answer(entry4, scaleQ, scaleV2, at: entry4Answered, .scale(2)),
                answer(entry4, singleQ, singleV1, at: entry4Answered, .single(optionId: optOther)),
            ]
        )
    }

    static var entries: [ExportEntry] { [exportEntry1, exportEntry2, exportEntry3, exportEntry4] }

    /// The snapshot with `survey.questions`, every `options` array, the answers of
    /// every entry and every multi-choice selection reversed. Same data, every
    /// unordered input in a different order; the exporters must produce identical
    /// output. `entries` keeps its order, which is meaningful.
    static var reorderedSnapshot: ExportSnapshot {
        var snapshot = snapshot
        snapshot.survey.questions = snapshot.survey.questions.reversed().map { question in
            var copy = question
            copy.options.reverse()
            return copy
        }
        snapshot.entries = snapshot.entries.map { exportEntry in
            var copy = exportEntry
            copy.answers = copy.answers.reversed().map { answer in
                var copy = answer
                if case .multi(let optionIds) = answer.value {
                    copy.value = .multi(optionIds: optionIds.reversed())
                }
                return copy
            }
            return copy
        }
        return snapshot
    }

    /// The snapshot with the scale question and the "alone" option each listed twice,
    /// the duplicate carrying a different label and a higher position. Entry 1 selects
    /// "alone", so the duplicate is exercised by the fixture's own answers.
    static var duplicateIdsSnapshot: ExportSnapshot {
        var snapshot = snapshot
        let extraQuestion = Question(id: scaleQ, kind: .scale, label: "Duplicate", position: 9, scale: ScaleConfig())
        snapshot.survey.questions.insert(extraQuestion, at: 0)
        let multiIndex = snapshot.survey.questions.firstIndex { $0.id == multiQ }!
        snapshot.survey.questions[multiIndex].options.insert(
            ChoiceOption(id: optAlone, label: "Duplicate option", position: 9), at: 0
        )
        return snapshot
    }

    // MARK: Snapshot

    static var questionLabelHistory: [String: [LabelVersion]] {
        [
            scaleQ: [
                LabelVersion(label: scaleLabelOld, validFrom: createdAt),
                LabelVersion(label: scaleLabelNew, validFrom: renamedAt),
            ],
            singleQ: [LabelVersion(label: singleLabel, validFrom: createdAt)],
            multiQ: [LabelVersion(label: multiLabel, validFrom: createdAt)],
            yesNoQ: [LabelVersion(label: yesNoLabel, validFrom: createdAt)],
            textQ: [LabelVersion(label: notesLabel, validFrom: createdAt)],
            archivedQ: [LabelVersion(label: notesLabel, validFrom: createdAt)],
        ]
    }

    static var optionLabelHistory: [String: [LabelVersion]] {
        [
            optWork: [
                LabelVersion(label: workLabelOld, validFrom: createdAt),
                LabelVersion(label: workLabelNew, validFrom: renamedAt),
            ],
            optRest: [LabelVersion(label: restLabel, validFrom: createdAt)],
            optOther: [LabelVersion(label: otherLabel, validFrom: createdAt)],
            optAlone: [LabelVersion(label: aloneLabel, validFrom: createdAt)],
            optFriends: [LabelVersion(label: friendsLabel, validFrom: createdAt)],
            optFamily: [LabelVersion(label: familyLabel, validFrom: createdAt)],
        ]
    }

    static var questionVersionLabels: [String: String] {
        [
            scaleV1: scaleLabelOld,
            scaleV2: scaleLabelNew,
            singleV1: singleLabel,
            multiV1: multiLabel,
            yesNoV1: yesNoLabel,
            textV1: notesLabel,
            archivedV1: notesLabel,
        ]
    }

    static var snapshot: ExportSnapshot {
        ExportSnapshot(
            survey: survey,
            entries: entries,
            questionLabelHistory: questionLabelHistory,
            optionLabelHistory: optionLabelHistory,
            questionVersionLabels: questionVersionLabels
        )
    }

    /// The survey with its histories but no entries.
    static var emptySnapshot: ExportSnapshot {
        var snapshot = snapshot
        snapshot.entries = []
        return snapshot
    }
}

// MARK: - Minimal CSV reader

/// Just enough RFC 4180 parsing to check the exporters' output: quoted fields, doubled
/// quotes, embedded CR and LF inside quotes, CRLF or LF between records. Malformed
/// input (a quote inside an unquoted field, or text after a closing quote) poisons the
/// field with a marker so any assertion on it fails rather than passing by accident.
enum CSVReader {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var quoteClosed = false
        var scalars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil

        func next() -> Unicode.Scalar? {
            if let scalar = pending {
                pending = nil
                return scalar
            }
            return scalars.next()
        }

        func endField() {
            row.append(field)
            field = ""
            quoteClosed = false
        }

        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while let scalar = next() {
            if inQuotes {
                if scalar == "\"" {
                    if let following = next() {
                        if following == "\"" {
                            field.unicodeScalars.append("\"")
                        } else {
                            inQuotes = false
                            quoteClosed = true
                            pending = following
                        }
                    } else {
                        inQuotes = false
                        quoteClosed = true
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where field.isEmpty && !quoteClosed:
                inQuotes = true
            case ",":
                endField()
            case "\r":
                if let following = next(), following != "\n" {
                    pending = following
                }
                endRow()
            case "\n":
                endRow()
            default:
                if quoteClosed {
                    field += "<text after closing quote>"
                }
                if scalar == "\"" {
                    field += "<quote in unquoted field>"
                }
                field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty || quoteClosed {
            endRow()
        }
        return rows
    }
}

/// A parsed CSV document with header-based access.
///
/// Lookups return nil rather than trapping on a missing column or a short row, so one
/// wrong header fails its own assertion instead of killing the whole test process.
struct CSVTable {
    let header: [String]
    let rows: [[String]]

    init(_ text: String) {
        let parsed = CSVReader.parse(text)
        header = parsed.first ?? []
        rows = Array(parsed.dropFirst())
    }

    func column(_ name: String) -> Int? {
        header.firstIndex(of: name)
    }

    subscript(row: Int, column name: String) -> String? {
        guard row < rows.count, let index = column(name), index < rows[row].count else { return nil }
        return rows[row][index]
    }

    /// The rows whose `entry_id` equals `entryId`, in document order.
    func rows(entry entryId: String) -> [[String]] {
        guard let index = column("entry_id") else { return [] }
        return rows.filter { index < $0.count && $0[index] == entryId }
    }
}
