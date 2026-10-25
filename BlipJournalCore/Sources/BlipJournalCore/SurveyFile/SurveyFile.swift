import Foundation

/// A survey definition read from a survey file: the name, questions, schedule and Journal
/// summary the file describes, with identifiers minted on reading and nothing else.
///
/// The identifiers exist so the contents can be previewed like any survey; they are
/// replaced again by ``Store/importSurvey(_:now:)``, so one value can be imported twice.
public struct SurveyFileContents: Sendable, Equatable {
    public var name: String
    /// Active questions, positions numbered from 0 in file order, options likewise.
    public var questions: [Question]
    /// The file's schedule, absent fields filled from ``SamplingConfig/default``.
    /// `isEnabled` is always true here; importing pauses it.
    public var sampling: SamplingConfig
    /// Identifiers from ``questions``, resolved: the file's own `journalSummary`, or
    /// ``Survey/defaultJournalSummaryQuestionIds(for:)`` when the file has none.
    public var journalSummaryQuestionIds: [String]
}

/// Everything wrong with a survey file. Reading a file never changes anything, so a
/// person can fix every issue and try again.
public struct SurveyFileError: Error, Sendable, Equatable {
    public struct Issue: Sendable, Equatable, Hashable {
        /// Where the problem is, as a path into the file, such as
        /// `questions[2].scale.max`. Empty for the file as a whole.
        public let path: String
        /// The same place for a person, such as "Question 3, scale, max".
        public let location: String
        /// What is wrong and how to fix it, in plain language.
        public let message: String

        init(_ path: FieldPath, _ message: String) {
            self.path = path.text
            self.location = path.location
            self.message = message
        }
    }

    /// At least one, in the order they appear in the file.
    public let issues: [Issue]

    init(issues: [Issue]) {
        self.issues = issues
    }

    init(_ path: FieldPath, _ message: String) {
        self.issues = [Issue(path, message)]
    }
}

/// The survey file format: one survey definition as JSON. `docs/survey-format.md` is the
/// specification; this is its only reader and writer.
///
/// Reading returns a `Result` rather than throwing so callers get ``SurveyFileError``
/// itself without a cast.
public enum SurveyFile {
    /// The newest `formatVersion` this build reads, and the one it writes.
    public static let formatVersion = 1

    /// Reads a survey file. Never touches the store.
    public static func decode(_ data: Data) -> Result<SurveyFileContents, SurveyFileError> {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            return .failure(SurveyFileError(FieldPath(), """
                This isn't valid JSON. Look for a missing comma, quotation mark or bracket.
                """))
        }
        var reader = SurveyFileReader()
        if let contents = reader.readSurvey(root), reader.issues.isEmpty {
            return .success(contents)
        }
        return .failure(SurveyFileError(issues: reader.issues))
    }

    /// Reads pasted text. Anything before the first `{` and after the last `}` is
    /// ignored, so a Markdown code block or an assistant's surrounding sentences do not
    /// get in the way.
    public static func decode(text: String) -> Result<SurveyFileContents, SurveyFileError> {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return decode(Data(text.utf8))
        }
        return decode(Data(text[start...end].utf8))
    }

    /// Reads a file on disk or in a bundle. The caller handles any security scope.
    public static func decode(contentsOf url: URL) -> Result<SurveyFileContents, SurveyFileError> {
        guard let data = try? Data(contentsOf: url) else {
            return .failure(SurveyFileError(FieldPath(), """
                The file couldn't be opened. Try saving it again, or paste its text instead.
                """))
        }
        return decode(data)
    }

    /// Writes the survey's current definition: active questions and options in display
    /// order, the schedule and the Journal summary. Archived definitions, answers,
    /// whether sampling is on, and the notification preview are never written.
    ///
    /// Question ids are `q1`, `q2`, … in display order, used only by `journalSummary`.
    /// The same survey always produces the same bytes.
    public static func encode(_ survey: Survey) -> Data {
        Data((document(for: survey).formatted() + "\n").utf8)
    }

    static func document(for survey: Survey) -> JSONValue {
        let questions = survey.activeQuestions
        var fileIds: [String: String] = [:]
        for (index, question) in questions.enumerated() {
            fileIds[question.id] = "q\(index + 1)"
        }
        let summary = survey.journalSummaryQuestions.compactMap { fileIds[$0.id] }
        return .object([
            .init("formatVersion", .number(Double(formatVersion))),
            .init("name", .string(survey.name)),
            .init("sampling", document(for: survey.sampling)),
            .init("journalSummary", .array(summary.map(JSONValue.string))),
            .init("questions", .array(questions.map { document(for: $0, id: fileIds[$0.id] ?? "") })),
        ])
    }

    private static func document(for sampling: SamplingConfig) -> JSONValue {
        .object([
            .init("promptsPerDay", .number(Double(sampling.promptsPerDay))),
            .init("windowStart", .string(clock(sampling.windowStartMinutes))),
            .init("windowEnd", .string(clock(sampling.windowEndMinutes))),
            .init("minGapMinutes", .number(Double(sampling.minGapMinutes))),
            .init("expiryMinutes", .number(Double(sampling.expiryMinutes))),
        ])
    }

    private static func document(for question: Question, id: String) -> JSONValue {
        var members: [JSONValue.Member] = [
            .init("id", .string(id)),
            .init("kind", .string(question.kind.rawValue)),
            .init("label", .string(question.label)),
            .init("required", .bool(question.isRequired)),
        ]
        switch question.kind {
        case .scale:
            if let scale = question.scale {
                members.append(.init("scale", .object([
                    .init("min", .number(Double(scale.min))),
                    .init("max", .number(Double(scale.max))),
                    .init("minLabel", .string(scale.minLabel)),
                    .init("maxLabel", .string(scale.maxLabel)),
                ])))
            }
        case .spectrum:
            if let spectrum = question.spectrum {
                let zones = spectrum.zones.map { zone in
                    JSONValue.object([
                        .init("label", .string(zone.label)),
                        .init("color", .object([
                            .init("red", .number(zone.color.red)),
                            .init("green", .number(zone.color.green)),
                            .init("blue", .number(zone.color.blue)),
                        ])),
                    ])
                }
                members.append(.init("spectrum", .object([
                    .init("zones", .array(zones)),
                    .init("breakpoints", .array(spectrum.breakpoints.map(JSONValue.number))),
                ])))
            }
        case .singleChoice, .multiChoice:
            members.append(.init("expandable", .bool(question.allowsCustomOptions)))
            members.append(.init("options", .array(question.activeOptions.map { JSONValue.string($0.label) })))
        case .yesNo, .text:
            break
        }
        return .object(members)
    }

    /// `HH:MM` for minutes after midnight; 1440 is `24:00`.
    private static func clock(_ minutes: Int) -> String {
        func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return twoDigits(minutes / 60) + ":" + twoDigits(minutes % 60)
    }
}
