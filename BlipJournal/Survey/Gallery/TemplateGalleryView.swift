import BlipJournalCore
import SwiftUI

/// The bundled survey templates and a blank survey. A template opens the same preview
/// sheet as an imported file, which shows its questions and schedule and adds nothing
/// until the person taps Add survey. The caller supplies the navigation chrome.
struct TemplateGalleryView: View {
    @Environment(AppModel.self) private var appModel
    private let intro: String?
    private let excluding: Set<String>
    private let onAdded: (Survey) -> Void
    @State private var selected: PendingSurveyImport?
    /// The survey the preview added, handed on once the preview has closed.
    @State private var added: Survey?
    @State private var showingBlank = false
    @State private var name = ""
    @State private var errorMessage: String?

    /// - Parameters:
    ///   - intro: A line shown above the templates.
    ///   - excluding: Template ids to leave out, such as the one a fresh install already has.
    ///   - onAdded: Called with the new survey after one is added, from a template or blank.
    init(intro: String? = nil, excluding: Set<String> = [], onAdded: @escaping (Survey) -> Void) {
        self.intro = intro
        self.excluding = excluding
        self.onAdded = onAdded
    }

    /// One template read through the survey file importer, once per launch: the files
    /// are part of the app and never change while it runs.
    private struct Entry: Identifiable {
        let template: SurveyTemplateGallery.Template
        let pending: PendingSurveyImport
        var id: String { template.id }

        var contents: SurveyFileContents? {
            guard case .success(let contents)? = pending.outcome else { return nil }
            return contents
        }
    }

    @MainActor private static let entries: [Entry] = SurveyTemplateGallery.templates.map {
        Entry(template: $0, pending: PendingSurveyImport(fileAt: $0.url))
    }

    var body: some View {
        List {
            if let intro {
                Section { Text(intro).foregroundStyle(.secondary) }
            }
            Section("Templates") {
                ForEach(Self.entries.filter { !excluding.contains($0.id) }) { entry in
                    Button { selected = entry.pending } label: { row(entry) }
                        .accessibilityHint("Shows its questions and schedule before adding it.")
                }
            }
            Section {
                Button { name = ""; showingBlank = true } label: {
                    card("Blank survey", detail: "Write your own questions from scratch.")
                }
            }
        }
        .sheet(item: $selected, onDismiss: {
            // Waits for the preview to close, so two sheets never dismiss at once.
            if let survey = added { added = nil; onAdded(survey) }
        }) { pending in
            SurveyImportSheet(outcome: pending.outcome) { added = $0 }
        }
        .alert("New survey", isPresented: $showingBlank) {
            TextField("Survey name", text: $name)
            Button("Create") { createBlank() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Choose a name. Sampling starts paused.") }
        .alert("Could not save survey", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func row(_ entry: Entry) -> some View {
        // A file that fails to read still opens the preview, which lists its problems.
        let contents = entry.contents
        let questions = contents.map { $0.questions.count == 1 ? "1 question" : "\($0.questions.count) questions" }
        let schedule = contents.map { EditorText.window($0.sampling) }
        return card(
            contents?.name ?? entry.template.id, detail: entry.template.purpose,
            footnote: [questions, schedule].compactMap { $0 }.joined(separator: " · "))
    }

    private func card(_ title: String, detail: String, footnote: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail)
            if !footnote.isEmpty {
                Text(footnote).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func createBlank() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let survey = try EditorModel(store: appModel.store, notifications: appModel.notifications)
                .createSurvey(name: name)
            try appModel.refresh()
            onAdded(survey)
        } catch { errorMessage = String(describing: error) }
    }
}
