import SwiftUI
import UniformTypeIdentifiers
import BlipJournalCore

struct RestoreBackupView: View {
    init() {}

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var model: RestoreBackupModel?
    @State private var showingPicker = false
    @State private var shareURL: URL?
    @State private var confirmingLoss = false

    var body: some View {
        Form {
            Section {
                Text("Restoring replaces everything in Blip Journal on this phone with the contents of a backup file made by Export. Merging is not supported.")
                Button("Choose backup file") { showingPicker = true }
                    .accessibilityLabel("Choose backup file")
            }
            if let model, let backup = model.backupSummary {
                Section("Backup and this phone") {
                    summaryRow("Backup", backup)
                    summaryRow("On this phone now", model.current)
                }
                Section {
                    Text("Everything on this phone will be replaced by the backup. Anything added since the backup was made will be lost.")
                        .foregroundStyle(.red)
                }
                Section {
                    Button {
                        do { shareURL = try model.makeCurrentBackupFile() } catch { model.errorMessage = error.localizedDescription }
                    } label: { Label("Save a backup of current data", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Save a backup of current data")
                    Text(model.savedCurrentData ? "Current data saved. You can restore it later the same way." : "Recommended. Keep the file somewhere safe so you can come back to it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Replace data on this phone", role: .destructive) {
                        if model.needsLossConfirmation { confirmingLoss = true } else { Task { await performRestore() } }
                    }
                    .accessibilityLabel("Replace data on this phone")
                }
            }
        }
        .blipScreen("Restore from backup")
        .task { if model == nil { model = RestoreBackupModel(appModel: appModel) } }
        .onDisappear { model?.cleanUp() }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.json]) { model?.load($0) }
        .shareSheet(url: $shareURL) { completed in
            model?.cleanUp()
            if completed { model?.markSavedCurrentData() }
        }
        .alert("Are you sure?", isPresented: $confirmingLoss) {
            Button("Replace and lose current data", role: .destructive) { Task { await performRestore() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You have not saved a backup of current data. It will be lost and cannot be recovered.") }
        .alert("Could not restore", isPresented: Binding(get: { model?.errorMessage != nil }, set: { if !$0 { model?.errorMessage = nil } })) { Button("OK") {} } message: { Text(model?.errorMessage ?? "") }
        .alert("Backup restored", isPresented: Binding(get: { model?.didRestore ?? false }, set: { if !$0 { model?.acknowledgeRestore() } })) { Button("OK") { dismiss() } } message: { Text("Blip Journal now matches the backup. Notifications were rescheduled from its surveys.") }
    }

    private func summaryRow(_ title: String, _ summary: BackupSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let date = summary.exportedAt { Text("Made \(date.formatted(date: .abbreviated, time: .shortened))") }
            Text("\(summary.surveys) surveys, \(summary.entries) entries")
        }
        .accessibilityElement(children: .combine)
    }

    private func performRestore() async {
        do { try await model?.restore() } catch { model?.errorMessage = RestoreBackupModel.message(for: error) }
    }
}
