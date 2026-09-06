import Foundation
import GRDB

// Entries and answers are mutable: the runner autosaves an entry on every change, so
// `saveEntry` is an upsert. `deleteEntry` is destructive and ends with the vacuum step.

extension Store {
    /// Saves an entry and its answers in one transaction, replacing what was there.
    ///
    /// The entry row is replaced by value. Answers are reconciled by identifier:
    /// - a stored answer whose identifier is not in `answers` is deleted with its
    ///   `answerOption` rows;
    /// - a stored answer that is in `answers` keeps its stored `answeredAt` and takes
    ///   the new value and `questionVersionId`; its selections are deleted and
    ///   reinserted;
    /// - a new answer is inserted with the `answeredAt` the caller supplied.
    ///
    /// Every answer's `entryId` must equal `entry.id` and no two answers may share an
    /// identifier; anything else is a programming error and traps.
    public func saveEntry(_ entry: Entry, answers: [Answer]) throws {
        for answer in answers {
            precondition(answer.entryId == entry.id, "answer \(answer.id) does not belong to entry \(entry.id)")
        }
        precondition(Set(answers.map(\.id)).count == answers.count, "answers of entry \(entry.id) share an identifier")
        try dbQueue.write { db in
            try EntryRow(entry).save(db)
            let stored = try AnswerRow.fetchAll(
                db, sql: "SELECT * FROM answer WHERE entryId = ?", arguments: [entry.id])
            let storedById = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let keep = Set(answers.map(\.id))

            for old in stored where !keep.contains(old.id) {
                try deleteAnswerOptions(db, answerId: old.id)
                try old.delete(db)
            }
            for answer in answers {
                var row = AnswerRow(answer)
                if let old = storedById[answer.id] {
                    row.answeredAt = old.answeredAt
                    try row.update(db)
                    try deleteAnswerOptions(db, answerId: answer.id)
                } else {
                    try row.insert(db)
                }
                for optionId in Self.selectedOptionIds(of: answer.value) {
                    try AnswerOptionRow(answerId: answer.id, optionId: optionId).insert(db)
                }
            }
        }
    }

    /// Entries whose `startedAt` is in `from ..< to`, ascending. Nil bounds are
    /// unbounded; a nil `surveyId` means every survey.
    public func entries(surveyId: String?, from: Date?, to: Date?) throws -> [Entry] {
        try dbQueue.read { db in
            var clauses: [String] = []
            var arguments: StatementArguments = []
            if let surveyId {
                clauses.append("surveyId = ?")
                arguments += [surveyId]
            }
            if let from {
                clauses.append("startedAt >= ?")
                arguments += [from]
            }
            if let to {
                clauses.append("startedAt < ?")
                arguments += [to]
            }
            let filter = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ") + " "
            return try EntryRow.fetchAll(
                db, sql: "SELECT * FROM entry \(filter)ORDER BY startedAt, rowid", arguments: arguments
            ).map(Entry.init)
        }
    }

    /// The answers of one entry, ordered by `answeredAt`. Empty for an unknown entry.
    public func answers(entryId: String) throws -> [Answer] {
        try dbQueue.read { db in
            let rows = try AnswerRow.fetchAll(
                db, sql: "SELECT * FROM answer WHERE entryId = ? ORDER BY answeredAt, rowid",
                arguments: [entryId])
            let selections = try AnswerOptionRow.fetchAll(
                db, sql: "SELECT * FROM answerOption WHERE answerId IN (SELECT id FROM answer WHERE entryId = ?) ORDER BY rowid",
                arguments: [entryId])
            return try Self.makeAnswers(rows, selections: selections)
        }
    }

