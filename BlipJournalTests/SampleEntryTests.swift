#if DEBUG
import Foundation
import BlipJournalCore
import Testing
@testable import BlipJournal

/// The debug "Add sample entry" button has no other coverage: it cannot be driven from
/// a unit test through the toolbar, so its writer is tested directly. It only exists in
/// DEBUG builds, which is what the test bundle is built as.
@MainActor
struct SampleEntryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func seededStore() throws -> (Store, Survey) {
        let store = try Store.inMemory()
        let template = SurveyTemplate.makeDefault(now: now)
        let survey = try store.createSurvey(
            name: template.name, sampling: template.sampling, questions: template.questions, now: now)
        return (store, survey)
    }

    @Test func writesOneCompletedEntryWithinTheLastFortnight() throws {
        let (store, survey) = try seededStore()
        var rng = SeededRandomNumberGenerator(seed: 42)
        try SampleEntry.write(to: store, survey: survey, now: now, using: &rng)

        let entries = try store.entries(surveyId: nil, from: nil, to: nil)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.surveyId == survey.id)
        #expect(entry.completedAt != nil)
        #expect(entry.startedAt <= now)
        #expect(entry.startedAt >= now.addingTimeInterval(-14 * 86_400))
        if let completedAt = entry.completedAt {
            #expect(completedAt > entry.startedAt)
            #expect(completedAt <= now)
        }
    }

    @Test func answersReferenceRealQuestionsAndOptions() throws {
        let (store, survey) = try seededStore()
        var rng = SeededRandomNumberGenerator(seed: 42)
        try SampleEntry.write(to: store, survey: survey, now: now, using: &rng)
        let entry = try #require(try store.entries(surveyId: nil, from: nil, to: nil).first)
        let answers = try store.answers(entryId: entry.id)

        #expect(!answers.isEmpty)
        let questionsById = Dictionary(uniqueKeysWithValues: survey.questions.map { ($0.id, $0) })
        let versionIds = try store.currentQuestionVersionIds(surveyId: survey.id)
        for answer in answers {
            let question = try #require(questionsById[answer.questionId])
            #expect(answer.answeredAt >= entry.startedAt)
            #expect(answer.answeredAt <= (entry.completedAt ?? now))
            #expect(answer.value.kind == question.kind)
            #expect(answer.questionVersionId == versionIds[question.id])
            switch answer.value {
            case .scale(let value):
                let scale = try #require(question.scale)
                #expect((scale.min...scale.max).contains(value))
            case .spectrum(let value):
                #expect((0...1).contains(value))
            case .single(let optionId):
                #expect(question.options.contains { $0.id == optionId })
            case .multi(let optionIds):
                #expect(optionIds.allSatisfy { id in question.options.contains { $0.id == id } })
                #expect(Set(optionIds).count == optionIds.count)
            case .yesNo, .text:
                break
            }
        }
    }

    /// Half the sample entries are prompted. A fixed seed exercises both kinds, and
    /// every prompted one must carry a real prompt row marked answered, so the Journal
    /// can show both badges.
    @Test func promptedEntriesCarryAnAnsweredPrompt() throws {
        let (store, survey) = try seededStore()
        var rng = SeededRandomNumberGenerator(seed: 42)
        for _ in 0..<25 {
            try SampleEntry.write(to: store, survey: survey, now: now, using: &rng)
        }
        let entries = try store.entries(surveyId: nil, from: nil, to: nil)
        #expect(entries.count == 25)

        let prompts = Dictionary(uniqueKeysWithValues: try store.prompts(status: nil).map { ($0.id, $0) })
        let prompted = entries.filter(\.isPrompted)
        #expect(!prompted.isEmpty)
        #expect(prompted.count < entries.count)
        for entry in prompted {
            let promptId = try #require(entry.promptId)
            let prompt = try #require(prompts[promptId])
            #expect(prompt.surveyId == survey.id)
            #expect(prompt.status == .answered)
            #expect(prompt.scheduledAt <= entry.startedAt)
            #expect(prompt.day == DayKey.string(for: prompt.scheduledAt, calendar: .current))
        }
    }
}
#endif
