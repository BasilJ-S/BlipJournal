import Foundation
import Testing
import BlipJournalCore

@Suite("Store notification answers")
struct StoreNotificationAnswersTests {
    private let t = Fixture.at

    /// A survey that opens with a required yes/no question, then an optional 1 to 7 scale
    /// and an optional note. Prompts expire twenty minutes after they fire.
    private func seeded(secondRequired: Bool = false) throws -> (Store, Survey, Question, Question) {
        let store = try Store.inMemory()
        let survey = try store.createSurvey(
            name: "Sleep", sampling: .default,
            questions: [
                Question(kind: .yesNo, label: "Slept well?", position: 0, isRequired: true),
                Question(kind: .scale, label: "Energy", position: 1, isRequired: secondRequired,
                         scale: ScaleConfig(min: 1, max: 7)),
                Question(kind: .text, label: "Anything else?", position: 2),
            ],
            now: t(0))
        let first = try survey.question(labelled: "Slept well?")
        let second = try survey.question(labelled: "Energy")
        return (store, survey, first, second)
    }

    private func action(_ survey: Survey, _ value: AnswerValue) throws -> String {
        let offered = try #require(NotificationAnswers(survey: survey))
        return try #require(offered.choices.first { $0.value == value }).actionIdentifier
    }

    private func entry(_ store: Store, promptId: String) throws -> Entry? {
        try store.entries(surveyId: nil, from: nil, to: nil).first { $0.promptId == promptId }
    }

    private func prompt(_ store: Store, _ id: String) throws -> Prompt? {
        try store.prompts(status: nil).first { $0.id == id }
    }

    // MARK: Saving (R2, R3)

