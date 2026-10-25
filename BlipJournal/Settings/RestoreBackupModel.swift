import Foundation
import Observation
import BlipJournalCore

/// State of the restore screen. The decoding, the version check and the replace itself
/// live in BlipJournalCore; this holds the chosen backup, the "saved current data" flag
/// and the wording of failures. The save step reuses `ExportModel` (JSON backup file,
/// protected temporary directory, clean-up) rather than writing its own.
@MainActor @Observable
final class RestoreBackupModel {
    private let appModel: AppModel
    /// Writes and cleans up the backup of current data, exactly as the Export screen does.
    let exporter: ExportModel

    private(set) var backup: Backup?
    private(set) var current: BackupSummary
    /// Whether the person completed the share sheet for a backup of current data on this
    /// screen. Choosing another file resets it, since the data on the phone is the same
    /// but the question being asked is new.
    private(set) var savedCurrentData = false
    private(set) var didRestore = false
    var errorMessage: String?

    init(appModel: AppModel) {
        self.appModel = appModel
        self.exporter = ExportModel(store: appModel.store)
        self.exporter.format = .jsonBackup
        self.current = Self.currentSummary(appModel.store)
    }

    var backupSummary: BackupSummary? { backup?.summary }

    /// Reads and validates the chosen file. Writes nothing to the store.
    func load(_ result: Result<URL, Error>) {
        backup = nil
        savedCurrentData = false
        didRestore = false
        do {
            let url = try result.get()
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            backup = try BackupExporter.decodeForRestore(Data(contentsOf: url))
            current = Self.currentSummary(appModel.store)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// The JSON backup of current data, for the share sheet.
    func makeCurrentBackupFile() throws -> URL {
        exporter.format = .jsonBackup
        return try exporter.makeFile()
    }

    func markSavedCurrentData() { savedCurrentData = true }

    func cleanUp() { exporter.cleanUp() }

    /// Replaces the database with the chosen backup, then resets notifications and
    /// refreshes the app, as delete-all does.
    func restore() async throws {
        guard let backup else { return }
        try await DeleteAllDataModel.reset(appModel: appModel) { try self.appModel.store.restore(backup) }
        self.backup = nil
        savedCurrentData = false
        didRestore = true
        current = Self.currentSummary(appModel.store)
    }

    static func message(for error: Error) -> String {
        guard let restoreError = error as? RestoreError else {
            return "Blip Journal could not restore from that file. \(error.localizedDescription)"
        }
        switch restoreError {
        case .newerSchema:
            return "This backup was made by a newer version of Blip Journal. Update the app to restore it. Nothing was changed."
        case .unreadable:
            return "This file is not a Blip Journal backup, or it is damaged. Nothing was changed."
        }
    }

    private static func currentSummary(_ store: Store) -> BackupSummary {
        (try? store.summary()) ?? BackupSummary(exportedAt: nil, surveys: 0, entries: 0)
    }
}
