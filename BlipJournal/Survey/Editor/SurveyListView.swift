import SwiftUI

/// Placeholder. Task A4 replaces this file wholesale; the signature is the contract.
struct SurveyListView: View {
    init() {}

    var body: some View {
        ContentUnavailableView(
            "Surveys",
            systemImage: "list.bullet.rectangle",
            description: Text("This screen arrives with task A4."))
        .navigationTitle("Surveys")
    }
}
