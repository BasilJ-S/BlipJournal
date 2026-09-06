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
        _ = try appModel.store.eraseEverything()
        await appModel.notifications.promptsDestroyed(now: Date())
        try appModel.refresh()
        appModel.notifications.pendingRoute = nil
    }
}
