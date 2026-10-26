import Foundation
import Testing
@testable import BlipJournalCore

/// The bundled templates are survey files like any other: each one must read, match the
/// schema and import, or the gallery would offer something that cannot be added.
@Suite("SurveyTemplateGallery")
struct SurveyTemplateGalleryTests {
    typealias Gallery = SurveyTemplateGallery
    typealias Support = SurveyFileTestSupport

    private static func contents(_ template: Gallery.Template) throws -> SurveyFileContents {
        try SurveyFile.decode(contentsOf: template.url).get()
    }

    @Test("every bundled template reads through the survey file reader and imports", arguments: Gallery.templates)
    func templateImports(_ template: Gallery.Template) throws {
        let result = SurveyFile.decode(contentsOf: template.url)
        if case .failure(let error) = result {
            Issue.record("\(template.id): \(error.issues.map { "\($0.location): \($0.message)" })")
            return
        }
        let contents = try result.get()
        let imported = try Store.inMemory().importSurvey(contents)
        #expect(imported.activeQuestions.count == contents.questions.count)
        #expect(!imported.sampling.isEnabled)
    }

    @Test("every bundled template validates against the published schema", arguments: Gallery.templates)
    func templateMatchesSchema(_ template: Gallery.Template) throws {
        let schema = Support.repositoryRoot.appendingPathComponent("docs/survey-format.schema.json")
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: template.url))
        #expect(try SchemaValidator(contentsOf: schema).errors(in: json) == [])
    }

    @Test("every template is short to answer and has a purpose", arguments: Gallery.templates)
    func templateIsShort(_ template: Gallery.Template) throws {
        let questionCount = try Self.contents(template).questions.count
        #expect((3...6).contains(questionCount))
        #expect(!template.purpose.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    @Test("template wording makes no diagnostic, treatment or therapy claims", arguments: Gallery.templates)
    func templateWording(_ template: Gallery.Template) throws {
        let contents = try Self.contents(template)
        var texts = [contents.name, template.purpose]
        for question in contents.questions {
            texts.append(question.label)
            texts += question.options.map(\.label)
            texts += question.scale.map { [$0.minLabel, $0.maxLabel] } ?? []
            texts += question.spectrum?.zones.map(\.label) ?? []
        }
        let words = texts.joined(separator: " ").lowercased()
        for stem in ["diagnos", "therap", "treat", "symptom", "disorder", "clinic", "patient", "depress", "addict", "cure"] {
            #expect(!words.contains(stem), "\(template.id) contains \"\(stem)\"")
        }
    }

    @Test("the gallery lists exactly the files in the Templates folder, each once")
    func catalogMatchesFolder() throws {
        let folder = Support.repositoryRoot
            .appendingPathComponent("BlipJournalCore/Sources/BlipJournalCore/SurveyFile/Templates")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { !$0.hasPrefix(".") }
        let ids = Gallery.templates.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(files) == Set(ids.map { "\($0).\(Gallery.fileExtension)" }))
    }

    @Test("template names are all different")
    func namesAreDistinct() throws {
        let names = try Gallery.templates.map { try Self.contents($0).name }
        #expect(Set(names).count == names.count)
    }

    @Test("the template the default survey reads is in the gallery")
    func defaultSurveyIsATemplate() {
        #expect(Gallery.templates.contains { $0.id == Gallery.defaultSurveyTemplateId })
    }
}
