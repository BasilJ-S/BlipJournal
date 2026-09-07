import BlipJournalCore
import SwiftUI

struct SurveyEditorView: View {
    @Environment(AppModel.self) private var appModel
    let surveyId: String
    @State private var name = ""
    @State private var editMode = EditMode.inactive
    @State private var showingNewQuestion = false
    @State private var errorMessage: String?

    init(surveyId: String) { self.surveyId = surveyId }
    private var survey: Survey? { try? appModel.store.survey(surveyId) }

    var body: some View {
        Group {
            if let survey {
                Form {
                    Section("Survey") {
                        TextField("Survey name", text: $name)
                            .onSubmit { rename() }.accessibilityLabel("Survey name")
                        if !survey.sampling.isEnabled { Label("Notifications paused", systemImage: "bell.slash") }
                        NavigationLink("Sampling") { SamplingSettingsView(surveyId: survey.id) }
                        NavigationLink("Archived in this survey") { ArchivedView(scope: .survey(survey.id)) }
                    }
                    Section("Questions") {
                        ForEach(survey.activeQuestions) { question in
                            NavigationLink { QuestionEditorView(surveyId: survey.id, questionId: question.id) } label: {
                                Label(question.label, systemImage: icon(for: question.kind))
                            }.badge(question.isRequired ? "Required" : "")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Archive", role: .destructive) { archive(question) }
                            }
                        }.onMove { from, to in move(from: from, to: to) }
                        Button("Add question") { showingNewQuestion = true }
                    }
                }
                .environment(\.editMode, $editMode)
                .blipScreen(survey.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(editMode == .active ? "Done" : "Reorder") {
                            editMode = editMode == .active ? .inactive : .active
                        }
                        .accessibilityLabel(editMode == .active ? "Finish reordering questions" : "Reorder questions")
                    }
                }
                .sheet(isPresented: $showingNewQuestion) { NewQuestionSheet(surveyId: survey.id) }
            } else { ContentUnavailableView("Survey unavailable", systemImage: "questionmark") }
        }
        .task(id: appModel.revision) { name = survey?.name ?? "" }
        .alert("Could not save survey", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func rename() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do { try EditorModel(store: appModel.store, notifications: appModel.notifications).rename(surveyId: surveyId, to: name); try appModel.refresh() }
        catch { errorMessage = String(describing: error) }
    }

    private func archive(_ question: Question) {
        var archived = question; archived.isArchived = true
        do { try EditorModel(store: appModel.store, notifications: appModel.notifications).updateQuestion(archived); try appModel.refresh() }
        catch { errorMessage = String(describing: error) }
    }

    private func move(from: IndexSet, to: Int) {
        do { try EditorModel(store: appModel.store, notifications: appModel.notifications).moveQuestions(surveyId: surveyId, from: from, to: to); try appModel.refresh() }
        catch { errorMessage = String(describing: error) }
    }

    private func icon(for kind: QuestionKind) -> String {
        switch kind { case .scale: "slider.horizontal.3"; case .singleChoice: "circle.grid.2x2"; case .multiChoice: "checklist"; case .yesNo: "checkmark.circle"; case .text: "text.alignleft" }
    }
}
