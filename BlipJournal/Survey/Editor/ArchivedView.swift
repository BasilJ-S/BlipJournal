import BlipJournalCore
import SwiftUI

enum ArchivedScope: Hashable { case all; case survey(String) }

struct ArchivedView: View {
    @Environment(AppModel.self) private var appModel
    let scope: ArchivedScope
    @State private var pendingTarget: ArchivedTarget?
    @State private var errorMessage: String?

    var body: some View {
        let all = (try? appModel.store.surveys(includeArchived: true)) ?? []
        let surveys = all.filter { $0.isArchived && includes($0.id) }
        let allQuestions = Self.archivedQuestions(in: all, scope: scope)
        let questions = allQuestions.filter { pair in pair.0.isArchived }
        let options = Self.archivedOptions(in: all, scope: scope)
        List {
            Section("Surveys") { ForEach(surveys) { survey in row("Survey: \(survey.name)", target: .survey(survey)) } }
            Section("Questions") { ForEach(questions, id: \.[0].id) { question, survey in row("\(question.label) — \(survey.name)", target: .question(question, in: survey)) } }
            Section("Options") { ForEach(options, id: \.[0].id) { option, question, survey in row("\(option.label) — \(question.label) — \(survey.name)", target: .option(option, in: question, survey)) } }
        }
        .navigationTitle("Archived")
        .confirmationDialog("Delete permanently?", item: $pendingTarget) { target in
            Button("Delete permanently", role: .destructive) { delete(target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in DeletionConfirmation.message(for: target, store: appModel.store) }
        .alert("Could not change archive", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func includes(_ surveyId: String) -> Bool { if case .survey(let id) = scope { return id == surveyId }; return true }
    static func archivedQuestions(in surveys: [Survey], scope: ArchivedScope) -> [(Question, Survey)] {
        var result: [(Question, Survey)] = []
        for survey in surveys where scopeIncludes(survey.id, scope: scope) {
            result.append(contentsOf: survey.questions.map { ($0, survey) })
        }
        return result
    }
    static func archivedOptions(in surveys: [Survey], scope: ArchivedScope) -> [(ChoiceOption, Question, Survey)] {
        var result: [(ChoiceOption, Question, Survey)] = []
        for survey in surveys where scopeIncludes(survey.id, scope: scope) {
            for question in survey.questions {
                for option in question.options where option.isArchived {
                    result.append((option, question, survey))
                }
            }
        }
        return result
    }
    private static func scopeIncludes(_ surveyId: String, scope: ArchivedScope) -> Bool {
        if case .survey(let id) = scope { return id == surveyId }
        return true
    }
    @ViewBuilder private func row(_ title: String, target: ArchivedTarget) -> some View {
        HStack { Text(title); Spacer(); Button("Unarchive") { unarchive(target) }.buttonStyle(.borderless); Button("Delete permanently", role: .destructive) { pendingTarget = target }.buttonStyle(.borderless) }
    }
    private func unarchive(_ target: ArchivedTarget) {
        Task { do { let model = EditorModel(store: appModel.store, notifications: appModel.notifications); switch target { case .survey(let s): try await model.unarchive(surveyId: s.id); case .question(let q, _): var q = q; q.isArchived = false; try model.updateQuestion(q); case .option(let o, _, _): var o = o; o.isArchived = false; try model.updateOption(o) }; try appModel.refresh() } catch { errorMessage = String(describing: error) } }
    }
    private func delete(_ target: ArchivedTarget) { Task { do { try await EditorModel(store: appModel.store, notifications: appModel.notifications).hardDelete(target); try appModel.refresh() } catch { errorMessage = String(describing: error) } } }
}
