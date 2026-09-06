import Foundation
import Testing
@testable import BlipJournal

@MainActor
struct DeleteAllDataModelTests {
    private struct ExpectedFailure: Error {}

    @Test func cleanupRunsWhenEraseReportsPostCommitFailure() async {
        var destroyed = false
        var refreshed = false
        var routeCleared = false

        await #expect(throws: ExpectedFailure.self) {
            try await DeleteAllDataModel.performReset(
                erase: { throw ExpectedFailure() },
                refresh: { refreshed = true },
                promptsDestroyed: { _ in destroyed = true },
                clearRoute: { routeCleared = true })
        }
        #expect(destroyed)
        #expect(refreshed)
        #expect(routeCleared)
    }
}
