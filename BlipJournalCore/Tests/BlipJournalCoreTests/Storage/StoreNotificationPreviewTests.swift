import Foundation
import Testing
@testable import BlipJournalCore

@Suite("Store notification preview")
struct StoreNotificationPreviewTests {
    private let t = Fixture.at

    @Test("a newly created survey defaults to private")
    func createDefaultsToPrivate() throws {
        let (store, survey) = try Fixture.seeded()
        #expect(survey.notificationPreview == .private)
        #expect(try store.survey(survey.id)?.notificationPreview == .private)
    }

    @Test("updateNotificationPreview twice makes the second the survey's preview")
    func updateTwice() throws {
        let (store, survey) = try Fixture.seeded()

        try store.updateNotificationPreview(surveyId: survey.id, .surveyName, now: t(1))
        #expect(try store.survey(survey.id)?.notificationPreview == .surveyName)

        try store.updateNotificationPreview(surveyId: survey.id, .custom(message: "Check in?"), now: t(2))
        #expect(try store.survey(survey.id)?.notificationPreview == .custom(message: "Check in?"))
        #expect(try store.backup(now: t(3)).surveyNotificationPreviews.count == 3)
    }

    @Test("a blank or whitespace-only custom message is rejected before writing anything")
    func rejectsBlankMessage() throws {
        let (store, survey) = try Fixture.seeded()
        for message in ["", "   ", "\n"] {
            #expect(throws: StoreError.invalidNotificationPreview) {
                try store.updateNotificationPreview(surveyId: survey.id, .custom(message: message), now: t(1))
            }
        }
        #expect(try store.backup(now: t(2)).surveyNotificationPreviews.count == 1)
        #expect(try store.survey(survey.id)?.notificationPreview == .private)
    }

    @Test("updateNotificationPreview throws notFound for an unknown survey")
    func unknownSurvey() throws {
        #expect(throws: StoreError.notFound) {
            try store().updateNotificationPreview(surveyId: "x", .surveyName, now: t(1))
        }
    }

    @Test("multiple surveys keep independent preview histories")
    func multipleSurveys() throws {
        let store = try Store.inMemory()
        let a = try Fixture.seed(store, name: "A", now: t(0))
        let b = try Fixture.seed(store, name: "B", now: t(1))

        try store.updateNotificationPreview(surveyId: a.id, .surveyName, now: t(2))

        #expect(try store.survey(a.id)?.notificationPreview == .surveyName)
        #expect(try store.survey(b.id)?.notificationPreview == .private)
    }

    @Test("a survey with no preview row, as from a pre-migration database, resolves to private")
    func absentRowResolvesToPrivate() throws {
        let (store, survey) = try Fixture.seeded()
        try store.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM surveyNotificationPreview WHERE surveyId = ?", arguments: [survey.id])
        }
        #expect(try store.survey(survey.id)?.notificationPreview == .private)
        #expect(try store.surveys(includeArchived: true).first?.notificationPreview == .private)
    }

    @Test("a backup round trips a custom preview through JSON")
    func backupRoundTrips() throws {
        let (store, survey) = try Fixture.seeded()
        try store.updateNotificationPreview(surveyId: survey.id, .custom(message: "Ping!"), now: t(1))

        let backup = try store.backup(now: t(2))
        let decoded = try BackupExporter.decode(try BackupExporter.json(backup))

        #expect(decoded == backup)
        let row = try #require(decoded.surveyNotificationPreviews.last { $0.surveyId == survey.id })
        #expect(row.mode == "custom")
        #expect(row.message == "Ping!")
    }

    @Test("a pre-v2 backup with no surveyNotificationPreviews key still decodes, defaulting to empty")
    func decodesHistoricalBackupMissingTheKey() throws {
        let (store, _) = try Fixture.seeded()
        var json = try JSONSerialization.jsonObject(with: try BackupExporter.json(store.backup(now: t(1)))) as! [String: Any]
        json.removeValue(forKey: "surveyNotificationPreviews")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try BackupExporter.decode(data)
        #expect(decoded.surveyNotificationPreviews.isEmpty)
    }

    @Test("hard-deleting a survey removes its notification preview rows and counts them")
    func hardDeleteCountsAndRemoves() throws {
        let (store, survey) = try Fixture.seeded()
        try store.updateNotificationPreview(surveyId: survey.id, .surveyName, now: t(1))
        try store.archiveSurvey(survey.id, now: t(2))

        let before = try store.backup(now: t(3))
        let impact = try store.deletionImpact(surveyId: survey.id)
        try store.hardDeleteSurvey(survey.id)
        let after = try store.backup(now: t(4))

        #expect(before.surveyNotificationPreviews.count == 2)
        #expect(after.surveyNotificationPreviews.isEmpty)
        #expect(impact == measuredImpact(before: before, after: after, surveyLevel: true))
    }

    @Test("eraseEverything reseeds a private preview regardless of what the erased survey had")
    func eraseEverythingResetsToPrivate() throws {
        let (store, survey) = try Fixture.seeded()
        try store.updateNotificationPreview(surveyId: survey.id, .custom(message: "Old message"), now: t(1))

        let reseeded = try store.eraseEverything(now: t(2))

        #expect(reseeded.notificationPreview == .private)
        #expect(try store.backup(now: t(3)).surveyNotificationPreviews.count == 1)
        #expect(!(try store.backup(now: t(3)).jsonString().contains("Old message")))
    }

    private func store() throws -> Store { try Store.inMemory() }
}
