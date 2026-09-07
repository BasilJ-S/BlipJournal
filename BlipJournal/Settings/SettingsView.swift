import SwiftUI

/// The Settings tab: one row per screen. Owned by A1; later tasks replace the
/// destination files, not this one.
struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("Surveys") { SurveyListView() }.blipCardRow()
            NavigationLink("Notifications") { NotificationSettingsView() }.blipCardRow()
            NavigationLink("Export") { ExportView() }.blipCardRow()
            NavigationLink {
                DeleteAllDataView()
            } label: {
                Text("Delete all data")
                    .foregroundStyle(.red)
            }
            .accessibilityLabel("Delete all data")
            .blipCardRow()
            NavigationLink("About") { AboutView() }.blipCardRow()
        }
        .listStyle(.plain)
        .navigationTitle("Settings")
        .fontDesign(.rounded)
        .scrollContentBackground(.hidden)
        .blipScreenBackground()
    }
}
