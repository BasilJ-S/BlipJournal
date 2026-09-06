import Foundation
import Testing
import BlipJournalCore

@Suite("NotificationPreview")
struct NotificationPreviewTests {
    @Test("default is private")
    func defaultIsPrivate() {
        #expect(NotificationPreview.default == .private)
    }

    @Test("private and surveyName are always valid")
    func fixedModesAreValid() {
        #expect(NotificationPreview.private.isValid)
        #expect(NotificationPreview.surveyName.isValid)
    }

    @Test("custom is valid with a non-blank message and invalid once trimmed to blank", arguments: [
        (message: "Ping!", valid: true),
        (message: "  Ping!  ", valid: true),
        (message: "", valid: false),
        (message: "   ", valid: false),
        (message: "\n\t", valid: false),
    ])
    func customValidity(_ scenario: (message: String, valid: Bool)) {
        #expect(NotificationPreview.custom(message: scenario.message).isValid == scenario.valid)
    }

    @Test("private shows the app name as title and a generic body")
    func privateContent() {
        let content = NotificationPreview.private.content(surveyName: "Check-in")
        #expect(content.title == "Blip Journal")
        #expect(content.body == "Time for a check-in.")
    }

    @Test("surveyName shows the current survey name as title, with the same generic body")
    func surveyNameContent() {
        let content = NotificationPreview.surveyName.content(surveyName: "Mood log")
        #expect(content.title == "Mood log")
        #expect(content.body == "Time for a check-in.")
    }

    @Test("custom shows the app name as title and the custom message as body")
    func customContent() {
        let content = NotificationPreview.custom(message: "Quick check?").content(surveyName: "Check-in")
        #expect(content.title == "Blip Journal")
        #expect(content.body == "Quick check?")
    }

    @Test("content never includes anything from inside the survey beyond its name")
    func contentNeverLeaksAnswers() {
        for preview in [NotificationPreview.private, .surveyName, .custom(message: "hi")] {
            let content = preview.content(surveyName: "Mood log")
            #expect(content.title == "Mood log" || content.title == "Blip Journal")
        }
    }

    @Test("round-trips through JSON for every case")
    func roundTrips() throws {
        for preview in [NotificationPreview.private, .surveyName, .custom(message: "Ping!")] {
            let data = try JSONEncoder().encode(preview)
            #expect(try JSONDecoder().decode(NotificationPreview.self, from: data) == preview)
        }
    }
}
