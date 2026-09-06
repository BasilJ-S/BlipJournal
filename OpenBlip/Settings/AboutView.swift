import SwiftUI

/// Placeholder. Task A6 replaces this file wholesale; the signature is the contract.
struct AboutView: View {
    init() {}

    var body: some View {
        ContentUnavailableView(
            "About",
            systemImage: "info.circle",
            description: Text("This screen arrives with task A6."))
        .navigationTitle("About")
    }
}
