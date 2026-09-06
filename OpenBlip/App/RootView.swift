import SwiftUI

/// The three-tab root. Each tab owns its own navigation stack.
struct RootView: View {
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
    }
}
