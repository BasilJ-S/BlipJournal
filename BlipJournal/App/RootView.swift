import SwiftUI

/// The three-tab root. Each tab owns its own navigation stack.
///
/// A tapped notification, whether it arrived while unlocked or is only being surfaced now
/// because the app just unlocked, is presented here as a sheet: `RootView` only exists
/// once `AppModel.isLocked` is false, so a route set while locked waits for unlock before
/// its sheet appears.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        TabView {
            Tab("Journal", systemImage: "book.closed") {
                NavigationStack { JournalView() }
            }
            Tab("Insights", systemImage: "chart.xyaxis.line") {
                NavigationStack { InsightsView() }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView() }
            }
        }
        .preferredColorScheme(.light)
        .tint(BlipBrand.violet)
        .toolbarBackground(BlipBrand.paper, for: .tabBar, .navigationBar)
        .toolbarBackground(.visible, for: .tabBar, .navigationBar)
        .blipScreenBackground()
        .sheet(isPresented: Binding(
            get: { appModel.notifications.pendingRoute != nil },
            set: { isPresented in
                if !isPresented { appModel.notifications.pendingRoute = nil }
            }
        ), onDismiss: { try? appModel.refresh() }) {
            if let promptId = appModel.notifications.pendingRoute {
                PromptRouteView(promptId: promptId) {
                    appModel.notifications.pendingRoute = nil
                }
            }
        }
    }
}
