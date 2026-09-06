import Foundation
import GRDB

// Prompts are mutable rows: their status moves as the person responds or the prompt
// expires. They carry no user text, so deleting them needs no vacuum.

extension Store {
    /// Every prompt with `status`, or every prompt when nil, ordered by `scheduledAt`.
    public func prompts(status: PromptStatus?) throws -> [Prompt] {
        try dbQueue.read { db in
            let rows: [PromptRow]
            if let status {
                rows = try PromptRow.fetchAll(
                    db, sql: "SELECT * FROM prompt WHERE status = ? ORDER BY scheduledAt, rowid",
                    arguments: [status])
            } else {
                rows = try PromptRow.fetchAll(db, sql: "SELECT * FROM prompt ORDER BY scheduledAt, rowid")
            }
            return rows.map(Prompt.init)
        }
    }

    /// Every prompt of one survey on one local day, ordered by `scheduledAt`.
    public func prompts(surveyId: String, day: String) throws -> [Prompt] {
        try dbQueue.read { db in
            try PromptRow.fetchAll(
                db, sql: "SELECT * FROM prompt WHERE surveyId = ? AND day = ? ORDER BY scheduledAt, rowid",
                arguments: [surveyId, day]
            ).map(Prompt.init)
        }
    }

    /// Inserts every prompt in one transaction. A prompt naming an unknown survey fails
    /// the whole batch.
    public func insertPrompts(_ prompts: [Prompt]) throws {
        try dbQueue.write { db in
            for prompt in prompts {
                try PromptRow(prompt).insert(db)
            }
        }
    }

    /// Updates only `status` and `respondedAt`. Throws `notFound` for an unknown prompt.
    public func setPromptStatus(_ id: String, _ status: PromptStatus, respondedAt: Date?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE prompt SET status = ?, respondedAt = ? WHERE id = ?",
                arguments: [status, respondedAt, id])
            guard db.changesCount > 0 else { throw StoreError.notFound }
        }
    }

    /// Deletes the survey's pending prompts scheduled strictly after `after`. Nothing
    /// else: past pending prompts, prompts with an outcome, other surveys' prompts, and a
    /// pending prompt that already has an entry (the runner is open on it) all stay.
    public func deleteFuturePendingPrompts(surveyId: String, after: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM prompt
                    WHERE surveyId = ? AND status = ? AND scheduledAt > ?
                      AND id NOT IN (SELECT promptId FROM entry WHERE promptId IS NOT NULL)
                    """,
                arguments: [surveyId, PromptStatus.pending, after])
        }
    }
}

extension PromptRow {
    init(_ prompt: Prompt) {
        self.init(
            id: prompt.id, surveyId: prompt.surveyId, day: prompt.day,
            scheduledAt: prompt.scheduledAt, expiresAt: prompt.expiresAt,
            status: prompt.status, respondedAt: prompt.respondedAt)
    }
}

extension Prompt {
    init(_ row: PromptRow) {
        self.init(
            id: row.id, surveyId: row.surveyId, day: row.day,
            scheduledAt: row.scheduledAt, expiresAt: row.expiresAt,
            status: row.status, respondedAt: row.respondedAt)
    }
}
