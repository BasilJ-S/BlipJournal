import BlipJournalCore
import SwiftUI

/// Charts over the Analytics functions. This view does no arithmetic: every number on
/// screen comes from `InsightsModel`, which reads `Analytics` in the core package.
struct InsightsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: InsightsModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                InsightsBody(model: model, reload: reload)
            } else {
                ProgressView()
            }
        }
        .blipScreen("Insights", titleStyle: .large)
        // Keyed by the app's write revision, not just first appearance, so entries
        // and survey changes made elsewhere (Journal, Settings) do not leave a stale
        // snapshot on screen. The existing model is reused, not recreated, so this
        // never resets the person's survey, range or question selections.
        .task(id: appModel.revision) {
            let model = self.model ?? InsightsModel(store: appModel.store)
            self.model = model
            await reload(model)
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

    private func reload(_ model: InsightsModel) async {
        do {
            try model.load()
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

/// The loaded screen: survey and range pickers, then the chart sections. Split out of
/// `InsightsView` so `model` can be `@Bindable` for the pickers below.
private struct InsightsBody: View {
    @Bindable var model: InsightsModel
    let reload: (InsightsModel) async -> Void

    var body: some View {
        List {
            Section {
                surveyHeader
                rangePicker
                if model.range == .custom {
                    DatePicker(
                        "Start date", selection: $model.customStart, in: ...Date.now, displayedComponents: .date)
                    DatePicker(
                        "End date", selection: $model.customEnd, in: ...Date.now, displayedComponents: .date)
                }
                if model.moodQuestions.count > 1 {
                    Picker("Measure", selection: $model.moodQuestion) {
                        ForEach(model.moodQuestions) { question in
                            Text(question.label).tag(Optional(question))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .blipCardRow()

            chartSection(title: sectionTitle("Over time"), emptyReason: moodEmptyReason) {
                if let axis = model.moodAxis {
                    // One row, so `blipCardRow` draws the caption and the chart as a
                    // single card like every other chart section.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Line: rolling average of up to 7 entries")
                            .font(.caption).foregroundStyle(.secondary)
                        MoodOverTimeChart(
                            points: model.series, rolling: model.rolling, domain: axis.domain,
                            minLabel: axis.minLabel, maxLabel: axis.maxLabel,
                            accessibilitySummary: model.seriesAccessibilitySummary)
                    }
                }
            }

            chartSection(title: sectionTitle("By hour"), emptyReason: moodEmptyReason) {
                if let axis = model.moodAxis {
                    BucketBarChart(
                        title: sectionTitle("By hour"), buckets: model.byHour,
                        valueDomain: axis.domain)
                        .accessibilityLabel(model.byHourAccessibilitySummary)
                }
            }

            chartSection(title: sectionTitle("By weekday"), emptyReason: moodEmptyReason) {
                if let axis = model.moodAxis {
                    BucketBarChart(
                        title: sectionTitle("By weekday"), buckets: model.byWeekday,
                        valueDomain: axis.domain)
                        .accessibilityLabel(model.byWeekdayAccessibilitySummary)
                }
            }

            Section {
                if model.moodAxis != nil {
                    ByOptionChart(model: model)
                } else {
                    ContentUnavailableView(
                        "Answer distributions", systemImage: "chart.bar",
                        description: Text("No scale or spectrum question in this survey"))
                }
            } header: {
                Text("Explore by option").blipMonoLabel()
            }
            .blipCardRow()

            Section {
                ComplianceTile(stats: model.compliance, accessibilitySummary: model.complianceAccessibilitySummary)
            } header: {
                Text("Response rate").blipMonoLabel()
            }
            .blipCardRow()
        }
        .listStyle(.plain)
        .onChange(of: model.selectedSurveyId) { _, _ in
            Task { await reload(model) }
        }
    }

    // MARK: Survey and range

    @ViewBuilder
    private var surveyHeader: some View {
        if model.surveys.count > 1 {
            Picker("Survey", selection: $model.selectedSurveyId) {
                ForEach(model.surveys) { survey in
                    Text(surveyLabel(survey)).tag(Optional(survey.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Survey")
        } else if let survey = model.surveys.first {
            LabeledContent("Survey", value: surveyLabel(survey))
        } else {
            Text("No surveys yet")
                .foregroundStyle(.secondary)
        }
    }

    private func surveyLabel(_ survey: Survey) -> String {
        survey.isArchived ? "\(survey.name) (Archived)" : survey.name
    }

    /// A segmented control when it fits, else a menu, per the five range choices.
    private var rangePicker: some View {
        ViewThatFits(in: .horizontal) {
            Picker("Range", selection: $model.range) {
                ForEach(InsightsModel.RangeSelection.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.segmented)

            Picker("Range", selection: $model.range) {
                ForEach(InsightsModel.RangeSelection.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: Section framing

    private func sectionTitle(_ context: String) -> String {
        guard let label = model.moodQuestion?.label else { return context }
        return "\(label) — \(context)"
    }

    private var moodEmptyReason: String? {
        if model.moodQuestions.isEmpty { return "No mood question in this survey" }
        if model.series.isEmpty { return "No entries in this range" }
        return nil
    }

    @ViewBuilder
    private func chartSection<Content: View>(
        title: String, emptyReason: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            if let emptyReason {
                ContentUnavailableView(title, systemImage: "chart.bar", description: Text(emptyReason))
            } else {
                content()
            }
        } header: {
            Text(title).blipMonoLabel()
        }
        .blipCardRow()
    }
}
