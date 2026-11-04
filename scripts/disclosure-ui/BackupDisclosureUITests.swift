import XCTest

@MainActor
final class BackupDisclosureUITests: XCTestCase {
    func testBothBackupEntryPointsShowDisclosureBeforeSharing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["Save a backup of current data"].waitForExistence(timeout: 15), app.debugDescription)
        assertDisclosure(in: app)
        app.buttons["Export"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Format")).firstMatch.tap()
        app.buttons["JSON backup"].tap()
        XCTAssertTrue(app.buttons["Share export"].waitForExistence(timeout: 5))
        assertDisclosure(in: app)
    }

    private func assertDisclosure(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Exported files are not encrypted. Anyone with the file can read your answers."].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Includes all surveys and dates."].exists, app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
