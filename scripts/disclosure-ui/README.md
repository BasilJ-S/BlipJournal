# Backup disclosure UI regression

Run `python3 scripts/test-backup-disclosure.py --simulator <UUID>` with Xcode and XcodeGen.
The script copies the source into a temporary directory, substitutes an in-memory test
app with a separate bundle ID, and loads a generated empty backup into the production
Restore view. It checks both Restore and Export before sharing. It never restores data,
opens the share sheet, or changes production authentication. Source and results remain
in the printed temporary directory for inspection.

XCUITest is used here because this regression concerns rendered text in SwiftUI screens;
Core tests remain Swift Testing. The test host injection is confined to the temporary copy.
