//
//  ManualSyncService.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import Foundation
import SwiftData

enum ManualSyncService {
    struct BackupInfo {
        let url: URL
        let exportDate: Date
    }

    enum SyncError: LocalizedError {
        case folderNotConfigured
        case cannotAccessFolder
        case noBackupsFound

        var errorDescription: String? {
            switch self {
            case .folderNotConfigured:
                return "No hay carpeta de iCloud Drive configurada."
            case .cannotAccessFolder:
                return "No se pudo acceder a la carpeta de sincronización."
            case .noBackupsFound:
                return "No se encontraron backups en la carpeta configurada."
            }
        }
    }

    private static let bookmarkKey = "manualSyncFolderBookmark"
    private static let lastImportedExportDateKey = "manualSyncLastImportedExportDate"
    private static let lastDismissedExportDateKey = "manualSyncLastDismissedExportDate"
    private static let lastExportedExportDateKey = "manualSyncLastExportedExportDate"
    private static let maxBackupFiles = 2

    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var lastImportedExportDate: Date? {
        UserDefaults.standard.object(forKey: lastImportedExportDateKey) as? Date
    }

    static var lastDismissedExportDate: Date? {
        UserDefaults.standard.object(forKey: lastDismissedExportDateKey) as? Date
    }

    static var lastExportedExportDate: Date? {
        UserDefaults.standard.object(forKey: lastExportedExportDateKey) as? Date
    }

    static func setSyncDirectory(_ url: URL) throws {
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
    }

    static func clearConfiguration() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: lastImportedExportDateKey)
        UserDefaults.standard.removeObject(forKey: lastDismissedExportDateKey)
        UserDefaults.standard.removeObject(forKey: lastExportedExportDateKey)
    }

    @discardableResult
    static func exportToSyncDirectory(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement]
    ) throws -> BackupInfo {
        try withSyncDirectoryAccess { directoryURL in
            let tempURL = try DataExportService.exportData(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements
            )

            let destinationURL = directoryURL.appendingPathComponent(tempURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)

            try pruneBackups(in: directoryURL)

            let exportDate = backupDate(for: destinationURL) ?? Date()
            markExported(exportDate: exportDate)
            return BackupInfo(url: destinationURL, exportDate: exportDate)
        }
    }

    static func latestBackup() throws -> BackupInfo {
        try withSyncDirectoryAccess { directoryURL in
            try latestBackup(in: directoryURL)
        }
    }

    static func importLatestBackup() throws -> (DataExportService.ImportResult, Date) {
        try withSyncDirectoryAccess { directoryURL in
            let latest = try latestBackup(in: directoryURL)
            let result = try DataExportService.importData(from: latest.url)
            return (result, latest.exportDate)
        }
    }

    static func markImported(exportDate: Date) {
        UserDefaults.standard.set(exportDate, forKey: lastImportedExportDateKey)
        UserDefaults.standard.removeObject(forKey: lastDismissedExportDateKey)
    }

    static func markExported(exportDate: Date) {
        UserDefaults.standard.set(exportDate, forKey: lastExportedExportDateKey)
    }

    static func markDismissed(exportDate: Date) {
        UserDefaults.standard.set(exportDate, forKey: lastDismissedExportDateKey)
    }

    @MainActor static func shouldPromptForNewBackup() -> Bool {
        guard let latest = try? latestBackup() else { return false }

        let acknowledgedDate = maxDate(lastImportedExportDate, lastDismissedExportDate)
        let baseline = maxDate(acknowledgedDate, lastExportedExportDate)
        guard let baseline else { return true }
        return latest.exportDate > baseline
    }

    static func syncFolderDisplayName() -> String {
        guard let folderURL = try? resolveSyncDirectory() else { return "No configurada" }
        return folderURL.lastPathComponent
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (l?, r?): return max(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }

    private static func listBackups(in directoryURL: URL) throws -> [BackupInfo] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return files
            .filter { $0.lastPathComponent.hasPrefix("Finance_backup_") && $0.pathExtension.lowercased() == "json" }
            .map { fileURL in
                let fileModDate = backupDate(for: fileURL)
                let exportDate: Date = fileModDate ?? .distantPast
                return BackupInfo(url: fileURL, exportDate: exportDate)
            }
            .sorted { lhs, rhs in
                if lhs.exportDate != rhs.exportDate {
                    return lhs.exportDate > rhs.exportDate
                }
                return lhs.url.lastPathComponent > rhs.url.lastPathComponent
            }
    }

    private static func pruneBackups(in directoryURL: URL) throws {
        let backups = try listBackups(in: directoryURL)
        guard backups.count > maxBackupFiles else { return }

        for backup in backups.dropFirst(maxBackupFiles) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    private static func backupDate(for fileURL: URL) -> Date? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private static func latestBackup(in directoryURL: URL) throws -> BackupInfo {
        let backups = try listBackups(in: directoryURL)
        guard let latest = backups.first else {
            throw SyncError.noBackupsFound
        }
        return latest
    }

    private static func resolveSyncDirectory() throws -> URL {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw SyncError.folderNotConfigured
        }

        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            let refreshed = try resolvedURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }

        return resolvedURL
    }

    static func withSyncDirectoryAccess<T>(_ action: (URL) throws -> T) throws -> T {
        let folderURL = try resolveSyncDirectory()
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        guard didAccess else {
            throw SyncError.cannotAccessFolder
        }

        return try action(folderURL)
    }

    static func withSyncDirectoryAccessAsync<T>(_ action: (URL) async throws -> T) async throws -> T {
        let folderURL = try resolveSyncDirectory()
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        guard didAccess else {
            throw SyncError.cannotAccessFolder
        }

        return try await action(folderURL)
    }
}
