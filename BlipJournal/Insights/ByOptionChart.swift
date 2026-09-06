import SwiftUI
import BlipJournalCore

/// The "By option" section: a picker over the survey's active choice questions, then
/// a horizontal bar chart of the scale's mean per option, in the order `Analytics`
/// returned it.
struct ByOptionChart: View {
    let choiceQuestions: [Question]
    @Binding var selectedChoiceQuestion: Question?
    let buckets: [BucketStat]
    let valueDomain: ClosedRange<Double>
    let accessibilitySummary: String
    let emptyReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if choiceQuestions.count > 1 {
                Picker("Question", selection: $selectedChoiceQuestion) {
                    ForEach(choiceQuestions) { question in
                        Text(question.label).tag(Optional(question))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("By option question")
            }
            if let emptyReason {
                ContentUnavailableView("By option", systemImage: "chart.bar", description: Text(emptyReason))
            } else {
                BucketBarChart(title: "By option", buckets: buckets, valueDomain: valueDomain, horizontal: true)
                    .accessibilityLabel(accessibilitySummary)
            }
        }
    }
}
