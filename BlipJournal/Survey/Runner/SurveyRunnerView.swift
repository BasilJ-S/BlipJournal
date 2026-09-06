import BlipJournalCore
import SwiftUI

struct SurveyRunnerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    private let survey: Survey?; private let entry: Entry?; private let promptId: String?; private let onFinish: () -> Void
    @State private var draft: EntryDraft?; @State private var errorMessage: String?; @State private var addQuestion: Question?; @State private var option = ""; @State private var leaving = false
    init(survey: Survey, promptId: String?, onFinish: @escaping () -> Void) { self.survey = survey; entry = nil; self.promptId = promptId; self.onFinish = onFinish }
    init(entry: Entry, onFinish: @escaping () -> Void) { survey = nil; self.entry = entry; promptId = nil; self.onFinish = onFinish }
    var body: some View {
        Group { if let draft { content(draft) } else { ProgressView("Loading entry") } }
            .navigationTitle(draft?.survey.name ?? survey?.name ?? "Entry").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(draft != nil).task { load() }
            .onChange(of: scenePhase) { _, phase in if phase == .background, let draft { Task { try? await draft.flush() } } }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
            .alert("Add option", isPresented: Binding(get: { addQuestion != nil }, set: { if !$0 { addQuestion = nil } })) { TextField("Option", text: $option); Button("Add") { add() }; Button("Cancel", role: .cancel) {} } message: { Text("Enter a new choice.") }
    }
    @ViewBuilder private func content(_ draft: EntryDraft) -> some View {
        VStack(spacing: 0) {
            ScrollView { LazyVStack(alignment: .leading, spacing: 16) { ForEach(draft.survey.activeQuestions) { q in card(q, draft) } }.padding() }
            Divider(); VStack(alignment: .leading) { if !draft.canComplete { Text("Still needed: \(draft.missingRequired.map(\.label).joined(separator: ", "))").font(.caption).foregroundStyle(.secondary) }; Button("Done") { Task { await finish(draft, complete: true) } }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity, minHeight: 44).disabled(!draft.canComplete || leaving) }.padding()
        }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { Task { await finish(draft, complete: false) } }.disabled(leaving) } }
    }
    @ViewBuilder private func card(_ q: Question, _ draft: EntryDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(q.label).font(.headline); if q.isRequired { Text("Required").font(.caption).foregroundStyle(.secondary) }; switch q.kind {
        case .scale: if let scale = q.scale { ScaleInput(scale: scale, value: draft.values[q.id].flatMap { if case .scale(let n) = $0 { n } else { nil } }, onChange: { number in Task { try? await draft.set(.scale(number), for: q.id) } }) }
        case .singleChoice, .multiChoice: ChipGrid(question: q, value: draft.values[q.id], onChange: { value in Task { try? await draft.set(value, for: q.id) } }, onAdd: { addQuestion = q })
        case .yesNo: YesNoInput(value: draft.values[q.id].flatMap { if case .yesNo(let b) = $0 { b } else { nil } }, onChange: { answer in Task { try? await draft.set(.yesNo(answer), for: q.id) } })
        case .text: TextInput(value: draft.values[q.id].flatMap { if case .text(let s) = $0 { s } else { nil } } ?? "", onChange: { draft.setText($0, for: q.id) }, onCommit: { Task { try? await draft.flush() } }) }
        if draft.hasAnswer(for: q.id) { Button("Clear answer") { Task { try? await draft.set(nil, for: q.id) } }.frame(minHeight: 44).accessibilityLabel("Clear answer for \(q.label)") }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
    private func load() { guard draft == nil else { return }; do { if let entry { draft = try EntryDraft(store: appModel.store, entry: entry) } else if let survey { draft = try EntryDraft(store: appModel.store, survey: survey, promptId: promptId) } } catch { errorMessage = String(describing: error) } }
    private func add() { guard let q = addQuestion, let draft else { return }; let label = option.trimmingCharacters(in: .whitespacesAndNewlines); guard !label.isEmpty, !q.activeOptions.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) else { return }; Task { do { try await draft.addOption(label: label, to: q.id); addQuestion = nil } catch { errorMessage = String(describing: error) } } }
    private func finish(_ draft: EntryDraft, complete: Bool) async { leaving = true; defer { leaving = false }; do { if complete { try await draft.complete() } else { try await draft.flush() }; onFinish() } catch { errorMessage = String(describing: error) } }
}
