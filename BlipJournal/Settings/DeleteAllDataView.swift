import SwiftUI

struct DeleteAllDataView: View {
    init() {}

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var model: DeleteAllDataModel?
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    @State private var deleted = false

    var body: some View {
        Form {
            Section {
                Text("This permanently removes every survey, answer, prompt, and schedule. The app restores a fresh default survey with notifications paused. Existing notification permission is unchanged.")
                Text("Exported files on other devices are not affected.").foregroundStyle(.secondary)
            }
            Section {
                Button("Delete all data", role: .destructive) { showingConfirmation = true }
                    .accessibilityLabel("Delete all data")
            }
        }
        .navigationTitle("Delete all data")
        .task { if model == nil { model = DeleteAllDataModel(appModel: appModel) } }
        .confirmationDialog("Delete all data permanently", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) { Task { await performDelete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases \(model?.entryCount ?? 0) entries, \(model?.surveyCount ?? 0) surveys, and every prompt. The default survey will be restored with notifications paused. It cannot be undone. Exported files on other devices are not affected.")
        }
        .alert("Could not delete data", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        .alert("All data deleted", isPresented: $deleted) { Button("OK") { dismiss() } } message: { Text("Notifications are paused.") }
    }

    private func performDelete() async {
        do { try await model?.deleteAll(); deleted = true }
        catch { errorMessage = error.localizedDescription }
    }
}
