import SwiftUI

/// Placeholder. Task A6 replaces this file wholesale; the signature is the contract.
struct DeleteAllDataView: View {
    init() {}

    var body: some View {
        ContentUnavailableView(
            "Delete all data",
            systemImage: "trash",
            description: Text("This screen arrives with task A6."))
        .navigationTitle("Delete all data")
    }
}
