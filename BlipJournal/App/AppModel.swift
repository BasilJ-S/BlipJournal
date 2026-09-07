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
    /// Every prompt still pending, ordered by `scheduledAt`. Used to tell whether a
    /// prompt's window is currently open, for the Journal's "survey open" banner.
    private(set) var pendingPrompts: [Prompt] = []
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
        pendingPrompts = try store.prompts(status: .pending)
        revision &+= 1
    }

    /// Reloads state, since a prompt whose window opened while backgrounded (or while
    /// locked, however long that lasted) needs to be reflected immediately.
    func unlock() {
        isLocked = false
        try? refresh()
    }

    func didEnterBackground(at now: Date) {
        backgroundedAt = now
    }

    /// The earliest pending prompt whose window is currently open, if any.
    func openPrompt(at now: Date) -> Prompt? {
        pendingPrompts.first { $0.scheduledAt <= now && !$0.isExpired(at: now) }
    }

    /// Applies the lock policy against the last background time, then asks the
    /// notification coordinator to replan.
    ///
    /// Skips the store read when the app is about to lock: `RootView` is torn down for
    /// `LockView` regardless, so refreshing here would be a synchronous SQLite read on
    /// every foreground transition — including ones as brief as Control Centre — that
    /// nothing on screen would use before `unlock()` reloads anyway.
    func willEnterForeground(at now: Date) {
        let shouldLock = lockPolicy.shouldLock(backgroundedAt: backgroundedAt, now: now)
        backgroundedAt = nil
        if shouldLock {
            isLocked = true
        } else {
            try? refresh()
        }
        let notifications = notifications
        Task { await notifications.refresh(now: now) }
    }
}
