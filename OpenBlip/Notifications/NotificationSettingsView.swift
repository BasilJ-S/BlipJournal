import SwiftUI

/// Placeholder. Task A2 replaces this file wholesale; the signature is the contract.
struct NotificationSettingsView: View {
    init() {}

    var body: some View {
        ContentUnavailableView(
            "Notifications",
            systemImage: "bell",
            description: Text("This screen arrives with task A2."))
        .navigationTitle("Notifications")
    }
}
