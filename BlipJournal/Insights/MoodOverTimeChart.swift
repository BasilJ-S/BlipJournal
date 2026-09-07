import Charts
import SwiftUI
import BlipJournalCore

/// Mood answers over time: prompted entries as filled points, manual entries as
/// hollow ones, with a trailing 7-point rolling mean line. Y axis is the question's
/// own domain, labelled at its two ends; the view supplies no numbers of its own.
struct MoodOverTimeChart: View {
    let points: [MoodPoint]
    let rolling: [MoodPoint]
    let domain: ClosedRange<Double>
    let minLabel: String
    let maxLabel: String
    let accessibilitySummary: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Chart {
            ForEach(points) { point in
                // Exact timestamp, not `unit: .day`: several readings on one day must
                // keep their own x-position rather than collapsing onto one. Day
                // granularity belongs to the axis labels only.
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .symbol(by: .value("Source", sourceLabel(point)))
                    .foregroundStyle(Color.accentColor)
            }
            ForEach(rolling) { point in
                LineMark(x: .value("Date", point.date), y: .value("Rolling mean", point.value))
                    .foregroundStyle(.secondary)
                    .interpolationMethod(.monotone)
            }
        }
        .chartSymbolScale([
            Self.promptedLabel: AnyChartSymbolShape(.circle),
            Self.manualLabel: AnyChartSymbolShape(.circle.strokeBorder()),
        ])
        .chartForegroundStyleScale([Self.promptedLabel: Color.accentColor, Self.manualLabel: Color.accentColor])
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(values: [domain.lowerBound, domain.upperBound]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let raw = value.as(Double.self) {
                        Text(raw == domain.lowerBound ? minLabel : maxLabel)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 3 : 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 220)
        .accessibilityLabel(accessibilitySummary)
    }

    private static let promptedLabel = "Prompted"
    private static let manualLabel = "Manual"

    private func sourceLabel(_ point: MoodPoint) -> String {
        point.prompted ? Self.promptedLabel : Self.manualLabel
    }
}
