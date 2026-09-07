import Foundation
import BlipJournalCore
import Testing
import UserNotifications
@testable import BlipJournal

@MainActor
struct AppModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeModel(store: Store) throws -> AppModel {
        try AppModel(store: store, notifications: NoopNotificationCoordinator(), now: now)
    }

    @Test func seedsTemplateOnce() throws {
        let store = try Store.inMemory()
        let first = try makeModel(store: store)
        #expect(first.surveys.count == 1)
        #expect(first.surveys.first?.name == "Check-in")
        #expect(first.surveys.first?.activeQuestions.count == 6)

        let second = try makeModel(store: store)
        #expect(second.surveys.count == 1)
        #expect(try store.surveys(includeArchived: true).count == 1)
    }

    @Test func refreshReflectsStoreDeletion() throws {
        let store = try Store.inMemory()
        let model = try makeModel(store: store)
        let survey = try #require(model.surveys.first)

        let entry = Entry(surveyId: survey.id, startedAt: now, completedAt: now)
        try store.saveEntry(entry, answers: [])
        try model.refresh()
        #expect(model.entries.map(\.id) == [entry.id])

        try store.deleteEntry(entry.id)
        #expect(model.entries.count == 1)
        try model.refresh()
        #expect(model.entries.isEmpty)

        try store.archiveSurvey(survey.id, now: now.addingTimeInterval(1))
        try model.refresh()
        #expect(model.surveys.isEmpty)
        #expect(model.surveysById[survey.id]?.isArchived == true)
    }

    @Test func archivedSurveyDoesNotReseed() throws {
        let store = try Store.inMemory()
        let first = try makeModel(store: store)
        let id = try #require(first.surveys.first?.id)
        try store.archiveSurvey(id, now: now)
        let second = try makeModel(store: store)
        #expect(second.surveys.isEmpty)
        #expect(try store.surveys(includeArchived: true).map(\.id) == [id])
    }

    @Test func refreshInvalidatesAnswersWhenEntryIsUnchanged() throws {
        let store = try Store.inMemory()
        let model = try makeModel(store: store)
        let survey = try #require(model.surveys.first)
        let question = try #require(survey.activeQuestions.first)
        let version = try #require(store.currentQuestionVersionIds(surveyId: survey.id)[question.id])
        let entry = Entry(surveyId: survey.id, startedAt: now)
        try store.saveEntry(entry, answers: [])
        try model.refresh()
        let revision = model.revision
        let previousEntries = model.entries
        try store.saveEntry(entry, answers: [
            Answer(entryId: entry.id, questionId: question.id, questionVersionId: version,
                   answeredAt: now, value: .scale(5))
        ])
        try model.refresh()
        #expect(model.entries == previousEntries)
        #expect(model.revision != revision)
    }

    @Test func locksAfterGraceAndUnlocks() throws {
        let model = try makeModel(store: try Store.inMemory())
        #expect(model.isLocked)
        model.unlock()
        #expect(model.isLocked == false)

        model.didEnterBackground(at: now)
        model.willEnterForeground(at: now.addingTimeInterval(10))
        #expect(model.isLocked == false)

        model.didEnterBackground(at: now)
        model.willEnterForeground(at: now.addingTimeInterval(30))
        #expect(model.isLocked)

        model.unlock()
        #expect(model.isLocked == false)
    }

    @Test func foregroundAsksNotificationsToRefresh() async throws {
        let spy = SpyNotificationCoordinator()
        let model = try AppModel(store: try Store.inMemory(), notifications: spy, now: now)
        await withCheckedContinuation { continuation in
            spy.onRefresh = { continuation.resume() }
            model.willEnterForeground(at: now)
        }
        #expect(spy.refreshDates == [now])
    }

    @Test func coldLaunchForegroundKeepsLock() throws {
        let model = try makeModel(store: try Store.inMemory())
        model.willEnterForeground(at: now)
        #expect(model.isLocked)
    }
}

/// Records what the app asks of the notification layer.
@MainActor
final class SpyNotificationCoordinator: NotificationCoordinating {
    var authorizationStatus: UNAuthorizationStatus { .notDetermined }
    var pendingRoute: String?
    private(set) var refreshDates: [Date] = []
    var onRefresh: (() -> Void)?

    func requestAuthorization() async -> Bool { false }
    func reschedule(now: Date) async -> Bool { false }
    func refresh(now: Date) async {
        refreshDates.append(now)
        let callback = onRefresh
        onRefresh = nil
        callback?()
    }
    func scheduleChanged(surveyId: String, now: Date) async {}
    func promptsDestroyed(now: Date) async {}
}
