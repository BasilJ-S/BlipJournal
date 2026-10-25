import BlipJournalCore
import SwiftUI

/// Every entry, newest first, sectioned by local day. Rows push `EntryDetailView`;
/// the toolbar starts a new entry in the survey runner and opens filter and sort.
struct JournalView: View {
    @Environment(AppModel.self) private var appModel
    @State private var runnerSurvey: Survey?
    @State private var errorMessage: String?
    @State private var filter = JournalFilter()
    @State private var sort = JournalSort.newestFirst
    @State private var showingFilters = false
    @State private var loadedAnswers: LoadedAnswers?
    /// The key whose read last failed, so the list can offer a retry instead of a
    /// spinner or a false "no matches".
    @State private var failedKey: AnswersKey?
    /// Bumped by Retry so the same query reads again.
    @State private var attempt = 0

    var body: some View {
        // Computed once per render and passed down: filtering and sorting every entry
        // is the expensive part of this screen.
        let query = self.query
        let key = answersKey(for: query)
        Group {
            VStack(spacing: 0) {
                openSurveyBanner
                if appModel.entries.isEmpty {
                    emptyState
                } else {
                    let visible = visibleEntries(query: query, key: key)
                    let failed = visible == nil && failedKey == key
                    if isNarrowedOrReordered(query) {
                        filterBar(query: query, shown: visible?.count, failed: failed)
                    }
                    if let visible {
                        if visible.isEmpty {
                            noMatchesState
                        } else {
                            entryList(visible, query: query)
                        }
                    } else if failed {
                        loadFailedState
                    } else {
                        ProgressView("Loading entries")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .task(id: key) { await loadAnswers(for: key) }
        // Write the cleaned-up query back, so the sheet never shows a choice the list
        // has already dropped (an erased survey, question or option).
        .onAppear(perform: normalizeState)
        .onChange(of: appModel.revision) { normalizeState() }
        // On the Group, not the List: deleting the last entry swaps in the empty state,
        // and a destination registered inside the List would vanish while the detail
        // view it pushed is still on the stack.
        .navigationDestination(for: Entry.self) { entry in
            EntryDetailView(entry: entry)
        }
        .blipScreen("Journal", titleStyle: .large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                newEntryControl
            }
            if !appModel.entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    let isOn = isNarrowedOrReordered(query)
                    Button("Filter and sort", systemImage: isOn
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle"
                    ) {
                        showingFilters = true
                    }
                    .accessibilityLabel("Filter and sort")
                    .accessibilityValue(isOn ? "On" : "Off")
                }
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
            NavigationStack {
                SurveyRunnerView(survey: survey, promptId: nil) {
                    runnerSurvey = nil
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            NavigationStack {
                JournalFilterView(filter: $filter, sort: $sort, surveys: pickableSurveys)
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

    // MARK: Filter and sort

    private typealias Query = (filter: JournalFilter, sort: JournalSort)

    /// The filter and sort with anything that no longer resolves dropped, for example
    /// a survey or option erased since it was chosen.
    private var query: Query {
        JournalQuery.normalized(filter: filter, sort: sort, surveys: appModel.surveysById)
    }

    private func isNarrowedOrReordered(_ query: Query) -> Bool {
        query.filter.isActive || query.sort != .newestFirst
    }

    private func normalizeState() {
        let query = self.query
        if query.filter != filter { filter = query.filter }
        if query.sort != sort { sort = query.sort }
    }

    /// What the answer read depends on. A write bumps `revision`, so answers edited in
    /// the runner or removed by a delete are re-read; Retry bumps `attempt`.
    private struct AnswersKey: Hashable {
        let revision: UInt64
        let attempt: Int
        let questionIds: [String]
    }

    private struct LoadedAnswers {
        let key: AnswersKey
        let answers: [Answer]
    }

    private func answersKey(for query: Query) -> AnswersKey {
        AnswersKey(
            revision: appModel.revision, attempt: attempt,
            questionIds: JournalQuery.questionIds(filter: query.filter, sort: query.sort))
    }

    /// The entries to list, or nil while the answers the query needs have never been
    /// read. Answers read for the same questions at an older revision stay in use
    /// while the re-read runs, so a refresh does not tear the list down to a spinner
    /// and lose the scroll position. Entries are always current; at worst a just-saved
    /// answer joins the filter a moment late.
    private func visibleEntries(query: Query, key: AnswersKey) -> [Entry]? {
        let answers: [Answer]
        if key.questionIds.isEmpty {
            answers = []
        } else if let loadedAnswers, loadedAnswers.key.questionIds == key.questionIds {
            answers = loadedAnswers.answers
        } else {
            return nil
        }
        return JournalQuery.apply(appModel.entries, filter: query.filter, sort: query.sort, answers: answers)
    }

    private var pickableSurveys: [Survey] {
        JournalQuery.pickableSurveys(
            active: appModel.surveys, all: appModel.surveysById, entries: appModel.entries,
            keeping: filter.surveyId)
    }

    private func loadAnswers(for key: AnswersKey) async {
        // A new key starts clean, so returning to a query that failed earlier shows the
        // spinner while it re-reads, not the old failure.
        failedKey = nil
        guard !key.questionIds.isEmpty else { return }
        let result = await Self.answers(store: appModel.store, questionIds: key.questionIds)
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let answers):
            loadedAnswers = LoadedAnswers(key: key, answers: answers)
            failedKey = nil
        case .failure(let error):
            // Nothing is cached for this key. With no usable earlier read the list
            // shows a retry state; with one, it stays on screen and the alert says why
            // it did not refresh.
            failedKey = key
            if loadedAnswers?.key.questionIds == key.questionIds {
                errorMessage = String(describing: error)
            }
        }
    }

    /// Reads off the main actor, like the row summaries do.
    private nonisolated static func answers(store: Store, questionIds: [String]) async -> Result<[Answer], any Error> {
        Result { try store.answers(questionIds: questionIds) }
    }

    /// Shown above the list whenever the filter or sort differs from the default.
    private func filterBar(query: Query, shown: Int?, failed: Bool) -> some View {
        HStack {
            Text(filterSummary(query: query, shown: shown, failed: failed))
                .font(BlipFont.body(15))
                .foregroundStyle(BlipBrand.muted)
            Spacer()
            Button("Clear") { clearFilters() }
                .accessibilityLabel("Clear filters and sort")
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// "n of total entries" while filtered, followed by the order when it is not newest
    /// first; "Sorted: …" alone when only the order changed.
    private func filterSummary(query: Query, shown: Int?, failed: Bool) -> String {
        let order = sortDescription(query)
        if failed { return "Couldn't load answers" }
        guard query.filter.isActive else { return "Sorted: \(order)" }
        guard let shown else { return "Filtering…" }
        let total = appModel.entries.count
        let count = "\(shown) of \(total) \(total == 1 ? "entry" : "entries")"
        return query.sort == .newestFirst ? count : "\(count) · \(order)"
    }

    private func sortDescription(_ query: Query) -> String {
        switch query.sort {
        case .newestFirst:
            return "newest first"
        case .oldestFirst:
            return "oldest first"
        case .answer(let questionId, let descending):
            let survey = query.filter.surveyId.flatMap { appModel.surveysById[$0] }
            let question = survey?.questions.first(where: { $0.id == questionId })
            let label = question?.label ?? "Answer"
            return "\(label) (\(descending ? "highest" : "lowest") first)"
        }
    }

    private func clearFilters() {
        filter = JournalFilter()
        sort = .newestFirst
    }

    private var loadFailedState: some View {
        ContentUnavailableView {
            Label("Couldn't load answers", systemImage: "exclamationmark.triangle")
        } description: {
            Text("The answers this filter needs could not be read.")
        } actions: {
            Button("Try again") { attempt += 1 }
                .buttonStyle(.borderedProminent)
            Button("Clear filters") { clearFilters() }
        }
    }

    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No matching entries", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No entries match these filters.")
        } actions: {
            Button("Clear filters") { clearFilters() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: List

    /// Jumps back to the top when the order changes, so a re-sort never lands mid-list.
    private func entryList(_ entries: [Entry], query: Query) -> some View {
        ScrollViewReader { proxy in
            entryRows(entries, query: query)
                .onChange(of: query.sort) {
                    if let first = entries.first {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
        }
    }

    /// Day sections while the order is by date; one flat list, each row dated, when
    /// sorted by an answer, since neighbouring rows can then be weeks apart.
    @ViewBuilder
    private func entryRows(_ entries: [Entry], query: Query) -> some View {
        List {
            if query.sort.isChronological {
                ForEach(daySections(entries), id: \.day) { section in
                    Section {
                        ForEach(section.entries) { entry in
                            entryLink(entry, showsDate: false)
                        }
                    } header: {
                        Text(Self.dayFormatter.string(from: section.day)).blipMonoLabel()
                    }
                }
            } else {
                ForEach(entries) { entry in
                    entryLink(entry, showsDate: true)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func entryLink(_ entry: Entry, showsDate: Bool) -> some View {
        NavigationLink(value: entry) {
            EntryRow(entry: entry, survey: appModel.surveysById[entry.surveyId], showsDate: showsDate)
        }
        .blipCardRow()
    }

    private struct DaySection {
        let day: Date
        let entries: [Entry]
    }

    /// Consecutive entries grouped by local calendar day. `entries` is already in date
    /// order, either direction, so sections and the entries within them keep it.
    private func daySections(_ entries: [Entry]) -> [DaySection] {
        let calendar = Calendar.current
        var sections: [DaySection] = []
        var currentDay: Date?
        var currentEntries: [Entry] = []
        for entry in entries {
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

    // MARK: Open survey banner

    /// Re-evaluated every 30s against the already-loaded `pendingPrompts`, so a window
    /// opening or closing while the app sits in the foreground updates the banner without
    /// any extra store reads.
    ///
    /// Routes through `appModel.notifications.pendingRoute` — the same field a tapped
    /// notification sets — rather than a local sheet, so there is exactly one presenter
    /// (`RootView`) for prompt routing. Two independent `.sheet`s racing to present would
    /// silently drop whichever loses.
    @ViewBuilder
    private var openSurveyBanner: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let prompt = appModel.openPrompt(at: context.date) {
                OpenSurveyBanner(surveyName: appModel.surveysById[prompt.surveyId]?.name ?? "Survey") {
                    appModel.notifications.pendingRoute = prompt.id
                }
                .padding([.horizontal, .top])
            }
        }
    }

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

/// One Journal row: time, chosen answer summaries, survey name, provenance, and draft.
///
/// Answers are loaded when the row appears; the list is lazy, so only visible rows pay.
private struct EntryRow: View {
    @Environment(AppModel.self) private var appModel
    let entry: Entry
    let survey: Survey?
    /// Whether to show the day as well as the time, for lists not sectioned by day.
    var showsDate = false
    @State private var summary = JournalRowSummary()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if showsDate {
                        // With the year: an answer-sorted list can span several.
                        Text(entry.startedAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    } else {
                        Text(entry.startedAt, style: .time)
                    }
                }
                .font(BlipFont.qualifier(17))
                if let answerSummary = summary.value {
                    Text(answerSummary)
                        .font(BlipFont.qualifier(17))
                        .foregroundStyle(BlipBrand.muted)
                }
            }
            Text(survey?.name ?? "Unknown survey")
                .font(BlipFont.body(15))
                .foregroundStyle(BlipBrand.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { badges }
                VStack(alignment: .leading, spacing: 4) { badges }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
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
            return await Self.answerSummary(store: appModel.store, entryId: entry.id, survey: survey)
        }
    }

    /// The answered Journal-summary questions, kept in the person's chosen order.
    private nonisolated static func answerSummary(
        store: Store, entryId: String, survey: Survey
    ) async -> String? {
        guard let answers = try? store.answers(entryId: entryId) else { return nil }
        return JournalRowSummary.text(answers: answers, survey: survey)
    }
}

/// A small text badge. Text rather than colour carries the meaning. Private so a
/// later task's own badge type cannot collide with it.
private struct JournalBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .blipMonoLabel(size: 9.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(BlipBrand.paper, in: Capsule())
    }
}

/// The card shown on the Journal tab whenever a pending prompt's window is open, so
/// finding the app open mid-window (rather than tapping the notification itself) still
/// surfaces that there's something to complete.
private struct OpenSurveyBanner: View {
    let surveyName: String
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(surveyName, systemImage: "bell.badge")
                .font(.headline)
            Text("Complete your scheduled survey")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Complete now", action: onComplete)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BlipBrand.sand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
