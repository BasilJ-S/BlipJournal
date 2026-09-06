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

    var body: some View {
        Chart(plotted) { bucket in
            if horizontal {
                BarMark(x: .value("Mean", bucket.mean ?? 0), y: .value("Option", bucket.label))
                    .annotation(position: .trailing) { countLabel(bucket) }
            } else {
                BarMark(x: .value("Group", bucket.label), y: .value("Mean", bucket.mean ?? 0))
                    .annotation(position: .top) { countLabel(bucket) }
            }
        }
        .foregroundStyle(Color.accentColor)
        .modifier(ValueAxisModifier(horizontal: horizontal, domain: valueDomain, desiredCount: tickCount))
        .frame(height: horizontal ? CGFloat(max(plotted.count, 1)) * 44 : 220)
        .accessibilityChartDescriptor(BucketChartDescriptor(title: title, buckets: plotted))
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
                .chartXScale(domain: domain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: desiredCount)) }
        } else {
            content
                .chartYScale(domain: domain)
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

    func makeChartDescriptor() -> AXChartDescriptor {
        let means = buckets.map { $0.mean ?? 0 }
        let xAxis = AXCategoricalDataAxisDescriptor(title: "Group", categoryOrder: buckets.map(\.label))
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Mean",
            range: (means.min() ?? 0)...(means.max() ?? 1),
            gridlinePositions: []
        ) { $0.formatted(.number.precision(.fractionLength(1))) }
        let series = AXDataSeriesDescriptor(
            name: title,
            isContinuous: false,
            dataPoints: buckets.map { bucket in
                AXDataPoint(x: bucket.label, y: bucket.mean ?? 0)
            }
        )
        return AXChartDescriptor(title: title, summary: nil, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}
