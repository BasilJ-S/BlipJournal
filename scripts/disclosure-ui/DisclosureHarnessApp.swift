import SwiftUI
import BlipJournalCore

@main
struct DisclosureHarnessApp: App {
    private let model: AppModel
    init() {
        model = try! AppModel(store: Store.inMemory(), notifications: NoopNotificationCoordinator())
        model.unlock()
    }
    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Restore", systemImage: "arrow.clockwise") { NavigationStack { RestoreBackupView() } }
                Tab("Export", systemImage: "square.and.arrow.up") { NavigationStack { ExportView() } }
            }.environment(model)
        }
    }
}
