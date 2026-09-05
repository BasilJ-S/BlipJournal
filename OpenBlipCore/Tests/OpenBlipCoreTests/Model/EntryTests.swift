import Foundation
import Testing
import OpenBlipCore

@Suite("Entry")
struct EntryTests {
    @Test("an entry with a prompt is prompted")
    func promptedEntry() {
        let entry = Entry(surveyId: "survey", promptId: "prompt")
        #expect(entry.isPrompted)
    }

    @Test("an entry without a prompt is manual")
    func manualEntry() {
        let entry = Entry(surveyId: "survey")
        #expect(!entry.isPrompted)
        #expect(entry.promptId == nil)
    }

    @Test("a new entry is incomplete")
    func defaults() {
        let entry = Entry(surveyId: "survey")
        #expect(entry.completedAt == nil)
        #expect(!entry.id.isEmpty)
    }

    @Test("round-trips through JSON")
    func roundTrips() throws {
        let started = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let entry = Entry(
            surveyId: "survey",
            promptId: "prompt",
            startedAt: started,
            completedAt: started.addingTimeInterval(25)
        )
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(Entry.self, from: data) == entry)
    }
}

@Suite("AnswerValue")
struct AnswerValueTests {
    private static let cases: [AnswerValue] = [
        .scale(5),
        .single(optionId: "option-a"),
        .multi(optionIds: ["a", "b"]),
        .multi(optionIds: []),
        .yesNo(true),
        .yesNo(false),
        .text("A note, with a comma"),
        .text(""),
    ]

    @Test("every case round-trips through JSON", arguments: AnswerValueTests.cases)
    func roundTrips(value: AnswerValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(AnswerValue.self, from: data) == value)
    }

    @Test("the encoded discriminator names the case, not the question kind")
    func discriminators() throws {
        func kindField(of value: AnswerValue) throws -> String? {
            let data = try JSONEncoder().encode(value)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return object?["kind"] as? String
        }

        #expect(try kindField(of: .scale(5)) == "scale")
        #expect(try kindField(of: .single(optionId: "a")) == "single")
        #expect(try kindField(of: .multi(optionIds: ["a"])) == "multi")
        #expect(try kindField(of: .yesNo(true)) == "yesNo")
        #expect(try kindField(of: .text("hi")) == "text")
    }

    @Test("the payload keys are stable")
    func payloadShape() throws {
        func json(_ value: AnswerValue) throws -> [String: Any] {
            let data = try JSONEncoder().encode(value)
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }

        let scale = try json(.scale(5))
        #expect(scale["value"] as? Int == 5)
        #expect(scale.count == 2)

        let single = try json(.single(optionId: "option-a"))
        #expect(single["optionId"] as? String == "option-a")
        #expect(single.count == 2)

        let multi = try json(.multi(optionIds: ["a", "b"]))
        #expect(multi["optionIds"] as? [String] == ["a", "b"])
        #expect(multi.count == 2)

        let yesNo = try json(.yesNo(false))
        #expect(yesNo["value"] as? Bool == false)
        #expect(yesNo.count == 2)

        let text = try json(.text("hello"))
        #expect(text["value"] as? String == "hello")
        #expect(text.count == 2)
    }

    @Test("hand-written JSON decodes into the matching case")
    func decodesLiteralJSON() throws {
        func decode(_ json: String) throws -> AnswerValue {
            try JSONDecoder().decode(AnswerValue.self, from: Data(json.utf8))
        }

        #expect(try decode(#"{"kind":"scale","value":5}"#) == .scale(5))
        #expect(try decode(#"{"kind":"multi","optionIds":["a","b"]}"#)
            == .multi(optionIds: ["a", "b"]))
        #expect(try decode(#"{"kind":"single","optionId":"x"}"#) == .single(optionId: "x"))
        #expect(try decode(#"{"kind":"yesNo","value":true}"#) == .yesNo(true))
        #expect(try decode(#"{"kind":"text","value":"note"}"#) == .text("note"))
    }

    @Test("an unknown discriminator fails to decode")
    func rejectsUnknownKind() {
        let json = Data(#"{"kind":"nonsense","value":1}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AnswerValue.self, from: json)
        }
    }

    @Test("a payload that does not match its kind fails to decode")
    func rejectsMismatchedPayload() {
        let json = Data(#"{"kind":"scale","optionId":"a"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(AnswerValue.self, from: json)
        }
    }

    @Test("kind maps each case to the question kind it can answer")
    func kinds() {
        #expect(AnswerValue.scale(1).kind == .scale)
        #expect(AnswerValue.single(optionId: "a").kind == .singleChoice)
        #expect(AnswerValue.multi(optionIds: []).kind == .multiChoice)
        #expect(AnswerValue.yesNo(true).kind == .yesNo)
        #expect(AnswerValue.text("").kind == .text)
    }

    @Test("only an empty selection and an empty string are empty")
    func isEmpty() {
        #expect(AnswerValue.multi(optionIds: []).isEmpty)
        #expect(AnswerValue.text("").isEmpty)

        #expect(!AnswerValue.multi(optionIds: ["a"]).isEmpty)
        #expect(!AnswerValue.text("x").isEmpty)
        #expect(!AnswerValue.text(" ").isEmpty)
        #expect(!AnswerValue.scale(0).isEmpty)
        #expect(!AnswerValue.single(optionId: "").isEmpty)
        #expect(!AnswerValue.yesNo(false).isEmpty)
    }
}

@Suite("Answer")
struct AnswerTests {
    @Test("round-trips through JSON")
    func roundTrips() throws {
        let answer = Answer(
            entryId: "entry",
            questionId: "question",
            questionVersionId: "version",
            value: .multi(optionIds: ["a", "b"])
        )
        let data = try JSONEncoder().encode(answer)
        #expect(try JSONDecoder().decode(Answer.self, from: data) == answer)
    }

    @Test("a new answer gets an identifier")
    func defaults() {
        let answer = Answer(
            entryId: "entry",
            questionId: "question",
            questionVersionId: "version",
            value: .yesNo(true)
        )
        #expect(!answer.id.isEmpty)
    }
}
