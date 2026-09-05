import SwiftUI
import OpenBlipCore

@main
struct OpenBlipApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
                .preferredColorScheme(.light)
        }
    }
}

/// Temporary root. Replaced by the lock screen and tab root in the UI subsystem tasks.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("OpenBlip")
                .font(.largeTitle.bold())
            Text("Core schema version \(OpenBlipCore.schemaVersion)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
