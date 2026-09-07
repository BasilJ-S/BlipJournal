import BlipJournalCore
import SwiftUI

struct SamplingSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let surveyId: String
    @State private var config = SamplingConfig()
    @State private var preview: NotificationPreview = .default
    @State private var customMessage = ""
    @State private var errorMessage: String?
    private var errors: [SamplingConfig.ValidationError] { config.validationErrors }
    private var effectivePreview: NotificationPreview {
        Self.effectivePreview(mode: mode, customMessage: customMessage)
    }

    var body: some View {
        Form {
            Section("Schedule") {
                Toggle("Enable sampling", isOn: $config.isEnabled)
                Stepper("Prompts per day: \(config.promptsPerDay)", value: $config.promptsPerDay, in: 0...20)
                Stepper("Minimum gap: \(config.minGapMinutes) minutes", value: $config.minGapMinutes, in: 0...1440)
                Stepper("Expiry: \(config.expiryMinutes) minutes", value: $config.expiryMinutes, in: 1...240)
                minutePicker("Window starts", minutes: $config.windowStartMinutes)
                minutePicker("Window ends", minutes: $config.windowEndMinutes)
                ForEach(errors, id: \.self) { Text(errorText($0)).foregroundStyle(.red).font(.footnote) }
                if config.isEnabled && (try? appModel.store.survey(surveyId))?.map({ $0.activeQuestions.isEmpty }) == true { Text("Add a question before enabling sampling.").foregroundStyle(.red).font(.footnote) }
            }
            Section("Notification preview") {
                Picker("Preview", selection: Binding(get: { mode }, set: { setMode($0) })) { Text("Private").tag(0); Text("Survey name").tag(1); Text("Custom").tag(2) }
                if case .custom = preview { TextField("Notification message", text: $customMessage); Text("This text may appear on your lock screen.").font(.footnote).foregroundStyle(.secondary) }
                if let survey = try? appModel.store.survey(surveyId) { let content = effectivePreview.content(surveyName: survey.name); Text("Title: \(content.title)"); Text("Body: \(content.body)") }
            }
            Section { Text("A maximum of 60 prompts can be scheduled at once.").font(.footnote).foregroundStyle(.secondary) }
        }
        .blipScreen("Sampling")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!errors.isEmpty || (config.isEnabled && ((try? appModel.store.survey(surveyId))?.map { $0.activeQuestions.isEmpty } ?? false)) || !effectivePreview.isValid) } }
        .onAppear { load() }
        .alert("Could not save sampling", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }
    private var mode: Int { switch preview { case .private: 0; case .surveyName: 1; case .custom: 2 } }
    static func effectivePreview(mode: Int, customMessage: String) -> NotificationPreview {
        switch mode {
        case 1: .surveyName
        case 2: .custom(message: customMessage)
        default: .private
        }
    }
    private func setMode(_ mode: Int) { preview = mode == 0 ? .private : mode == 1 ? .surveyName : .custom(message: customMessage) }
    private func load() { if let survey = try? appModel.store.survey(surveyId) { config = survey.sampling; preview = survey.notificationPreview; if case .custom(let message) = preview { customMessage = message } } }
    private func save() {
        let requestedPreview = effectivePreview
        Task {
            do {
                guard let survey = try appModel.store.survey(surveyId) else { throw StoreError.notFound }
                let model = EditorModel(store: appModel.store, notifications: appModel.notifications)
                if config != survey.sampling { try await model.saveSampling(surveyId: surveyId, config) }
                if requestedPreview != survey.notificationPreview {
                    try await model.saveNotificationPreview(surveyId: surveyId, requestedPreview)
                }
                try appModel.refresh()
                dismiss()
            } catch { errorMessage = String(describing: error) }
        }
    }
    private func minutePicker(_ title: String, minutes: Binding<Int>) -> some View { Stepper("\(title): \(clock(minutes.wrappedValue))", value: minutes, in: 0...1440, step: 15) }
    private func clock(_ minutes: Int) -> String { minutes == 1440 ? "midnight" : String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    private func errorText(_ error: SamplingConfig.ValidationError) -> String { switch error { case .promptsPerDayOutOfRange: "Prompts per day must be from 0 to 20."; case .windowOutOfRange: "The window must be between midnight and midnight, with a later end."; case .minGapOutOfRange: "Minimum gap must be from 0 to 1440 minutes."; case .gapDoesNotFit: "The prompts and minimum gap do not fit in this window."; case .expiryOutOfRange: "Expiry must be from 1 to 240 minutes." } }
}
