import Accessibility
import Charts
import SwiftUI
import BlipJournalCore

/// A bar chart of `BucketStat` means, used for by-hour, by-weekday and by-option.
/// Buckets with a zero count are omitted rather than drawn at zero; each bar
/// annotates its count at a fixed, non-scaling text size so a long axis of small bars
/// stays readable at large Dynamic Type sizes.
struct BucketBarChart: View {
    let title: String
    let buckets: [BucketStat]
    let valueDomain: ClosedRange<Double>
    var horizontal = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var plotted: [BucketStat] {
        buckets.filter { $0.count > 0 }
    }

    /// Bars always start at zero, so the value axis must contain both zero and
    /// the question's selectable scale. The time-series chart intentionally uses
    /// the question scale alone.
    static func barDomain(for scale: ScaleConfig) -> ClosedRange<Double> {
        barDomain(for: Double(scale.min)...Double(scale.max))
    }

    private static func barDomain(for scaleDomain: ClosedRange<Double>) -> ClosedRange<Double> {
        min(0, scaleDomain.lowerBound)...max(0, scaleDomain.upperBound)
    }

    private var plottedDomain: ClosedRange<Double> {
        Self.barDomain(for: valueDomain)
    }

    var body: some View {
        Chart(plotted) { bucket in
            if horizontal {
                BarMark(
                    xStart: .value("Baseline", 0), xEnd: .value("Mean", bucket.mean ?? 0),
                    y: .value("Option", bucket.label))
                    .annotation(position: (bucket.mean ?? 0) >= 0 ? .trailing : .leading) { countLabel(bucket) }
            } else {
                BarMark(
                    x: .value("Group", bucket.label), yStart: .value("Baseline", 0),
                    yEnd: .value("Mean", bucket.mean ?? 0))
                    .annotation(position: (bucket.mean ?? 0) >= 0 ? .top : .bottom) { countLabel(bucket) }
            }
        }
        .foregroundStyle(Color.accentColor)
        .modifier(ValueAxisModifier(horizontal: horizontal, domain: plottedDomain, desiredCount: tickCount))
        // Keep annotation clearance outside the plot. Padding the plot itself
        // moves the rendered zero baseline away from the zero axis mark.
        .padding(.vertical, horizontal ? 8 : 12)
        .frame(height: horizontal ? CGFloat(max(plotted.count, 1)) * 52 : 260)
        .accessibilityChartDescriptor(
            BucketChartDescriptor(title: title, buckets: plotted, valueDomain: plottedDomain, horizontal: horizontal))
    }

    private var tickCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 3 : 6
    }

    @ViewBuilder
    private func countLabel(_ bucket: BucketStat) -> some View {
        Text("\(bucket.count)")
            .font(.caption2)
            .dynamicTypeSize(.large)
            .foregroundStyle(.secondary)
    }
}

/// Applies the reduced-tick-count axis to whichever axis carries the numeric value,
/// since `BucketBarChart` swaps x and y between its vertical and horizontal layouts.
private struct ValueAxisModifier: ViewModifier {
    let horizontal: Bool
    let domain: ClosedRange<Double>
    let desiredCount: Int

    func body(content: Content) -> some View {
        if horizontal {
            content
                .chartXScale(domain: domain, range: .plotDimension(startPadding: 0, endPadding: 0))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: desiredCount)) }
        } else {
            content
                .chartYScale(domain: domain, range: .plotDimension(startPadding: 0, endPadding: 0))
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: desiredCount)) }
        }
    }
}

/// A cheap `AXChartDescriptorRepresentable` shared by every bucket bar chart: one
/// categorical axis of bucket labels, one numeric axis of means, counts carried as an
/// additional value VoiceOver can read per data point.
struct BucketChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let buckets: [BucketStat]
    let valueDomain: ClosedRange<Double>
    let horizontal: Bool

    func makeChartDescriptor() -> AXChartDescriptor {
        let categoryAxis = AXCategoricalDataAxisDescriptor(
            title: horizontal ? "Option" : "Group", categoryOrder: buckets.map(\.label))
        let numericAxis = AXNumericDataAxisDescriptor(
            title: "Mean",
            range: valueDomain,
            gridlinePositions: []
        ) { $0.formatted(.number.precision(.fractionLength(1))) }
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: false,
            dataPoints: buckets.map { bucket in
                AXDataPoint(x: bucket.label, y: bucket.mean ?? 0)
            }
        )
        return AXChartDescriptor(
            title: title, summary: nil,
            // AXChartDescriptor models the categorical buckets on x and numeric
            // means on y even when the Swift Charts marks are rotated horizontally.
            // The numeric range still matches the visual value axis in both layouts.
            xAxis: categoryAxis,
            yAxis: numericAxis,
            additionalAxes: [], series: [series])
    }
}
