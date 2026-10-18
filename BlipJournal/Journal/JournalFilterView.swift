import BlipJournalCore
import SwiftUI

/// The Journal's filter and sort sheet. Edits apply live through the bindings, so the
/// list behind the sheet is already up to date when it closes.
struct JournalFilterView: View {
    @Binding var filter: JournalFilter
    @Binding var sort: JournalSort
    /// The surveys a person can pick, in display order.
    let surveys: [Survey]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Survey") {
                Picker("Survey", selection: surveyId) {
                    Text("All surveys").tag(String?.none)
                    ForEach(surveys) { survey in
                        Text(survey.isArchived ? "\(survey.name) (archived)" : survey.name)
                            .tag(Optional(survey.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Show") {
                Picker("Source", selection: $filter.source) {
                    Text("All").tag(JournalSource.any)
                    Text("Prompted").tag(JournalSource.prompted)
                    Text("Manual").tag(JournalSource.manual)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Source")
                Picker("Status", selection: $filter.status) {
                    Text("All").tag(JournalStatus.any)
                    Text("Completed").tag(JournalStatus.completed)
                    Text("Drafts").tag(JournalStatus.draft)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Status")
            }

            answerSection
            sortSection
        }
        .blipScreen("Filter and sort", titleStyle: .inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Reset") {
                    filter = JournalFilter()
                    sort = .newestFirst
                }
                .disabled(!filter.isActive && sort == .newestFirst)
                .accessibilityLabel("Reset filters and sort")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .accessibilityLabel("Close filters")
            }
        }
    }

    // MARK: Survey

    private var selectedSurvey: Survey? {
        filter.surveyId.flatMap { id in surveys.first { $0.id == id } }
    }

    /// Changing survey clears what pointed into the previous one.
    private var surveyId: Binding<String?> {
        Binding(
            get: { filter.surveyId },
            set: { newValue in
                guard newValue != filter.surveyId else { return }
                filter.surveyId = newValue
                filter.answer = nil
                if !sort.isChronological { sort = .newestFirst }
            })
    }

    // MARK: Answer

    @ViewBuilder
    private var answerSection: some View {
        if let survey = selectedSurvey {
            let questions = filterableQuestions(in: survey)
            Section {
                Picker("Question", selection: answerQuestionId(in: survey)) {
                    Text("Any answer").tag(String?.none)
                    ForEach(questions) { question in
                        Text(question.label).tag(Optional(question.id))
                    }
                }
                .pickerStyle(.menu)
                answerValuePicker(in: survey)
            } header: {
                Text("Answer")
            } footer: {
                if questions.isEmpty {
                    Text("This survey has no choice or yes/no questions to filter on.")
                }
            }
        } else {
            Section("Answer") {
                Text("Choose a survey to filter or sort by an answer.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Active choice and yes/no questions, plus the filtered question if it has since
    /// been archived, so the picker can still show the current selection.
    private func filterableQuestions(in survey: Survey) -> [Question] {
        var questions = survey.activeQuestions.filter { JournalAnswerFilter.defaultCondition(for: $0) != nil }
        if let id = filter.answer?.questionId, !questions.contains(where: { $0.id == id }),
           let archived = survey.questions.first(where: { $0.id == id }) {
            questions.append(archived)
        }
        return questions
    }

    private func answerQuestionId(in survey: Survey) -> Binding<String?> {
        Binding(
            get: { filter.answer?.questionId },
            set: { newValue in
                guard newValue != filter.answer?.questionId else { return }
                filter.answer = newValue
                    .flatMap { id in survey.questions.first { $0.id == id } }
                    .flatMap(JournalAnswerFilter.defaultCondition(for:))
            })
    }

    @ViewBuilder
    private func answerValuePicker(in survey: Survey) -> some View {
        switch filter.answer {
        case .option(let questionId, let optionId)?:
            if let question = survey.questions.first(where: { $0.id == questionId }) {
                Picker("Is", selection: Binding(
                    get: { optionId },
                    set: { filter.answer = .option(questionId: questionId, optionId: $0) }
                )) {
                    ForEach(pickableOptions(of: question, selected: optionId)) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel(question.kind == .multiChoice ? "Includes" : "Is")
            }
        case .yesNo(let questionId, let value)?:
            Picker("Is", selection: Binding(
                get: { value },
                set: { filter.answer = .yesNo(questionId: questionId, value: $0) }
            )) {
                Text("Yes").tag(true)
                Text("No").tag(false)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Answer is")
        case nil:
            EmptyView()
        }
    }

    /// Active options in order, plus the selected one if it has since been archived.
    private func pickableOptions(of question: Question, selected: String) -> [ChoiceOption] {
        var options = question.activeOptions
        if !options.contains(where: { $0.id == selected }),
           let archived = question.options.first(where: { $0.id == selected }) {
            options.append(archived)
        }
        return options
    }

    // MARK: Sort

    private var sortSection: some View {
        Section("Sort") {
            Picker("Order", selection: $sort) {
                Text("Newest first").tag(JournalSort.newestFirst)
                Text("Oldest first").tag(JournalSort.oldestFirst)
                if let survey = selectedSurvey {
                    ForEach(sortableQuestions(in: survey)) { question in
                        Text("\(question.label): highest first")
                            .tag(JournalSort.answer(questionId: question.id, descending: true))
                        Text("\(question.label): lowest first")
                            .tag(JournalSort.answer(questionId: question.id, descending: false))
                    }
                }
            }
            .pickerStyle(.menu)
        }
    }

    /// Active scale and spectrum questions, plus the sorted question if archived since.
    private func sortableQuestions(in survey: Survey) -> [Question] {
        let isNumeric: (Question) -> Bool = { $0.kind == .scale || $0.kind == .spectrum }
        var questions = survey.activeQuestions.filter(isNumeric)
        if let id = sort.questionId, !questions.contains(where: { $0.id == id }),
           let archived = survey.questions.first(where: { $0.id == id && isNumeric($0) }) {
            questions.append(archived)
        }
        return questions
    }
}
