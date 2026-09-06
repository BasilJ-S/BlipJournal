import BlipJournalCore
import SwiftUI

/// Every entry, newest first, sectioned by local day. Rows push `EntryDetailView`;
/// the toolbar starts a new entry in the survey runner.
struct JournalView: View {
    @Environment(AppModel.self) private var appModel
    @State private var runnerSurvey: Survey?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if appModel.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        // On the Group, not the List: deleting the last entry swaps in the empty state,
        // and a destination registered inside the List would vanish while the detail
        // view it pushed is still on the stack.
        .navigationDestination(for: Entry.self) { entry in
            EntryDetailView(entry: entry)
        }
        .navigationTitle("Journal")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                newEntryControl
            }
            #if DEBUG
            ToolbarItem(placement: .secondaryAction) {
                Button("Add sample entry", systemImage: "wand.and.stars") {
                    addSampleEntry()
                }
                .accessibilityLabel("Add sample entry")
            }
            #endif
        }
        // onDismiss covers the swipe-down case too: the runner autosaves, so a
        // dismissed sheet can still have written an entry the list must show.
        .sheet(item: $runnerSurvey, onDismiss: reload) { survey in
            SurveyRunnerView(survey: survey, promptId: nil) {
                runnerSurvey = nil
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: List

    private var entryList: some View {
        List {
            ForEach(daySections, id: \.day) { section in
                Section(Self.dayFormatter.string(from: section.day)) {
                    ForEach(section.entries) { entry in
                        NavigationLink(value: entry) {
                            EntryRow(entry: entry, survey: appModel.surveysById[entry.surveyId])
                        }
                    }
                }
            }
        }
    }

    private struct DaySection {
        let day: Date
        let entries: [Entry]
    }

    /// Entries grouped by local calendar day, newest day first; `appModel.entries` is
    /// already newest first so each group keeps that order.
    private var daySections: [DaySection] {
        let calendar = Calendar.current
        var sections: [DaySection] = []
        var currentDay: Date?
        var currentEntries: [Entry] = []
        for entry in appModel.entries {
            let day = calendar.startOfDay(for: entry.startedAt)
            if day != currentDay {
                if let currentDay {
                    sections.append(DaySection(day: currentDay, entries: currentEntries))
                }
                currentDay = day
                currentEntries = []
            }
            currentEntries.append(entry)
        }
        if let currentDay {
            sections.append(DaySection(day: currentDay, entries: currentEntries))
        }
        return sections
    }

    /// "Today", "Yesterday", otherwise a medium date.
    @MainActor private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No entries yet", systemImage: "book.closed")
        } description: {
            Text("Prompts will appear here once notifications are on.")
        } actions: {
            newEntryButton("Log an entry now")
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: New entry

    /// One active survey opens the runner directly; several offer a menu.
    @ViewBuilder
    private var newEntryControl: some View {
        newEntryButton("New entry")
    }

    @ViewBuilder
    private func newEntryButton(_ title: String) -> some View {
        if appModel.surveys.count > 1 {
            Menu(title, systemImage: "plus") {
                ForEach(appModel.surveys) { survey in
                    Button(survey.name) { runnerSurvey = survey }
                }
            }
            .accessibilityLabel(title)
        } else {
            Button(title, systemImage: "plus") {
                runnerSurvey = appModel.surveys.first
            }
            .disabled(appModel.surveys.isEmpty)
            .accessibilityLabel(title)
        }
    }

    private func reload() {
        do {
            try appModel.refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    #if DEBUG
    private func addSampleEntry() {
        do {
            guard let survey = appModel.surveys.first else { return }
            try SampleEntry.write(to: appModel.store, survey: survey)
            try appModel.refresh()
        } catch {
            errorMessage = String(describing: error)
        }
    }
    #endif
}

/// One Journal row: time, survey name, prompted or manual, first scale value, draft.
///
/// Answers are loaded when the row appears; the list is lazy, so only visible rows pay.
private struct EntryRow: View {
    @Environment(AppModel.self) private var appModel
    let entry: Entry
    let survey: Survey?
    @State private var summary = JournalRowSummary()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.startedAt, style: .time)
                    .font(.headline)
                if let scaleSummary = summary.value {
                    Text(scaleSummary)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(survey?.name ?? "Unknown survey")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { badges }
                VStack(alignment: .leading, spacing: 4) { badges }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .task(id: appModel.revision) { await loadSummary() }
    }

    @ViewBuilder
    private var badges: some View {
        JournalBadge(text: entry.isPrompted ? "Prompted" : "Manual")
        if entry.completedAt == nil {
            JournalBadge(text: "Draft")
        }
    }

    /// Loads the summary through a nonisolated helper, so the SQLite read happens off
    /// the main actor and still belongs to the structured `.task` that started it.
    private func loadSummary() async {
        await summary.load {
            guard let survey else { return nil }
            return await Self.scaleSummary(store: appModel.store, entryId: entry.id, survey: survey)
        }
    }

    /// The first scale question, in position order, that this entry answered.
    private nonisolated static func scaleSummary(
        store: Store, entryId: String, survey: Survey
    ) async -> String? {
        guard let answers = try? store.answers(entryId: entryId) else { return nil }
        let scaleQuestions = survey.questions
            .filter { $0.kind == .scale }
            .sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        for question in scaleQuestions {
            if let answer = answers.first(where: { $0.questionId == question.id }),
               case .scale(let value) = answer.value {
                guard let scale = question.scale else { return "\(value)" }
                return "\(value) of \(scale.max)"
            }
        }
        return nil
    }
}

/// A small text badge. Text rather than colour carries the meaning. Private so a
/// later task's own badge type cannot collide with it.
private struct JournalBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(.secondary)
    }
}
