import BlipJournalCore
import SwiftUI

/// Chooses the one or two answers that make each Journal row recognizable at a glance.
struct JournalSummarySettingsView: View {
    @Environment(AppModel.self) private var appModel
    let surveyId: String

    @State private var selectedIds: [String] = []
    @State private var errorMessage: String?

    private var survey: Survey? { try? appModel.store.survey(surveyId) }

    var body: some View {
        Form {
            Section {
                Text("Choose up to two responses to show on each Journal entry. Tap them in the order you want them displayed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                if let survey, survey.activeQuestions.isEmpty {
                    Text("Add a question before choosing a Journal summary.")
                        .foregroundStyle(.secondary)
                } else if let survey {
                    ForEach(survey.activeQuestions) { question in
                        Button {
                            toggle(question.id)
                        } label: {
                            HStack {
                                Label(question.label, systemImage: icon(for: question.kind))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if let position = selectedIds.firstIndex(of: question.id) {
                                    Text(position == 0 ? "Primary" : "Second")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel(accessibilityLabel(for: question))
                    }
                }
            } header: {
                Text("Responses")
            } footer: {
                Text("Choosing another response keeps the primary and replaces the second. An unanswered choice is omitted from that entry.")
            }
        }
        .navigationTitle("Journal summary")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appModel.revision) {
            selectedIds = survey?.journalSummaryQuestionIds ?? []
        }
        .alert("Could not save Journal summary", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggle(_ id: String) {
        var updated = selectedIds
        if let index = updated.firstIndex(of: id) {
            updated.remove(at: index)
        } else if updated.count < 2 {
            updated.append(id)
        } else {
            // The newest choice becomes secondary while the primary stays anchored.
            updated[1] = id
        }
        do {
            try EditorModel(
                store: appModel.store, notifications: appModel.notifications
            ).saveJournalSummary(surveyId: surveyId, questionIds: updated)
            selectedIds = updated
            try appModel.refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func accessibilityLabel(for question: Question) -> String {
        guard let index = selectedIds.firstIndex(of: question.id) else {
            return "\(question.label), not shown in Journal summary"
        }
        return "\(question.label), \(index == 0 ? "primary" : "second") Journal summary response"
    }

    private func icon(for kind: QuestionKind) -> String {
        switch kind {
        case .scale: "slider.horizontal.3"
        case .singleChoice: "circle.grid.2x2"
        case .multiChoice: "checklist"
        case .yesNo: "checkmark.circle"
        case .text: "text.alignleft"
        }
    }
}
