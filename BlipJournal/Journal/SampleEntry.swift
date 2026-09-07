#if DEBUG
import Foundation
import BlipJournalCore

/// Debug-only: writes one completed entry with random answers so screens can be checked
/// by eye in the simulator. Half the entries are prompted, with an answered prompt row,
/// so both badges show up.
enum SampleEntry {
    static func write(to store: Store, survey: Survey, now: Date = Date()) throws {
        var rng = SystemRandomNumberGenerator()
        try write(to: store, survey: survey, now: now, using: &rng)
    }

    static func write(
        to store: Store, survey: Survey, now: Date,
        using rng: inout some RandomNumberGenerator
    ) throws {
        let duration = TimeInterval.random(in: 30...180, using: &rng)
        let startedAt = now.addingTimeInterval(
            -TimeInterval.random(in: duration..<(14 * 86_400), using: &rng))
        let completedAt = startedAt.addingTimeInterval(duration)
        let versionIds = try store.currentQuestionVersionIds(surveyId: survey.id)

        var promptId: String?
        if Bool.random(using: &rng) {
            let scheduledAt = startedAt.addingTimeInterval(-60)
            let prompt = Prompt(
                surveyId: survey.id,
                day: DayKey.string(for: scheduledAt, calendar: .current),
                scheduledAt: scheduledAt,
                expiresAt: scheduledAt.addingTimeInterval(TimeInterval(survey.sampling.expiryMinutes * 60)),
                status: .answered,
                respondedAt: completedAt)
            try store.insertPrompts([prompt])
            promptId = prompt.id
        }

        let entry = Entry(surveyId: survey.id, promptId: promptId, startedAt: startedAt, completedAt: completedAt)
        var answers: [Answer] = []
        for (index, question) in survey.activeQuestions.enumerated() {
            guard let versionId = versionIds[question.id],
                  let value = randomValue(for: question, using: &rng) else { continue }
            answers.append(Answer(
                entryId: entry.id,
                questionId: question.id,
                questionVersionId: versionId,
                answeredAt: startedAt.addingTimeInterval(
                    duration * Double(index + 1) / Double(survey.activeQuestions.count + 1)),
                value: value))
        }
        try store.saveEntry(entry, answers: answers)
    }

    private static func randomValue(for question: Question, using rng: inout some RandomNumberGenerator) -> AnswerValue? {
        switch question.kind {
        case .scale:
            let scale = question.scale ?? ScaleConfig()
            return .scale(Int.random(in: scale.min...scale.max, using: &rng))
        case .spectrum:
            return .spectrum(Double.random(in: 0...1, using: &rng))
        case .singleChoice:
            guard let option = question.activeOptions.randomElement(using: &rng) else { return nil }
            return .single(optionId: option.id)
        case .multiChoice:
            let count = Int.random(in: 0...min(3, question.activeOptions.count), using: &rng)
            let picked = question.activeOptions.shuffled(using: &rng).prefix(count).map(\.id)
            return .multi(optionIds: picked)
        case .yesNo:
            return .yesNo(Bool.random(using: &rng))
        case .text:
            if Bool.random(using: &rng) { return nil }
            let samples = ["Long meeting, but it went well.", "Quiet afternoon.", "Rushing between things.", ""]
            return .text(samples.randomElement(using: &rng) ?? "")
        }
    }

}
#endif
