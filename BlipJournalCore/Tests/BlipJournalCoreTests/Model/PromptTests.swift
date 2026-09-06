import Foundation
import Testing
import BlipJournalCore

@Suite("Prompt")
struct PromptTests {
    private let scheduledAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var expiresAt: Date { scheduledAt.addingTimeInterval(20 * 60) }

    private func makePrompt(status: PromptStatus = .pending) -> Prompt {
        Prompt(
            surveyId: "survey",
            day: "2026-09-05",
            scheduledAt: scheduledAt,
            expiresAt: expiresAt,
            status: status
        )
    }

    @Test("a pending prompt is not expired before its expiry")
    func notExpiredBefore() {
        let prompt = makePrompt()
        #expect(!prompt.isExpired(at: scheduledAt))
        #expect(!prompt.isExpired(at: expiresAt.addingTimeInterval(-1)))
    }

    @Test("a pending prompt is expired at and after its expiry")
    func expiredAtAndAfter() {
        let prompt = makePrompt()
        #expect(prompt.isExpired(at: expiresAt))
        #expect(prompt.isExpired(at: expiresAt.addingTimeInterval(1)))
        #expect(prompt.isExpired(at: expiresAt.addingTimeInterval(86_400)))
    }

    @Test("a prompt that already has an outcome never expires", arguments: [
        PromptStatus.answered, .missed, .dismissed,
    ])
    func resolvedPromptsNeverExpire(status: PromptStatus) {
        let prompt = makePrompt(status: status)
        #expect(!prompt.isExpired(at: expiresAt.addingTimeInterval(-1)))
        #expect(!prompt.isExpired(at: expiresAt))
        #expect(!prompt.isExpired(at: expiresAt.addingTimeInterval(86_400)))
    }

    @Test("a new prompt is pending with no response time")
    func defaults() {
        let prompt = makePrompt()
        #expect(prompt.status == .pending)
        #expect(prompt.respondedAt == nil)
        #expect(!prompt.id.isEmpty)
    }

    @Test("status raw values are the persisted contract")
    func statusRawValues() {
        #expect(PromptStatus.allCases.map(\.rawValue) == [
            "pending", "answered", "missed", "dismissed",
        ])
    }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        var prompt = makePrompt(status: .answered)
        prompt.respondedAt = scheduledAt.addingTimeInterval(90)
        let data = try JSONEncoder().encode(prompt)
        #expect(try JSONDecoder().decode(Prompt.self, from: data) == prompt)
    }
}
