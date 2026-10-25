import BlipJournalCore
import SwiftUI
import UniformTypeIdentifiers

struct SurveyListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingNewSurvey = false
    @State private var showingGallery = false
    @State private var showingCopySurvey = false
    @State private var name = ""
    @State private var copySource: Survey?
    @State private var errorMessage: String?
    @State private var showingFileImporter = false
    @State private var pendingImport: PendingSurveyImport?

    init() {}

    var body: some View {
        List {
            ForEach(appModel.surveys) { survey in
                NavigationLink { SurveyEditorView(surveyId: survey.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(survey.name)
                        Text(summary(for: survey)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Archive", role: .destructive) { Task { await archive(survey) } }
                }
            }
            NavigationLink("Archived") { ArchivedView(scope: .all) }
        }
        .blipScreen("Surveys")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New survey") { showingGallery = true }
                    Button("Copy an existing survey") { showingCopySurvey = true }
                    Divider()
                    Button("Import a survey file") { showingFileImporter = true }
                    Button("Paste survey text") { pendingImport = .paste() }
                } label: {
                    Image(systemName: "plus").accessibilityLabel("Add survey")
                }
            }
        }
        .alert("New survey", isPresented: $showingNewSurvey) {
            TextField("Survey name", text: $name)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Choose a name. Sampling starts paused.") }
        .sheet(isPresented: $showingCopySurvey) {
            NavigationStack {
                List(appModel.surveys) { survey in
                    Button(survey.name) {
                        copySource = survey; showingCopySurvey = false; name = ""; showingNewSurvey = true
                    }
                }
                .blipScreen("Copy survey")
            }
        }
        .sheet(isPresented: $showingGallery) {
            NavigationStack {
                TemplateGalleryView { showingGallery = false }
                    .blipScreen("New survey")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingGallery = false } }
                    }
            }
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.blipSurvey, .json]) { result in
            switch result {
            case .success(let url): pendingImport = PendingSurveyImport(fileAt: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $pendingImport) { pending in SurveyImportSheet(outcome: pending.outcome) }
        .alert("Could not save survey", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func summary(for survey: Survey) -> String {
        guard survey.sampling.isEnabled else { return "Notifications paused" }
        return EditorText.window(survey.sampling)
    }

    /// Copies `copySource` under the chosen name. A blank survey starts in the gallery.
    private func create() {
        guard let copySource, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let model = EditorModel(store: appModel.store, notifications: appModel.notifications)
            _ = try model.copySurvey(sourceId: copySource.id, name: name)
            try appModel.refresh(); self.copySource = nil; name = ""
        } catch { errorMessage = String(describing: error) }
    }

    private func archive(_ survey: Survey) async {
        do {
            try await EditorModel(store: appModel.store, notifications: appModel.notifications).archive(surveyId: survey.id)
            try appModel.refresh()
        } catch { errorMessage = String(describing: error) }
    }
}
