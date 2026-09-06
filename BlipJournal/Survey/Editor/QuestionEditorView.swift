import BlipJournalCore
import SwiftUI

struct QuestionEditorView: View {
    @Environment(AppModel.self) private var appModel
    let surveyId: String
    let questionId: String
    @State private var label = ""
    @State private var required = false
    @State private var scale = ScaleConfig()
    @State private var customOptions = false
    @State private var editMode = EditMode.inactive
    @State private var errorMessage: String?
    private var question: Question? { (try? appModel.store.survey(surveyId))?.flatMap { s in s.questions.first { $0.id == questionId } } }

    var body: some View {
        Form {
            Section {
                TextField("Question label", text: $label).accessibilityLabel("Question label")
                Toggle("Required", isOn: $required)
                if let question {
                    Text("Kind: \(question.kind.rawValue)").foregroundStyle(.secondary)
                    Text("The kind cannot change because answers depend on it.").font(.footnote).foregroundStyle(.secondary)
                    if question.kind == .scale { ScaleFields(scale: $scale) }
                    if question.kind.usesOptions {
                        Toggle("Allow adding options while answering", isOn: $customOptions)
                    }
                }
            }
            if let question, question.kind.usesOptions {
                Section("Options") {
                    ForEach(question.activeOptions) { option in
                        TextField("Option", text: Binding(
                            get: { option.label }, set: { value in rename(option, value: value) }))
                            .accessibilityLabel("Option \(option.label)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Archive", role: .destructive) { archive(option) }
                            }
                    }.onMove { from, to in moveOptions(from: from, to: to) }
                    Button("Add option") { addOption() }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Edit question")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }; ToolbarItem(placement: .topBarLeading) { EditButton() } }
        .onAppear { load() }
        .alert("Could not save question", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func load() { guard let q = question else { return }; label = q.label; required = q.isRequired; scale = q.scale ?? ScaleConfig(); customOptions = q.allowsCustomOptions }
    private func save() {
        guard var q = question else { return }; q.label = label; q.isRequired = required; q.scale = q.kind == .scale ? scale : nil; q.allowsCustomOptions = q.kind.usesOptions && customOptions
        do { try EditorModel(store: appModel.store, notifications: appModel.notifications).updateQuestion(q); try appModel.refresh() } catch { errorMessage = String(describing: error) }
    }
    private func addOption() { do { _ = try EditorModel(store: appModel.store, notifications: appModel.notifications).addOption(questionId: questionId, label: "New option"); try appModel.refresh() } catch { errorMessage = String(describing: error) } }
    private func rename(_ option: ChoiceOption, value: String) { var updated = option; updated.label = value; do { try EditorModel(store: appModel.store, notifications: appModel.notifications).updateOption(updated); try appModel.refresh() } catch { errorMessage = String(describing: error) } }
    private func archive(_ option: ChoiceOption) { var updated = option; updated.isArchived = true; do { try EditorModel(store: appModel.store, notifications: appModel.notifications).updateOption(updated); try appModel.refresh() } catch { errorMessage = String(describing: error) } }
    private func moveOptions(from: IndexSet, to: Int) { do { try EditorModel(store: appModel.store, notifications: appModel.notifications).moveOptions(questionId: questionId, from: from, to: to); try appModel.refresh() } catch { errorMessage = String(describing: error) } }
}
