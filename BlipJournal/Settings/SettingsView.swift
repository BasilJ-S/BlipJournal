import SwiftUI

/// The Settings tab: one row per screen. Owned by A1; later tasks replace the
/// destination files, not this one.
struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("Surveys") { SurveyListView() }
            NavigationLink("Notifications") { NotificationSettingsView() }
            NavigationLink("Export") { ExportView() }
            NavigationLink {
                DeleteAllDataView()
            } label: {
                Text("Delete all data")
                    .foregroundStyle(.red)
            }
            .accessibilityLabel("Delete all data")
            NavigationLink("About") { AboutView() }
        }
        .navigationTitle("Settings")
        .fontDesign(.rounded)
        .scrollContentBackground(.hidden)
        .blipScreenBackground()
    }
}
