import Foundation
import Observation
import BlipJournalCore

/// The one object the whole app shares: it owns the `Store`, the notification
/// coordinator, the current survey list, and the lock state.
///
/// Views read it from the environment. Every write goes through `store` directly and is
/// followed by `refresh()`, which is the only way the published lists change.
@MainActor @Observable
final class AppModel {
    let store: Store
    let notifications: any NotificationCoordinating
    /// Active surveys only, sorted as the store returns them.
    private(set) var surveys: [Survey] = []
    /// Every survey, archived included, by identifier. The Journal uses it to name
    /// entries whose survey has since been archived.
    private(set) var surveysById: [String: Survey] = [:]
    /// Every entry of every survey, newest first.
    private(set) var entries: [Entry] = []
    /// Invalidates answer-derived UI after writes that leave the entry itself unchanged.
    private(set) var revision: UInt64 = 0
    /// True from init until `unlock()`, and again whenever the lock policy says so.
    private(set) var isLocked = true
    var lockPolicy = LockPolicy()

    @ObservationIgnored private var backgroundedAt: Date?

    /// Opens the model over `store`, seeding the default survey if the store has never
    /// held one. Seeding checks archived surveys too, so it happens once, ever.
    init(store: Store, notifications: any NotificationCoordinating, now: Date = Date()) throws {
        self.store = store
        self.notifications = notifications
        if try store.surveys(includeArchived: true).isEmpty {
            let template = SurveyTemplate.makeDefault(now: now)
            try store.createSurvey(
                name: template.name, sampling: template.sampling, questions: template.questions, now: now)
        }
        try refresh()
    }

    /// The production model: the store under Application Support and a real notification
    /// coordinator, attached to the app-wide notification delegate so a cold launch from
    /// a notification tap is not lost while the store opens.
    static func live() throws -> AppModel {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlipJournal", isDirectory: true)
        let store = try Store.open(at: directory)
        #if DEBUG
        // The simulator has no Data Protection and reports no class; a device reports
        // NSFileProtectionComplete here.
        let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        let protection = attributes?[.protectionKey].map { String(describing: $0) } ?? "not reported"
        print("BlipJournal store at \(directory.path), protection class: \(protection)")
        #endif
        let coordinator = NotificationCoordinator(store: store, client: LiveNotificationCenterClient())
        coordinator.attach(to: .shared)
        return try AppModel(store: store, notifications: coordinator)
    }

    /// Reloads surveys and entries from the store. Call after any write.
    func refresh() throws {
        let all = try store.surveys(includeArchived: true)
        surveysById = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        surveys = all.filter { !$0.isArchived }
        entries = try store.entries(surveyId: nil, from: nil, to: nil).reversed()
        revision &+= 1
    }

    func unlock() {
        isLocked = false
    }

    func didEnterBackground(at now: Date) {
        backgroundedAt = now
    }

    /// Applies the lock policy against the last background time, then asks the
    /// notification coordinator to replan.
    func willEnterForeground(at now: Date) {
        if lockPolicy.shouldLock(backgroundedAt: backgroundedAt, now: now) {
            isLocked = true
        }
        backgroundedAt = nil
        let notifications = notifications
        Task { await notifications.refresh(now: now) }
    }
}
