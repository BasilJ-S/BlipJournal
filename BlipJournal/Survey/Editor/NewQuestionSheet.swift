import BlipJournalCore
import SwiftUI

struct NewQuestionSheet: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let surveyId: String
    @State private var kind = QuestionKind.scale
    @State private var label = ""
    @State private var required = false
    @State private var scale = ScaleConfig()
    @State private var spectrum = SpectrumConfig()
    @State private var customOptions = false
    @State private var options = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Question type", selection: $kind) { ForEach(QuestionKind.allCases, id: \.self) { Text(description($0)).tag($0) } }
                TextField("Question label", text: $label, axis: .vertical)
                Toggle("Required", isOn: $required)
                if kind == .text { Text("Quick notes are limited to 500 characters.").font(.footnote).foregroundStyle(.secondary) }
                if kind == .scale { ScaleFields(scale: $scale) }
                if kind == .spectrum { SpectrumFields(spectrum: $spectrum) }
                if kind.usesOptions {
                    Toggle("Allow adding options while answering", isOn: $customOptions)
                    TextField("Initial options, one per line", text: $options, axis: .vertical)
                }
            }.navigationTitle("New question")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { add() }.disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == .scale && !scale.isValid) || (kind == .spectrum && !spectrum.isValid)) } }
            .alert("Could not add question", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }
    private func description(_ kind: QuestionKind) -> String { switch kind { case .scale: "Scale — choose a number"; case .spectrum: "Spectrum — slide between feelings"; case .singleChoice: "Single choice — choose one"; case .multiChoice: "Multiple choice — choose any"; case .yesNo: "Yes or no"; case .text: "Quick note — short text" } }
    private func add() {
        do { let q = try EditorModel(store: appModel.store, notifications: appModel.notifications).addQuestion(surveyId: surveyId, kind: kind, label: label, isRequired: required, scale: kind == .scale ? scale : nil, spectrum: kind == .spectrum ? spectrum : nil, allowsCustomOptions: kind.usesOptions && customOptions); for (i, value) in options.split(separator: "\n").map(String.init).enumerated() { _ = try EditorModel(store: appModel.store, notifications: appModel.notifications).addOption(questionId: q.id, label: value) ; _ = i }; try appModel.refresh(); dismiss() } catch { errorMessage = String(describing: error) }
    }
}