    /// Deletes the entry, its answers and their selections. The prompt row and its
    /// status are left untouched. Throws `notFound` for an unknown entry. Ends with the
    /// checkpoint and vacuum step.
    public func deleteEntry(_ id: String) throws {
        try dbQueue.write { db in
            guard try EntryRow.exists(db, key: id) else { throw StoreError.notFound }
            try db.execute(
                sql: "DELETE FROM answerOption WHERE answerId IN (SELECT id FROM answer WHERE entryId = ?)",
                arguments: [id])
            try db.execute(sql: "DELETE FROM answer WHERE entryId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM entry WHERE id = ?", arguments: [id])
        }
        try checkpointAndVacuum()
    }

    // MARK: Shared with export

    /// Builds answers from their rows and the selections of all of them, keeping each
    /// answer's selections in `answerOption` rowid order, which is the order they were
    /// saved in.
    static func makeAnswers(_ rows: [AnswerRow], selections: [AnswerOptionRow]) throws -> [Answer] {
        let optionIds = Dictionary(grouping: selections, by: \.answerId).mapValues { $0.map(\.optionId) }
        return try rows.map { row in
            Answer(
                id: row.id, entryId: row.entryId, questionId: row.questionId,
                questionVersionId: row.questionVersionId, answeredAt: row.answeredAt,
                value: try makeValue(row, optionIds: optionIds[row.id] ?? []))
        }
    }

    private static func makeValue(_ row: AnswerRow, optionIds: [String]) throws -> AnswerValue {
        switch row.kind {
        case .scale:
            guard let value = row.numericValue else { throw mismatch(row, "numericValue") }
            return .scale(value)
        case .singleChoice:
            guard let optionId = optionIds.first else { throw mismatch(row, "an answerOption row") }
            return .single(optionId: optionId)
        case .multiChoice:
            return .multi(optionIds: optionIds)
        case .yesNo:
            guard let value = row.boolValue else { throw mismatch(row, "boolValue") }
            return .yesNo(value)
        case .text:
            guard let value = row.textValue else { throw mismatch(row, "textValue") }
            return .text(value)
        }
    }

    /// A row that this store could not have written: its kind and its value columns
    /// disagree.
    private static func mismatch(_ row: AnswerRow, _ missing: String) -> DatabaseError {
        DatabaseError(
            resultCode: .SQLITE_MISMATCH,
            message: "answer \(row.id) has kind \(row.kind.rawValue) but no \(missing)")
    }

    /// The option identifiers a value selects, in the caller's order, without repeats.
    /// Non-choice values select nothing.
    static func selectedOptionIds(of value: AnswerValue) -> [String] {
        switch value {
        case .single(let optionId):
            return [optionId]
        case .multi(let optionIds):
            var seen: Set<String> = []
            return optionIds.filter { seen.insert($0).inserted }
        case .scale, .yesNo, .text:
            return []
        }
    }

    private func deleteAnswerOptions(_ db: Database, answerId: String) throws {
        try db.execute(sql: "DELETE FROM answerOption WHERE answerId = ?", arguments: [answerId])
    }
}

extension EntryRow {
    init(_ entry: Entry) {
        self.init(
            id: entry.id, surveyId: entry.surveyId, promptId: entry.promptId,
            startedAt: entry.startedAt, completedAt: entry.completedAt)
    }
}

extension Entry {
    init(_ row: EntryRow) {
        self.init(
            id: row.id, surveyId: row.surveyId, promptId: row.promptId,
            startedAt: row.startedAt, completedAt: row.completedAt)
    }
}

extension AnswerRow {
    init(_ answer: Answer) {
        var numericValue: Int?
        var textValue: String?
        var boolValue: Bool?
        switch answer.value {
        case .scale(let value): numericValue = value
        case .yesNo(let value): boolValue = value
        case .text(let value): textValue = value
        case .single, .multi: break
        }
        self.init(
            id: answer.id, entryId: answer.entryId, questionId: answer.questionId,
            questionVersionId: answer.questionVersionId, answeredAt: answer.answeredAt,
            kind: answer.value.kind, numericValue: numericValue, textValue: textValue,
            boolValue: boolValue)
    }
}
