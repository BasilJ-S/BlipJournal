import Charts
import SwiftUI
import BlipJournalCore

/// Distribution exploration and a comparison driven by the same bounded snapshot.
struct ByOptionChart: View {
    @Bindable var model: InsightsModel
    @State private var selectedOption: AnswerDistribution?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.moodQuestion?.label ?? "Answer distribution")
                .font(.headline)
            if model.choiceQuestions.count > 1 {
                Picker("Group by", selection: $model.choiceQuestion) {
                    ForEach(model.choiceQuestions) { question in
                        Text(question.label).tag(Optional(question))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Group answers by question")
            } else if let question = model.choiceQuestion {
                Text(question.label).font(.subheadline)
            }
            Text("The spread of your answers in entries where each option was selected. Tap an option to compare and explore entries.")
                .font(.subheadline).foregroundStyle(.secondary)
            if model.choiceQuestion?.kind == .multiChoice {
                Text("An entry can appear under more than one option.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.choiceQuestions.isEmpty {
                Text("No choice question in this survey").foregroundStyle(.secondary)
            } else if model.optionDistributions.allSatisfy({ $0.count == 0 }) {
                Text("No entries answering both questions in this range").foregroundStyle(.secondary)
            } else if let axis = model.moodAxis {
                DistributionKey()
                ForEach(model.optionDistributions) { distribution in
                    Button {
                        selectedOption = distribution
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(distribution.label).font(.headline)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            DistributionPlot(distribution: distribution, domain: axis.domain,
                                minLabel: axis.minLabel, maxLabel: axis.maxLabel)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Compare \(distribution.label). \(DistributionPlot.summary(distribution))")
                }
            }
        }
        .sheet(item: $selectedOption) { option in
            NavigationStack {
                OptionComparisonView(model: model, optionId: option.id)
            }
        }
    }
}

private struct DistributionKey: View {
    var body: some View {
        Text("Box: middle 50% · Line: median · Whiskers: lowest to highest. Fewer than 5 entries are shown individually.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

/// One shared scale for all rows. Individual marks use separate lanes so equal
/// answers remain visible. No numerical summaries are calculated in the view.
private struct DistributionPlot: View {
    let distribution: AnswerDistribution
    let domain: ClosedRange<Double>
    let minLabel: String
    let maxLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.caption(distribution))
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if distribution.count > 0 {
                Chart {
                    if distribution.showsBox,
                       let minimum = distribution.minimum, let maximum = distribution.maximum,
                       let lower = distribution.lowerQuartile, let upper = distribution.upperQuartile,
                       let median = distribution.median {
                        RuleMark(xStart: .value("Lowest", minimum), xEnd: .value("Highest", maximum), y: .value("Row", 0))
                            .foregroundStyle(Color.accentColor.opacity(0.65))
                        RuleMark(x: .value("Lowest", minimum), yStart: .value("Bottom", -0.2), yEnd: .value("Top", 0.2))
                        RuleMark(x: .value("Highest", maximum), yStart: .value("Bottom", -0.2), yEnd: .value("Top", 0.2))
                        BarMark(xStart: .value("Lower quartile", lower), xEnd: .value("Upper quartile", upper),
                            y: .value("Row", 0), height: .fixed(26))
                            .cornerRadius(6)
                            .foregroundStyle(Color.accentColor.opacity(0.3))
                        RuleMark(x: .value("Median", median), yStart: .value("Bottom", -0.55), yEnd: .value("Top", 0.55))
                            .lineStyle(StrokeStyle(lineWidth: 3))
                    } else {
                        ForEach(Array(distribution.points.enumerated()), id: \.element.id) { index, point in
                            PointMark(x: .value("Answer", point.value), y: .value("Answer row", index))
                                .symbolSize(40)
                        }
                    }
                }
                .foregroundStyle(Color.accentColor)
                .chartXScale(domain: domain, range: .plotDimension(startPadding: 5, endPadding: 5))
                .chartYScale(domain: distribution.showsBox ? -1.0...1.0 : -1.0...4.0)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 54)
                .accessibilityHidden(true)
                HStack(alignment: .top) {
                    Text("\(minLabel) (\(domain.lowerBound.formatted()))")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 16)
                    Text("\(maxLabel) (\(domain.upperBound.formatted()))").multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.summary(distribution) + ". Scale: \(minLabel) to \(maxLabel).")
    }

    private static func caption(_ distribution: AnswerDistribution) -> String {
        guard let median = distribution.median else { return "No entries" }
        let count = distribution.count == 1 ? "1 entry" : "\(distribution.count) entries"
        return "\(count) · Median \(number(median))" + (distribution.showsBox ? "" : " · Few entries")
    }

    static func summary(_ distribution: AnswerDistribution) -> String {
        guard let median = distribution.median, let minimum = distribution.minimum,
              let maximum = distribution.maximum else { return "No entries" }
        let count = distribution.count == 1 ? "1 entry" : "\(distribution.count) entries"
        let values = "\(count) · Median \(number(median)) · Range \(number(minimum))–\(number(maximum))"
        if distribution.showsBox, let lower = distribution.lowerQuartile, let upper = distribution.upperQuartile {
            return values + " · Middle half \(number(lower))–\(number(upper))"
        }
        return values + " · Few entries"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct OptionComparisonView: View {
    @Bindable var model: InsightsModel
    let optionId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(model.moodQuestion?.label ?? "Answer distribution").font(.headline)
                Text(model.choiceQuestion?.label ?? "")
                Text("Within your selected date range. Only completed entries answering both questions are included. An explicit ‘none selected’ answer belongs in the second group.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.choiceQuestion?.kind == .multiChoice {
                    Text("Both groups may include other selected options.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                DistributionKey()
            }
            ForEach(model.comparison(optionId: optionId)) { group in
                Section {
                    if let axis = model.moodAxis {
                        DistributionPlot(distribution: group, domain: axis.domain,
                            minLabel: axis.minLabel, maxLabel: axis.maxLabel)
                    }
                    if group.count > 0 {
                        Text(DistributionPlot.summary(group))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        DisclosureGroup("Explore entries") {
                            ForEach(model.entries(in: group)) { entry in
                                NavigationLink {
                                    EntryDetailView(entry: entry)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(entry.startedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                        Text(entry.isPrompted ? "Prompted" : "Manual")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .accessibilityLabel("Entry from \(entry.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                        .accessibilityLabel("Explore entries: \(group.label)")
                    }
                } header: {
                    Text(group.label)
                }
            }
        }
        .navigationTitle("Compare answers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityLabel("Close comparison")
            }
        }
    }
}
