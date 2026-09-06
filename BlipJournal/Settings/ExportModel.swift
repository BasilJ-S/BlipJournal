import Foundation
import Observation
import BlipJournalCore

@MainActor @Observable
final class ExportModel {
    enum Format: CaseIterable, Identifiable {
        case wideCSV, longCSV, jsonBackup
        var id: Self { self }
        var title: String {
            switch self { case .wideCSV: "Wide CSV"; case .longCSV: "Long CSV"; case .jsonBackup: "JSON backup" }
        }
        var detail: String {
            switch self {
            case .wideCSV: "One row per entry, ready for Numbers or Excel."
            case .longCSV: "One row per answer, useful for analysis."
            case .jsonBackup: "A complete backup for a future import."
            }
        }
    }

    enum DateRange: CaseIterable, Identifiable {
        case sevenDays, thirtyDays, ninetyDays, all, custom
        var id: Self { self }
        var title: String {
            switch self { case .sevenDays: "7 days"; case .thirtyDays: "30 days"; case .ninetyDays: "90 days"; case .all: "All"; case .custom: "Custom" }
        }
        var days: Int? {
            switch self { case .sevenDays: 7; case .thirtyDays: 30; case .ninetyDays: 90; case .all, .custom: nil }
        }
    }

    enum ExportError: LocalizedError {
        case surveyNotFound
        case invalidDateRange
        var errorDescription: String? {
            switch self { case .surveyNotFound: "The selected survey could not be found."; case .invalidDateRange: "Choose a valid date range." }
        }
    }

    private let store: Store
    private let calendar: Calendar
    private let fileManager: FileManager
    private let baseDirectory: URL
    private var wroteFiles: [URL] = []

    private(set) var surveys: [Survey] = []
    var selectedSurveyId: String?
    var format: Format = .wideCSV
    var range: DateRange = .all
    var customStart: Date
    var customEnd: Date

    init(store: Store, calendar: Calendar = .autoupdatingCurrent, fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.store = store
        self.calendar = calendar
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlipJournal", isDirectory: true)
        let today = calendar.startOfDay(for: Date())
        self.customEnd = today
        self.customStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        self.surveys = (try? store.surveys(includeArchived: true)) ?? []
        self.selectedSurveyId = self.surveys.first?.id
    }

    var exportsDirectory: URL { baseDirectory.appendingPathComponent("exports", isDirectory: true) }

    func makeFile(now: Date = Date()) throws -> URL {
        try fileManager.createDirectory(at: exportsDirectory, withIntermediateDirectories: true, attributes: protectionAttributes)
        #if os(iOS)
        try fileManager.setAttributes(protectionAttributes, ofItemAtPath: exportsDirectory.path)
        #endif
        let url: URL
        let data: Data
        if format == .jsonBackup {
            data = try BackupExporter.json(store.backup(now: now))
            url = exportsDirectory.appendingPathComponent("BlipJournal-backup-\(fileDate(now)).json")
        } else {
            guard let id = selectedSurveyId, let survey = surveys.first(where: { $0.id == id }) else { throw ExportError.surveyNotFound }
            var snapshot = try store.exportSnapshot(surveyId: id)
            snapshot.entries = try filteredEntries(snapshot.entries, now: now)
            let text = format == .wideCSV ? CSVExporter.wide(snapshot, calendar: calendar) : CSVExporter.long(snapshot, calendar: calendar)
            data = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
            let suffix = format == .wideCSV ? "wide" : "long"
            url = exportsDirectory.appendingPathComponent("BlipJournal-\(slug(survey.name))-\(fileDate(now))-\(suffix).csv")
        }
        try data.write(to: url, options: .completeFileProtection)
        wroteFiles.append(url)
        return url
    }

    func cleanUp() {
        for url in wroteFiles { try? fileManager.removeItem(at: url) }
        wroteFiles.removeAll()
        if let contents = try? fileManager.contentsOfDirectory(at: exportsDirectory, includingPropertiesForKeys: nil) {
            for url in contents { try? fileManager.removeItem(at: url) }
        }
    }

    func setRange(_ newValue: DateRange, now: Date = Date()) {
        if newValue == .custom && range != .custom {
            if range == .all { customEnd = now; customStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now }
            else if let days = range.days { customEnd = now; customStart = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now }
        }
        range = newValue
    }

    private func filteredEntries(_ entries: [ExportEntry], now: Date) throws -> [ExportEntry] {
        guard range != .all else { return entries }
        let bounds: (Date, Date)
        if let days = range.days {
            let end = now
            let startDay = calendar.startOfDay(for: now)
            bounds = (calendar.date(byAdding: .day, value: -(days - 1), to: startDay) ?? startDay, end)
        } else {
            let start = calendar.startOfDay(for: customStart)
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? start
            guard start <= calendar.startOfDay(for: customEnd), customStart <= now else { throw ExportError.invalidDateRange }
            bounds = (start, min(next, now))
        }
        return entries.filter { $0.entry.startedAt >= bounds.0 && $0.entry.startedAt < bounds.1 }
    }

    private var protectionAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        return [.protectionKey: FileProtectionType.complete]
        #else
        return [:]
        #endif
    }
    private func fileDate(_ date: Date) -> String { let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "yyyyMMdd"; return f.string(from: date) }
    private func slug(_ name: String) -> String {
        let scalars = name.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let value = String(scalars).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return String(value.prefix(40)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
