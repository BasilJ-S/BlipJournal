import BlipJournalCore
import SwiftUI

/// Shows a survey file's questions and schedule before adding it, the reasons a file
/// cannot be imported, or a field to paste survey text into. Nothing is added until the
/// person taps Add survey.
struct SurveyImportSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var outcome: Result<SurveyFileContents, SurveyFileError>?
    @State private var text = ""
    @State private var errorMessage: String?
    /// Whether the sheet started from pasting, so a failed check can go back to the text.
    private let isPasting: Bool
    /// Called once the survey is added, just before the sheet closes itself.
    private let onAdded: () -> Void

    init(outcome: Result<SurveyFileContents, SurveyFileError>?, onAdded: @escaping () -> Void = {}) {
        _outcome = State(initialValue: outcome)
        isPasting = outcome == nil
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            content
                .blipScreen(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { confirmation }
                }
        }
        .alert("Could not add survey", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var title: String {
        switch outcome {
        case .success?: "Import survey"
        case .failure?: "Can't import"
        case nil: "Paste survey text"
        }
    }

    @ViewBuilder private var content: some View {
        switch outcome {
        case .success(let contents)?:
            SurveyFilePreview(contents: contents)
        case .failure(let error)?:
            issueList(error)
        case nil:
            pasteForm
        }
    }

    @ViewBuilder private var confirmation: some View {
        switch outcome {
        case .success(let contents)?:
            Button("Add survey") { add(contents) }
        case .failure?:
            if isPasting {
                Button("Edit text") { outcome = nil }
                    .accessibilityLabel("Edit survey text")
            }
        case nil:
            Button("Check") { outcome = SurveyFile.decode(text: text) }
                .accessibilityLabel("Check survey text")
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var pasteForm: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .frame(minHeight: 240)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Survey text")
            } footer: {
                Text("Paste a survey file's text, or an AI assistant's reply that contains one. Words around the survey are ignored. Nothing is added until you check it and confirm.")
            }
        }
    }

    private func issueList(_ error: SurveyFileError) -> some View {
        List {
            Section {
                ForEach(Array(error.issues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.location).font(.headline)
                        Text(issue.message)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(error.issues.count == 1 ? "1 problem" : "\(error.issues.count) problems")
            } footer: {
                Text("Nothing was added. Fix the survey and try again.")
            }
        }
    }

    private func add(_ contents: SurveyFileContents) {
        do {
            try appModel.store.importSurvey(contents)
            try appModel.refresh()
            onAdded()
            dismiss()
        } catch { errorMessage = String(describing: error) }
    }
}

/// A survey file's contents laid out the way the person will meet them.
struct SurveyFilePreview: View {
    let contents: SurveyFileContents

    var body: some View {
        List {
            Section("Survey") {
                LabeledContent("Name", value: contents.name)
                LabeledContent("Schedule", value: schedule)
                Text("Imported surveys start with notifications paused. Turn them on under Sampling when you're ready.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(contents.questions.isEmpty ? "No questions yet" : "Questions") {
                ForEach(contents.questions) { question in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question.label)
                        Text(detail(for: question)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !summaryLabels.isEmpty {
                Section("Shown in the Journal") {
                    ForEach(Array(summaryLabels.enumerated()), id: \.offset) { _, label in Text(label) }
                }
            }
        }
    }

    private var schedule: String {
        let sampling = contents.sampling
        return EditorText.window(sampling)
            + ", at least \(sampling.minGapMinutes) minutes apart, each open for \(sampling.expiryMinutes) minutes"
    }

    private var summaryLabels: [String] {
        contents.journalSummaryQuestionIds.compactMap { id in contents.questions.first { $0.id == id }?.label }
    }

    private func detail(for question: Question) -> String {
        var parts = [question.kind.editorDescription]
        if question.isRequired { parts.append("Required") }
        switch question.kind {
        case .scale:
            if let scale = question.scale {
                func end(_ value: Int, _ label: String) -> String { label.isEmpty ? "\(value)" : "\(value) (\(label))" }
                parts.append("\(end(scale.min, scale.minLabel)) to \(end(scale.max, scale.maxLabel))")
            }
        case .spectrum:
            if let spectrum = question.spectrum { parts.append(spectrum.zones.map(\.label).joined(separator: ", ")) }
        case .singleChoice, .multiChoice:
            let options = question.activeOptions.map(\.label)
            if !options.isEmpty { parts.append(options.joined(separator: ", ")) }
            if question.allowsCustomOptions { parts.append("more can be added while answering") }
        case .yesNo, .text:
            break
        }
        return parts.joined(separator: " · ")
    }
}
