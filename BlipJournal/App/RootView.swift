import SwiftUI

/// The three-tab root. Each tab owns its own navigation stack.
///
/// A tapped notification, whether it arrived while unlocked or is only being surfaced now
/// because the app just unlocked, is presented here as a sheet: `RootView` only exists
/// once `AppModel.isLocked` is false, so a route set while locked waits for unlock before
/// its sheet appears. It also waits for the one-time welcome to close: two presentations
/// from one view racing to appear would silently drop one, and the route must survive.
struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

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
        // Navigation chrome is owned by each screen's shared blipScreen modifier.
        .toolbarBackground(BlipBrand.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .blipScreenBackground()
        .sheet(isPresented: Binding(
            get: { hasSeenWelcome && appModel.notifications.pendingRoute != nil },
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
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenWelcome },
            set: { isPresented in
                if !isPresented { hasSeenWelcome = true }
            }
        )) {
            WelcomeView { hasSeenWelcome = true }
        }
    }
}