    @Test("an answer to a pending prompt saves an open entry with the prompt's metadata, flagged")
    func savesOpenEntry() throws {
        let (store, survey, first, _) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])

        let outcome = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: t(160))

        let saved = try #require(try entry(store, promptId: p.id))
        #expect(outcome == .saved(entryId: saved.id))
        #expect(saved.surveyId == survey.id)
        #expect(saved.startedAt == t(160))
        #expect(saved.completedAt == nil)
        #expect(saved.answeredFromNotification)
        let answers = try store.answers(entryId: saved.id)
        #expect(answers.map(\.value) == [.yesNo(true)])
        #expect(answers.first?.answeredAt == t(160))
        #expect(answers.first?.questionVersionId == (try store.currentQuestionVersionIds(surveyId: survey.id))[first.id])
        // The prompt stays pending: the rest of the survey can still be answered.
        #expect(try prompt(store, p.id)?.status == .pending)
    }

    @Test("a partly answered entry continues: the app's later answers join the same entry")
    func continuesEntry() throws {
        let (store, survey, first, second) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        _ = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(false)), now: t(160))
        var saved = try #require(try entry(store, promptId: p.id))

        // What the runner does on reopening: load the entry and its answers, add one, finish.
        var answers = try store.answers(entryId: saved.id)
        let versions = try store.currentQuestionVersionIds(surveyId: survey.id)
        answers.append(Answer(
            entryId: saved.id, questionId: second.id, questionVersionId: try #require(versions[second.id]),
            answeredAt: t(300), value: .scale(6)))
        saved.completedAt = t(320)
        try store.saveEntry(saved, answers: answers)

        let entries = try store.entries(surveyId: survey.id, from: nil, to: nil)
        #expect(entries.count == 1)
        #expect(entries.first?.answeredFromNotification == true)
        #expect(try store.answers(entryId: saved.id).map(\.value) == [.yesNo(false), .scale(6)])
    }

    @Test("an entry opened in the app first is left to the runner: nothing is saved")
    func leavesAppEntryAlone() throws {
        let (store, survey, first, second) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        try store.record(in: survey, promptId: p.id, startedAt: t(110), answers: [(second, .scale(3))])
        let before = try store.backup(now: t(0))

        let outcome = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: t(150))

        #expect(outcome == .unavailable)
        #expect(try store.backup(now: t(0)) == before)
    }

    @Test("a save from a copy taken before the notification answer keeps the flag")
    func flagIsSticky() throws {
        let (store, survey, first, _) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        _ = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: t(150))
        var stale = try #require(try entry(store, promptId: p.id))
        stale.answeredFromNotification = false

        try store.saveEntry(stale, answers: try store.answers(entryId: stale.id))

        #expect(try entry(store, promptId: p.id)?.answeredFromNotification == true)
    }

    @Test("saving an incomplete copy over a completed entry throws and changes nothing")
    func completedEntryIsNotReopened() throws {
        let (store, survey, first, _) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        _ = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: t(150))
        let copy = try #require(try entry(store, promptId: p.id))   // what an open runner holds
        try store.settleExpiredPrompts([p.id], now: t(2000))
        let before = try store.backup(now: t(0))

        #expect(throws: StoreError.entryCompleted) { try store.saveEntry(copy, answers: []) }
        #expect(try store.backup(now: t(0)) == before)

        // Completing over a completed entry, as the runner's Done does, is still allowed.
        var done = copy
        done.completedAt = t(2100)
        try store.saveEntry(done, answers: try store.answers(entryId: copy.id))
        #expect(try entry(store, promptId: p.id)?.completedAt == t(2100))
    }

    @Test("answering twice replaces the value and keeps the first answer's identity and time")
    func answeringTwice() throws {
        let (store, survey, first, _) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        _ = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: t(150))
        let before = try #require(try store.answers(entryId: try #require(try entry(store, promptId: p.id)).id).first)

        _ = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(false)), now: t(200))

        let after = try store.answers(entryId: before.entryId)
        #expect(after.count == 1)
        #expect(after.first?.id == before.id)
        #expect(after.first?.answeredAt == t(150))
        #expect(after.first?.value == .yesNo(false))
    }

    // MARK: Refusals

    @Test("a completed entry or an answered prompt saves nothing")
    func alreadyAnswered() throws {
        let (store, survey, first, _) = try seeded()
        let done = Fixture.prompt(survey, scheduledAt: t(100))
        let deleted = Fixture.prompt(survey, scheduledAt: t(200), status: .answered, respondedAt: t(250))
        try store.insertPrompts([done, deleted])
        try store.record(in: survey, promptId: done.id, startedAt: t(110), completedAt: t(120), answers: [(first, .yesNo(true))])
        let before = try store.backup(now: t(0))
        let no = try action(survey, .yesNo(false))

        #expect(try store.saveNotificationAnswer(promptId: done.id, questionId: first.id, actionIdentifier: no, now: t(130)) == .alreadyAnswered)
        #expect(try store.saveNotificationAnswer(promptId: deleted.id, questionId: first.id, actionIdentifier: no, now: t(260)) == .alreadyAnswered)
        #expect(try store.backup(now: t(0)) == before)
    }

    @Test("a changed first question, an action no longer offered, or a missing prompt saves nothing")
    func unavailable() throws {
        let (store, survey, first, second) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        let yes = try action(survey, .yesNo(true))

        #expect(try store.saveNotificationAnswer(promptId: "missing", questionId: first.id, actionIdentifier: yes, now: t(150)) == .unavailable)
        #expect(try store.saveNotificationAnswer(promptId: p.id, questionId: second.id, actionIdentifier: yes, now: t(150)) == .unavailable)
        #expect(try store.saveNotificationAnswer(promptId: p.id, questionId: first.id, actionIdentifier: "answer.scale.3", now: t(150)) == .unavailable)

        // The yes/no question is moved below the scale after the notification was scheduled.
        try store.updateQuestion(
            first.id, label: first.label, position: 5, isRequired: true, isArchived: false,
            scale: nil, allowsCustomOptions: false, now: t(140))
        #expect(try store.saveNotificationAnswer(promptId: p.id, questionId: first.id, actionIdentifier: yes, now: t(150)) == .unavailable)
        #expect(try entry(store, promptId: p.id) == nil)
        #expect(try prompt(store, p.id)?.status == .pending)
    }

    // MARK: Expiry (R5)

    @Test("an answer after expiry saves nothing and records the prompt as missed")
    func expiredMarksMissed() throws {
        let (store, survey, first, _) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])

        // Expiry is inclusive: exactly at expiresAt is too late.
        let outcome = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: p.expiresAt)

        #expect(outcome == .expired)
        #expect(try entry(store, promptId: p.id) == nil)
        let missed = try #require(try prompt(store, p.id))
        #expect(missed.status == .missed)
        #expect(missed.respondedAt == p.expiresAt)
    }

    @Test("an answer to a prompt already missed or dismissed saves nothing and changes nothing")
    func alreadyMissed() throws {
        let (store, survey, first, _) = try seeded()
        let missed = Fixture.prompt(survey, scheduledAt: t(100), status: .missed, respondedAt: t(1300))
        let dismissed = Fixture.prompt(survey, scheduledAt: t(200), status: .dismissed, respondedAt: t(210))
        try store.insertPrompts([missed, dismissed])
        let before = try store.backup(now: t(0))
        let yes = try action(survey, .yesNo(true))

        #expect(try store.saveNotificationAnswer(promptId: missed.id, questionId: first.id, actionIdentifier: yes, now: t(150)) == .expired)
        #expect(try store.saveNotificationAnswer(promptId: dismissed.id, questionId: first.id, actionIdentifier: yes, now: t(250)) == .expired)
        #expect(try store.backup(now: t(0)) == before)
    }

    @Test("at expiry a notification entry with every required answer completes at its last answer")
    func settleCompletes() throws {
        let (store, survey, first, second) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        _ = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: t(160))
        var open = try #require(try entry(store, promptId: p.id))
        var answers = try store.answers(entryId: open.id)
        answers.append(Answer(
            entryId: open.id, questionId: second.id,
            questionVersionId: try #require(try store.currentQuestionVersionIds(surveyId: survey.id)[second.id]),
            answeredAt: t(400), value: .scale(2)))
        try store.saveEntry(open, answers: answers)

        let answersBefore = try store.answers(entryId: open.id)
        try store.settleExpiredPrompts([p.id], now: t(2000))

        open = try #require(try entry(store, promptId: p.id))
        #expect(open.completedAt == t(400))
        #expect(open.answeredFromNotification)
        #expect(try store.answers(entryId: open.id) == answersBefore)
        let settled = try #require(try prompt(store, p.id))
        #expect(settled.status == .answered)
        #expect(settled.respondedAt == t(400))
        #expect(try store.answers(entryId: open.id).count == 2)
    }

    @Test("a later answer after expiry finds the entry closed, and the export shows a full latency")
    func settledThenAnsweredAgain() throws {
        let (store, survey, first, _) = try seeded()
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        let yes = try action(survey, .yesNo(true))
        _ = try store.saveNotificationAnswer(promptId: p.id, questionId: first.id, actionIdentifier: yes, now: t(160))

        // The answer arrives after expiry with no refresh in between: it settles the prompt.
        #expect(try store.saveNotificationAnswer(promptId: p.id, questionId: first.id, actionIdentifier: yes, now: t(2000)) == .expired)
        #expect(try prompt(store, p.id)?.status == .answered)
        #expect(try store.saveNotificationAnswer(promptId: p.id, questionId: first.id, actionIdentifier: yes, now: t(2001)) == .alreadyAnswered)

        let csv = CSVExporter.wide(try store.exportSnapshot(surveyId: survey.id), calendar: Calendar(identifier: .gregorian))
        let row = csv.components(separatedBy: "\r\n")[1]
        #expect(row.contains(",yes,yes,"))   // prompted, answered_from_notification
        #expect(row.contains(",60,"))         // latency: t(160) - t(100)
    }

    @Test("at expiry a notification entry missing a required answer stays open and the prompt is missed")
    func settleMissesIncomplete() throws {
        let (store, survey, first, _) = try seeded(secondRequired: true)
        let p = Fixture.prompt(survey, scheduledAt: t(100))
        try store.insertPrompts([p])
        _ = try store.saveNotificationAnswer(
            promptId: p.id, questionId: first.id, actionIdentifier: try action(survey, .yesNo(true)), now: t(160))

        try store.settleExpiredPrompts([p.id], now: t(2000))

        #expect(try entry(store, promptId: p.id)?.completedAt == nil)
        let settled = try #require(try prompt(store, p.id))
        #expect(settled.status == .missed)
        #expect(settled.respondedAt == t(2000))
    }

    @Test("settling leaves in-app entries open, misses their prompts, and skips settled or unknown prompts")
    func settleOthers() throws {
        let (store, survey, first, _) = try seeded()
        let appPrompt = Fixture.prompt(survey, scheduledAt: t(100))
        let bare = Fixture.prompt(survey, scheduledAt: t(200))
        let answered = Fixture.prompt(survey, scheduledAt: t(300), status: .answered, respondedAt: t(310))
        try store.insertPrompts([appPrompt, bare, answered])
        let (appEntry, _) = try store.record(
            in: survey, promptId: appPrompt.id, startedAt: t(110), answers: [(first, .yesNo(true))])

        try store.settleExpiredPrompts([appPrompt.id, bare.id, answered.id, "missing"], now: t(3000))

        #expect(try entry(store, promptId: appPrompt.id) == appEntry)
        #expect(try prompt(store, appPrompt.id)?.status == .missed)
        #expect(try prompt(store, bare.id)?.status == .missed)
        #expect(try prompt(store, bare.id)?.respondedAt == t(3000))
        #expect(try prompt(store, answered.id) == answered)
    }
}
