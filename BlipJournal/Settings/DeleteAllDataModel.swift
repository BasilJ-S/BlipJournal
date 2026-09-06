import Foundation
import BlipJournalCore

@MainActor
final class DeleteAllDataModel {
    let appModel: AppModel
    var entryCount = 0
    var surveyCount = 0
    var promptCount = 0

    init(appModel: AppModel) { self.appModel = appModel; refreshCounts() }

    func refreshCounts() {
        entryCount = (try? appModel.store.entries(surveyId: nil, from: nil, to: nil).count) ?? 0
        surveyCount = (try? appModel.store.surveys(includeArchived: true).count) ?? 0
        promptCount = (try? appModel.store.prompts(status: nil).count) ?? 0
    }

    func deleteAll() async throws {
        try await Self.performReset(
            erase: { _ = try self.appModel.store.eraseEverything() },
            refresh: { try self.appModel.refresh() },
            promptsDestroyed: { await self.appModel.notifications.promptsDestroyed(now: $0) },
            clearRoute: { self.appModel.notifications.pendingRoute = nil })
    }

    static func performReset(
        erase: @escaping @MainActor () throws -> Void,
        refresh: @escaping @MainActor () throws -> Void,
        promptsDestroyed: @escaping @MainActor (Date) async -> Void,
        clearRoute: @escaping @MainActor () -> Void
    ) async throws {
        var eraseError: Error?
        do { try erase() } catch { eraseError = error }
        await promptsDestroyed(Date())
        clearRoute()
        var refreshError: Error?
        do { try refresh() } catch { refreshError = error }
        if let eraseError { throw eraseError }
        if let refreshError { throw refreshError }
    }
}
