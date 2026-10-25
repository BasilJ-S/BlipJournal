import SwiftUI

struct ExportView: View {
    init() {}

    @Environment(AppModel.self) private var appModel
    @State private var model: ExportModel?
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let model {
                if model.format != .jsonBackup { Picker("Survey", selection: Binding(get: { model.selectedSurveyId }, set: { model.selectedSurveyId = $0 })) { ForEach(model.surveys) { survey in Text(survey.isArchived ? "\(survey.name) (Archived)" : survey.name).tag(Optional(survey.id)) } } }
                Picker("Format", selection: Binding(get: { model.format }, set: { model.format = $0 })) { ForEach(ExportModel.Format.allCases) { Text($0.title).tag($0) } }
                Text(model.format.detail).font(.footnote).foregroundStyle(.secondary)
                if model.format == .jsonBackup { Text("Includes all surveys and dates.").font(.footnote) }
                else {
                    Picker("Date range", selection: Binding(get: { model.range }, set: { model.setRange($0) })) { ForEach(ExportModel.DateRange.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                    if model.range == .custom { DatePicker("Start date", selection: Binding(get: { model.customStart }, set: { model.customStart = $0 }), in: ...Date(), displayedComponents: .date); DatePicker("End date", selection: Binding(get: { model.customEnd }, set: { model.customEnd = $0 }), in: ...Date(), displayedComponents: .date) }
                    Text("Based on when each entry was started.").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Exported files are not encrypted. Anyone with the file can read your answers.").font(.footnote).foregroundStyle(.orange)
                Button { do { shareURL = try model.makeFile() } catch { errorMessage = error.localizedDescription } } label: { Label("Share", systemImage: "square.and.arrow.up") }.accessibilityLabel("Share export")
                Text("A JSON backup can be restored from Settings, Restore from backup. CSV files open in Numbers and Excel.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .blipScreen("Export")
        .shareSheet(url: $shareURL) { _ in model?.cleanUp() }
        .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        .task { if model == nil { model = ExportModel(store: appModel.store) } }
        .onDisappear { model?.cleanUp() }
    }
}
