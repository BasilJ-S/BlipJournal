import SwiftUI

/// Placeholder. Task A5 replaces this file wholesale; the signature is the contract.
struct InsightsView: View {
    init() {}

    var body: some View {
        ContentUnavailableView(
            "Insights",
            systemImage: "chart.xyaxis.line",
            description: Text("This screen arrives with task A5."))
        .navigationTitle("Insights")
    }
}
