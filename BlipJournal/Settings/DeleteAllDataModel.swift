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
        var eraseError: Error?
        do { _ = try appModel.store.eraseEverything() }
        catch { eraseError = error }
        await appModel.notifications.promptsDestroyed(now: Date())
        appModel.notifications.pendingRoute = nil
        var refreshError: Error?
        do { try appModel.refresh() }
        catch { refreshError = error }
        if let eraseError { throw eraseError }
        if let refreshError { throw refreshError }
    }
}
