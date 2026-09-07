/// Version marker for the on-disk schema BlipJournalCore reads and writes.
///
/// Deliberately not named `BlipJournalCore`: a type with the module's name shadows the
/// module itself, so `BlipJournalCore.Survey` would fail to resolve in the app target.
///
/// Subsystems live in sibling directories (Model, Storage, Sampling, Export).
/// See docs/PLAN.md at the repo root for the work breakdown.
public enum CoreSchema {
    /// Bumped by a Storage migration whenever the on-disk schema changes.
    public static let version = 3
}
