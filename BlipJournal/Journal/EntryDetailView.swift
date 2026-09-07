import BlipJournalCore
import SwiftUI

/// One entry, read only: its provenance and every answered question in position order,
/// with a destructive delete at the bottom.
struct EntryDetailView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let entry: Entry

    @State private var answers: [Answer] = []
    @State private var prompt: Prompt?
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var hasLoadedAnswers = false
    @State private var errorMessage: String?
    @State private var runnerEntry: Entry?

    private var survey: Survey? { appModel.surveysById[entry.surveyId] }

    var body: some View {
        List {
            Section {
                LabeledContent("Survey", value: survey?.name ?? "Unknown survey")
                LabeledContent("Source", value: entry.isPrompted ? "Prompted" : "Manual")
                if let prompt {
                    LabeledContent("Prompted at") {
                        Text(prompt.scheduledAt, format: .dateTime.hour().minute())
                    }
                }
                LabeledContent("Started") {
                    Text(entry.startedAt, format: .dateTime.day().month().hour().minute())
                }
                LabeledContent("Completed") {
                    if let completedAt = entry.completedAt {
                        Text(completedAt, format: .dateTime.day().month().hour().minute())
                    } else {
                        Text("Draft")
                    }
                }
            }

            Section("Answers") {
                if answeredQuestions.isEmpty {
                    Text("No answers")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(answeredQuestions, id: \.question.id) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.question.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(Self.render(item.answer.value, for: item.question))
                            if let scale = item.question.scale, case .scale = item.answer.value {
                                Text("\(scale.min) is \(scale.minLabel), \(scale.max) is \(scale.maxLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                if entry.completedAt == nil {
                    Button("Continue entry") { runnerEntry = entry }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityLabel("Continue entry")
                }
                Button("Delete entry", role: .destructive) {
                    confirmingDelete = true
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Delete entry")
                .disabled(isDeleting || !hasLoadedAnswers)
                if isDeleting {
                    ProgressView("Deleting entry")
                }
            }
        }
        .blipScreen("Entry", titleStyle: .inline)
        .task(id: appModel.revision) { await load() }
        .sheet(item: $runnerEntry, onDismiss: { try? appModel.refresh() }) { entry in
            NavigationStack { SurveyRunnerView(entry: entry) { runnerEntry = nil } }
        }
        .confirmationDialog(
            deleteMessage, isPresented: $confirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete entry", role: .destructive) { Task { await deleteEntry() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Entry error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Data

    private struct AnsweredQuestion {
        let question: Question
        let answer: Answer
    }

    /// Every question of the survey with an answer in this entry, archived included,
    /// in position order. Unanswered questions are omitted.
    private var answeredQuestions: [AnsweredQuestion] {
        guard let survey else { return [] }
        let byQuestion = Dictionary(answers.map { ($0.questionId, $0) }, uniquingKeysWith: { first, _ in first })
        return survey.questions
            .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
            .compactMap { question in
                byQuestion[question.id].map { AnsweredQuestion(question: question, answer: $0) }
            }
    }

    private func load() async {
        hasLoadedAnswers = false
        do {
            let loaded = try await Self.read(store: appModel.store, entry: entry)
            guard !Task.isCancelled else { return }
            answers = loaded.answers
            prompt = loaded.prompt
            hasLoadedAnswers = true
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private nonisolated static func read(
        store: Store, entry: Entry
    ) async throws -> (answers: [Answer], prompt: Prompt?) {
        let answers = try store.answers(entryId: entry.id)
        guard let promptId = entry.promptId else { return (answers, nil) }
        let calendar = Calendar.current
        let days = [entry.startedAt, calendar.date(byAdding: .day, value: -1, to: entry.startedAt)]
            .compactMap { $0 }
            .map { DayKey.string(for: $0, calendar: calendar) }
        for day in days {
            if let prompt = try store.prompts(surveyId: entry.surveyId, day: day)
                .first(where: { $0.id == promptId }) {
                return (answers, prompt)
            }
        }
        // Stored day keys retain their original time zone. A zone change can miss
        // both candidate days, so fall back to the identifier across all prompts.
        return (answers, try store.prompts(status: nil).first { $0.id == promptId })
    }

    private var deleteMessage: String {
        var message = "Delete this entry permanently. This erases its \(answers.count) "
        message += answers.count == 1 ? "answer. " : "answers. "
        message += "It cannot be undone."
        if entry.isPrompted {
            message += " The prompt it answered still counts as answered."
        }
        return message
    }

    private func deleteEntry() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await Self.erase(store: appModel.store, entryId: entry.id)
        } catch {
            // Vacuum can fail after the delete commits. Reload even on failure.
            try? appModel.refresh()
            errorMessage = String(describing: error)
            return
        }
        // The row is gone, so leaving must not depend on the reload succeeding: a
        // failure here would otherwise strand the person on a screen for a deleted
        // entry under a "Could not delete" alert that misreports what happened. A
        // reload that fails leaves a stale row in the list until the next refresh.
        try? appModel.refresh()
        dismiss()
    }

    private nonisolated static func erase(store: Store, entryId: String) async throws {
        try store.deleteEntry(entryId)
    }

    // MARK: Rendering

    /// The answer as text, using the question's current labels.
    nonisolated static func render(_ value: AnswerValue, for question: Question) -> String {
        switch value {
        case .scale(let value):
            if let scale = question.scale {
                return "\(value) of \(scale.max)"
            }
            return "\(value)"
        case .single(let optionId):
            return optionLabel(optionId, in: question)
        case .multi(let optionIds):
            if optionIds.isEmpty { return "None selected" }
            // Option order, not selection order, so two entries with the same
            // selections read the same way.
            let selected = Set(optionIds)
            let ordered = question.options
                .filter { selected.contains($0.id) }
                .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
                .map(\.label)
            let unknown = optionIds.filter { id in !question.options.contains { $0.id == id } }
            return (ordered + unknown.map { _ in "Unknown option" }).joined(separator: ", ")
        case .yesNo(let value):
            return value ? "Yes" : "No"
        case .text(let text):
            return text.isEmpty ? "No text" : text
        }
    }

    nonisolated private static func optionLabel(_ optionId: String, in question: Question) -> String {
        question.options.first { $0.id == optionId }?.label ?? "Unknown option"
    }
}
