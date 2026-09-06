import Foundation
import Testing
import GRDB
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

    @Test("opening a database migrated only to v1 applies v2 and its existing survey resolves to private")
    func migratesFromV1() throws {
        let directory = Fixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(Store.databaseFileName).path

        // A real pre-v2 database: only "v1" has ever run, exactly as an installed app's
        // database would be before this migration ships. `grdb_migrations` inside the
        // file itself is what tells the v1+v2 migrator below that "v1" is already done.
        do {
            var v1Only = DatabaseMigrator()
            v1Only.registerMigration("v1", migrate: Schema.migrateV1)
            let v1Queue = try DatabaseQueue(path: path)
            try v1Only.migrate(v1Queue)
            try v1Queue.write { db in
                try SurveyRow(id: "s1", createdAt: t(0)).insert(db)
                try SurveyVersionRow(id: "sv1", surveyId: "s1", name: "Old", isArchived: false, createdAt: t(0)).insert(db)
                try SurveySamplingRow(
                    id: "ss1", surveyId: "s1", promptsPerDay: 3, windowStartMinutes: 540,
                    windowEndMinutes: 1380, minGapMinutes: 60, expiryMinutes: 20, isEnabled: true,
                    createdAt: t(0)
                ).insert(db)
            }
        }

        // Store.open runs the real v1+v2 migrator; only "v2" is still pending.
        let store = try Store.open(at: directory)
        let survey = try #require(try store.survey("s1"))
        #expect(survey.name == "Old")
        #expect(survey.notificationPreview == .private)
        #expect(try store.backup(now: t(1)).surveyNotificationPreviews.isEmpty)

        // The migrated survey behaves exactly like one created after v2 shipped.
        try store.updateNotificationPreview(surveyId: "s1", .surveyName, now: t(2))
        #expect(try store.survey("s1")?.notificationPreview == .surveyName)
    }

    @Test("a survey with no preview row, as from a survey created before this migration, resolves to private")
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
