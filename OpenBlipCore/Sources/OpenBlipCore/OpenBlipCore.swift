/// OpenBlipCore holds every piece of logic that does not need a screen:
/// the domain model, GRDB storage, prompt sampling, and export.
///
/// Subsystems live in sibling directories (Model, Storage, Sampling, Export).
/// See docs/PLAN.md at the repo root for the work breakdown.
public enum OpenBlipCore {
    /// Bumped by a Storage migration whenever the on-disk schema changes.
    public static let schemaVersion = 0
}
