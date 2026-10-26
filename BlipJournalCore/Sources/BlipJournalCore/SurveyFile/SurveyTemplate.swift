import Foundation

/// The survey a fresh install starts with.
///
/// This is a factory, not stored state: every call mints new identifiers, so the
/// template can be used to seed a first survey and again whenever the user wants
/// another copy without the two sharing identity.
public enum SurveyTemplate {
    /// The default survey from the README, with the default schedule switched on: the
    /// bundled `mood-and-feelings` template (``SurveyTemplateGallery``), read through
    /// ``SurveyFile/decode(contentsOf:)`` like every other survey file, so the default
    /// and the gallery's copy of it are one file.
    ///
    /// Positions start at 0 in file order. Every identifier in the returned survey is
    /// freshly generated, so two calls are equal in content and different in identity.
    ///
    /// - Parameter now: The creation timestamp to stamp on the survey.
    public static func makeDefault(now: Date = Date()) -> Survey {
        let id = SurveyTemplateGallery.defaultSurveyTemplateId
        switch SurveyFile.decode(contentsOf: SurveyTemplateGallery.url(for: id)) {
        case .success(let contents):
            return Survey(
                name: contents.name,
                createdAt: now,
                sampling: contents.sampling,
                journalSummaryQuestionIds: contents.journalSummaryQuestionIds,
                questions: contents.questions
            )
        case .failure(let error):
            // The file ships inside this module and the tests read it on every run, so
            // reaching this means a broken build, not anything a person did.
            preconditionFailure("The bundled \(id) template does not read: \(error.issues)")
        }
    }
}
