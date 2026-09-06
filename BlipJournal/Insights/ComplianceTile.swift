import SwiftUI
import BlipJournalCore

/// The response-rate tile: the rate as a percentage, or "No prompts yet" when there
/// are none in range, with answered/missed/dismissed/pending counts in a row.
struct ComplianceTile: View {
    let stats: ComplianceStats
    let accessibilitySummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(rateText)
                .font(.title2.weight(.semibold))
            HStack(spacing: 20) {
                statItem("Answered", stats.answered)
                statItem("Missed", stats.missed)
                statItem("Dismissed", stats.dismissed)
                statItem("Pending", stats.pending)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var rateText: String {
        guard let rate = stats.rate else { return "No prompts yet" }
        return rate.formatted(.percent.precision(.fractionLength(0)))
    }

    private func statItem(_ label: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
