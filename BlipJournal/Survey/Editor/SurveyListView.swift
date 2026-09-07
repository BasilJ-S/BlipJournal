import BlipJournalCore
import SwiftUI

struct SurveyListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingNewSurvey = false
    @State private var showingCopySurvey = false
    @State private var name = ""
    @State private var copySource: Survey?
    @State private var errorMessage: String?

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
                    Button("Blank survey") { name = ""; copySource = nil; showingNewSurvey = true }
                    Button("Copy an existing survey") { showingCopySurvey = true }
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
        .alert("Could not save survey", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func summary(for survey: Survey) -> String {
        guard survey.sampling.isEnabled else { return "Notifications paused" }
        return "\(survey.sampling.promptsPerDay) prompts a day, \(clock(survey.sampling.windowStartMinutes)) to \(clock(survey.sampling.windowEndMinutes))"
    }

    private func clock(_ minutes: Int) -> String {
        guard minutes != 1440 else { return "midnight" }
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let model = EditorModel(store: appModel.store, notifications: appModel.notifications)
            if let copySource { _ = try model.copySurvey(sourceId: copySource.id, name: name) }
            else { _ = try model.createSurvey(name: name) }
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
