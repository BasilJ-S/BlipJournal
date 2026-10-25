import Foundation
import GRDB

// Answering a prompt from its notification, and what happens to such an entry when its
// prompt expires. Both write an entry and its prompt's status in one transaction.

/// What `Store.saveNotificationAnswer` did with an answer picked from a notification.
public enum NotificationAnswerOutcome: Sendable, Equatable {
    /// Saved into the prompt's entry, which stays open for the remaining questions.
    case saved(entryId: String)
    /// The prompt had expired. Nothing was saved; a prompt still pending was settled the
    /// way the planner settles an expired prompt (see `settleExpiredPrompts`).
    case expired
    /// The prompt is already answered: its entry is complete, or it was answered and the
    /// entry since deleted. Nothing was saved.
    case alreadyAnswered
    /// The prompt or its survey no longer exists, or the survey's first question is no
    /// longer the one the notification offered, or no longer offers that answer. Nothing
    /// was saved.
    case unavailable
}

extension Store {
    /// Saves the answer behind `actionIdentifier` to the first question of the prompt's
    /// survey, as part of the prompt's entry.
    ///
    /// `questionId` is the question the notification was scheduled for. The answer is
    /// saved only when that is still the survey's first active question and
    /// ``NotificationAnswers`` still offers the action; otherwise the outcome is
    /// `unavailable`, so an edit made after the notification was scheduled can never
    /// record an answer against a question the person was not offered.
    ///
    /// - A pending, unexpired prompt with no entry gets a new entry, `startedAt` and the
    ///   answer's `answeredAt` both `now`, exactly as the runner would have stamped them.
    /// - A pending, unexpired prompt with an unfinished entry (opened in the app first, or
    ///   answered from a notification before) gets the answer added to that entry, or
    ///   replacing that question's answer while keeping its identifier and first
    ///   `answeredAt`, as the runner does.
    /// - Either way the entry is marked `answeredFromNotification`, stays incomplete, and
    ///   the prompt stays pending, so the rest of the survey can be answered in the app
    ///   until the prompt expires.
    /// - An expired prompt saves nothing and is settled (marked missed, unless it already
    ///   has a notification entry that can be completed); a prompt with any other outcome,
    ///   or a completed entry, saves nothing.
    ///
    /// One transaction: the prompt, the survey and the entry are read and written together.
    public func saveNotificationAnswer(
        promptId: String, questionId: String, actionIdentifier: String, now: Date = Date()
    ) throws -> NotificationAnswerOutcome {
        try dbQueue.write { db in
            guard let promptRow = try PromptRow.fetchOne(db, key: promptId) else { return .unavailable }
            let prompt = Prompt(promptRow)
            let rows = try DefinitionRows.load(db, surveyId: prompt.surveyId)
            guard let surveyRow = rows.surveys.first, let survey = rows.survey(for: surveyRow) else {
                return .unavailable
            }
            let existing = try EntryRow.fetchOne(
                db, sql: "SELECT * FROM entry WHERE promptId = ? ORDER BY rowid LIMIT 1", arguments: [promptId]
            ).map(Entry.init)

            if existing?.completedAt != nil { return .alreadyAnswered }
            switch prompt.status {
            case .answered: return .alreadyAnswered
            case .missed, .dismissed: return .expired
            case .pending: break
            }
            if prompt.isExpired(at: now) {
                try settleExpiredPrompt(db, prompt, now: now)
                return .expired
            }

            guard let offered = NotificationAnswers(survey: survey), offered.questionId == questionId,
                  let value = offered.value(forActionIdentifier: actionIdentifier),
                  let versionId = rows.questionVersions[questionId]?.last?.id
            else { return .unavailable }

            var entry = existing ?? Entry(surveyId: survey.id, promptId: prompt.id, startedAt: now)
            entry.answeredFromNotification = true
            var entryAnswers = try existing.map { try self.answers(db, entryId: $0.id) } ?? []
            let previous = entryAnswers.firstIndex { $0.questionId == questionId }
            let answer = Answer(
                id: previous.map { entryAnswers[$0].id } ?? Identifier.make(),
                entryId: entry.id, questionId: questionId, questionVersionId: versionId,
                answeredAt: previous.map { entryAnswers[$0].answeredAt } ?? now, value: value)
            if let previous { entryAnswers[previous] = answer } else { entryAnswers.append(answer) }
            try saveEntry(db, entry, answers: entryAnswers)
            return .saved(entryId: entry.id)
        }
    }

    /// Settles prompts the planner found expired while still pending.
    ///
    /// A prompt whose entry was started from its notification
    /// (`Entry.answeredFromNotification`) and is still unfinished is closed rather than
    /// missed when every active required question of its survey has an answer: the entry
    /// is completed at its latest `answeredAt`, and the prompt is marked answered at that
    /// same moment, so its latency is measured to the last answer the person gave. Every
    /// other prompt is marked missed at `now`, exactly as before. Unknown identifiers and
    /// prompts no longer pending are skipped.
    public func settleExpiredPrompts(_ ids: [String], now: Date) throws {
        guard !ids.isEmpty else { return }
        try dbQueue.write { db in
            for id in ids {
                guard let row = try PromptRow.fetchOne(db, key: id), row.status == .pending else { continue }
                try settleExpiredPrompt(db, Prompt(row), now: now)
            }
        }
    }

    /// Closes or misses one expired, pending prompt inside the caller's transaction. See
    /// `settleExpiredPrompts`.
    private func settleExpiredPrompt(_ db: Database, _ prompt: Prompt, now: Date) throws {
        if var entry = try EntryRow.fetchOne(
            db, sql: "SELECT * FROM entry WHERE promptId = ? ORDER BY rowid LIMIT 1", arguments: [prompt.id]
        ).map(Entry.init), entry.answeredFromNotification, entry.completedAt == nil {
            let rows = try DefinitionRows.load(db, surveyId: prompt.surveyId)
            let stored = try self.answers(db, entryId: entry.id)
            let answered = Set(stored.map(\.questionId))
            if let surveyRow = rows.surveys.first, let survey = rows.survey(for: surveyRow),
               survey.activeQuestions.allSatisfy({ !$0.isRequired || answered.contains($0.id) }),
               let lastAnswer = stored.map(\.answeredAt).max() {
                entry.completedAt = lastAnswer
                try saveEntry(db, entry, answers: stored)
                try setPromptStatus(db, prompt.id, .answered, respondedAt: lastAnswer)
                return
            }
        }
        try setPromptStatus(db, prompt.id, .missed, respondedAt: now)
    }

    private func setPromptStatus(_ db: Database, _ id: String, _ status: PromptStatus, respondedAt: Date) throws {
        try db.execute(
            sql: "UPDATE prompt SET status = ?, respondedAt = ? WHERE id = ?",
            arguments: [status, respondedAt, id])
    }
}
