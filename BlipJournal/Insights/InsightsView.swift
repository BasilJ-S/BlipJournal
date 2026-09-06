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
        .navigationTitle("Insights")
        .task {
            guard model == nil else { return }
            let model = InsightsModel(store: appModel.store)
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
                if model.scaleQuestions.count > 1 {
                    Picker("Scale question", selection: $model.scaleQuestion) {
                        ForEach(model.scaleQuestions) { question in
                            Text(question.label).tag(Optional(question))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            chartSection(title: sectionTitle("Over time"), emptyReason: scaleEmptyReason) {
                if let scaleQuestion = model.scaleQuestion, let scale = scaleQuestion.scale {
                    MoodOverTimeChart(
                        points: model.series, rolling: model.rolling, scale: scale,
                        accessibilitySummary: model.seriesAccessibilitySummary)
                }
            }

            chartSection(title: sectionTitle("By hour"), emptyReason: scaleEmptyReason) {
                if let scale = model.scaleQuestion?.scale {
                    BucketBarChart(
                        title: sectionTitle("By hour"), buckets: model.byHour,
                        valueDomain: Double(scale.min)...Double(scale.max))
                        .accessibilityLabel(model.byHourAccessibilitySummary)
                }
            }

            chartSection(title: sectionTitle("By weekday"), emptyReason: scaleEmptyReason) {
                if let scale = model.scaleQuestion?.scale {
                    BucketBarChart(
                        title: sectionTitle("By weekday"), buckets: model.byWeekday,
                        valueDomain: Double(scale.min)...Double(scale.max))
                        .accessibilityLabel(model.byWeekdayAccessibilitySummary)
                }
            }

            Section("By option") {
                if let scale = model.scaleQuestion?.scale {
                    ByOptionChart(
                        choiceQuestions: model.choiceQuestions,
                        selectedChoiceQuestion: $model.choiceQuestion,
                        buckets: model.byOption,
                        valueDomain: Double(scale.min)...Double(scale.max),
                        accessibilitySummary: model.byOptionAccessibilitySummary,
                        emptyReason: byOptionEmptyReason)
                } else {
                    ContentUnavailableView(
                        "By option", systemImage: "chart.bar",
                        description: Text("No scale question in this survey"))
                }
            }

            Section("Response rate") {
                ComplianceTile(stats: model.compliance, accessibilitySummary: model.complianceAccessibilitySummary)
            }
        }
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
        guard let label = model.scaleQuestion?.label else { return context }
        return "\(label) — \(context)"
    }

    private var scaleEmptyReason: String? {
        if model.scaleQuestions.isEmpty { return "No scale question in this survey" }
        if model.series.isEmpty { return "No entries in this range" }
        return nil
    }

    private var byOptionEmptyReason: String? {
        if model.choiceQuestions.isEmpty { return "No choice question in this survey" }
        if model.byOption.allSatisfy({ $0.count == 0 }) { return "No entries in this range" }
        return nil
    }

    @ViewBuilder
    private func chartSection<Content: View>(
        title: String, emptyReason: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        Section(title) {
            if let emptyReason {
                ContentUnavailableView(title, systemImage: "chart.bar", description: Text(emptyReason))
            } else {
                content()
            }
        }
    }
}
