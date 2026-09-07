import SwiftUI
import UIKit

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
                Text("JSON backups are reserved for a future import. CSV files open in Numbers and Excel.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .blipScreen("Export")
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil; model?.cleanUp() } })) { if let url = shareURL { ActivityView(url: url) { self.model?.cleanUp(); shareURL = nil } } }
        .alert("Export failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        .task { if model == nil { model = ExportModel(store: appModel.store) } }
        .onDisappear { model?.cleanUp() }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let url: URL; let completion: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIActivityViewController { let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil); controller.completionWithItemsHandler = { _, _, _, _ in context.coordinator.finish() }; return controller }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: UIActivityViewController, coordinator: Coordinator) { coordinator.finish(); controller.completionWithItemsHandler = nil }

    final class Coordinator {
        private let completion: () -> Void
        private var didFinish = false
        init(completion: @escaping () -> Void) { self.completion = completion }
        func finish() { guard !didFinish else { return }; didFinish = true; completion() }
    }
}
