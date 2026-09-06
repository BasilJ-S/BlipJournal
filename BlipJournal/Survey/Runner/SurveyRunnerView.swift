import OpenBlipCore
import SwiftUI

/// Placeholder. Task A3 replaces this file wholesale; the signature is the contract.
struct SurveyRunnerView: View {
    let survey: Survey
    let promptId: String?
    let onFinish: () -> Void

    init(survey: Survey, promptId: String?, onFinish: @escaping () -> Void) {
        self.survey = survey
        self.promptId = promptId
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                survey.name,
                systemImage: "square.and.pencil",
                description: Text("Answering a survey arrives with task A3."))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onFinish() }
                        .accessibilityLabel("Done")
                }
            }
        }
    }
}
