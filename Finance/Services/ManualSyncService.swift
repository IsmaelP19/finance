//
//  ManualSyncService.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import Foundation
import SwiftData
import Combine

/// Barrera común para operaciones costosas iniciadas desde la UI. Vive solo en
/// memoria y no introduce persistencia nueva.
@MainActor
final class PersistenceOperationCoordinator: ObservableObject {
    enum Operation: Equatable {
        case export
        case importData
        case restore
        case delete
        case repair
        case automaticBackup
    }

    static let shared = PersistenceOperationCoordinator()

    @Published private(set) var activeOperation: Operation?

    var isBusy: Bool { activeOperation != nil }
    var isRestoring: Bool { activeOperation == .restore }

    private init() {}

    @discardableResult
    func begin(_ operation: Operation) -> Bool {
        guard activeOperation == nil else { return false }
        activeOperation = operation
        return true
    }

    func finish(_ operation: Operation) {
        guard activeOperation == operation else { return }
        activeOperation = nil
    }
}

enum PersistenceOperationError: LocalizedError {
    case localChangesDetected
    case localBackupUnavailable

    var errorDescription: String? {
        switch self {
        case .localChangesDetected:
            return "La restauración se canceló porque los datos locales cambiaron mientras se preparaba."
        case .localBackupUnavailable:
            return "No se pudo crear y verificar el backup local previo."
        }
    }
}

private enum BackupFileSerializationLock {
    nonisolated static let value = NSLock()
}

enum ManualSyncService {
    struct BackupInfo: Sendable {
        let url: URL
        let exportDate: Date
    }

    enum SyncError: LocalizedError {
        case folderNotConfigured
        case cannotAccessFolder
        case noBackupsFound
        case preRestoreBackupUnavailable

        var errorDescription: String? {
            switch self {
            case .folderNotConfigured:
                return "No hay carpeta de iCloud Drive configurada."
            case .cannotAccessFolder:
                return "No se pudo acceder a la carpeta de sincronización."
            case .noBackupsFound:
                return "No se encontraron backups en la carpeta configurada."
            case .preRestoreBackupUnavailable:
                return "No se pudo crear y verificar el backup previo en la carpeta iCloud Drive configurada."
            }
        }
    }

    private nonisolated static let bookmarkKey = "manualSyncFolderBookmark"
    private nonisolated static let lastImportedExportDateKey = "manualSyncLastImportedExportDate"
    private nonisolated static let lastDismissedExportDateKey = "manualSyncLastDismissedExportDate"
    private nonisolated static let lastExportedExportDateKey = "manualSyncLastExportedExportDate"
    private nonisolated static let maxBackupFiles = 2

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
    @MainActor
    static func exportToSyncDirectory(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget]
    ) throws -> BackupInfo {
        try withSyncDirectoryAccess { directoryURL in
            try exportToSyncDirectory(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets,
                in: directoryURL
            )
        }
    }

    /// Variante asíncrona: la captura se prepara en el actor principal y la
    /// codificación, copia y poda del backup se ejecutan fuera de él.
    @MainActor
    static func exportToSyncDirectoryAsync(
        snapshot: DataExportService.DataSnapshot
    ) async throws -> BackupInfo {
        let directoryURL = try resolveSyncDirectory()
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard didAccess else { throw SyncError.cannotAccessFolder }
        let tempURL = try await DataExportService.exportDataAsync(snapshot: snapshot)
        return try await finalizeExport(tempURL: tempURL, in: directoryURL)
    }

    /// Decodifica la copia remota y crea el backup verificable del estado actual
    /// antes de que el caller pueda reemplazar datos locales.
    @MainActor
    static func prepareLatestBackupForRestore(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget]
    ) throws -> (DataExportService.ImportResult, Date) {
        try withSyncDirectoryAccess { directoryURL in
            let latest = try latestBackup(in: directoryURL)
            let importResult = try DataExportService.importData(from: latest.url)
            _ = try exportToSyncDirectory(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets,
                in: directoryURL
            )
            return (importResult, latest.exportDate)
        }
    }

    /// Mantiene el orden seguro de restauración: primero valida/decodifica la
    /// copia remota, después guarda el estado local y sólo entonces devuelve el
    /// resultado para que el caller pueda mutar SwiftData.
    @MainActor
    static func prepareLatestBackupForRestoreAsync(
        snapshot: DataExportService.DataSnapshot
    ) async throws -> (DataExportService.ImportResult, Date) {
        let directoryURL = try resolveSyncDirectory()
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard didAccess else { throw SyncError.cannotAccessFolder }
        let latest = try await latestBackupAsync(in: directoryURL)
        let importResult = try await DataExportService.importDataAsync(from: latest.url)
        _ = try await exportSnapshotAsync(snapshot, in: directoryURL)
        return (importResult, latest.exportDate)
    }

    /// Variante segura para restauraciones iniciadas desde una vista. El estado
    /// se captura después de decodificar la copia remota y justo antes de crear
    /// el backup previo, reduciendo la ventana en la que pueden entrar cambios.
    /// La huella devuelta debe comprobarse inmediatamente antes de mutar el
    /// `ModelContext`.
    @MainActor
    static func prepareLatestBackupForRestoreAsync(
        snapshotProvider: @escaping @MainActor () throws -> DataExportService.DataSnapshot
    ) async throws -> (DataExportService.ImportResult, Date, DataExportService.DataRevision) {
        let directoryURL = try resolveSyncDirectory()
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard didAccess else {
            throw SyncError.cannotAccessFolder
        }

        let latest = try await latestBackupAsync(in: directoryURL)
        let importResult = try await DataExportService.importDataAsync(from: latest.url)
        try Task.checkCancellation()

        let snapshot = try snapshotProvider()
        let revision = await DataExportService.revisionAsync(of: snapshot)
        _ = try await exportSnapshotAsync(snapshot, in: directoryURL)
        return (importResult, latest.exportDate, revision)
    }

    @MainActor
    static func createVerifiedPreRestoreBackup(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget]
    ) throws {
        guard isConfigured else { throw SyncError.preRestoreBackupUnavailable }
        try withSyncDirectoryAccess { directoryURL in
            _ = try exportToSyncDirectory(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets,
                in: directoryURL
            )
        }
    }

    @MainActor
    static func createVerifiedPreRestoreBackupAsync(
        snapshot: DataExportService.DataSnapshot
    ) async throws {
        guard isConfigured else { throw SyncError.preRestoreBackupUnavailable }
        let directoryURL = try resolveSyncDirectory()
        let didAccess = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard didAccess else { throw SyncError.cannotAccessFolder }
        _ = try await exportSnapshotAsync(snapshot, in: directoryURL)
    }

    @MainActor
    static func latestBackup() throws -> BackupInfo {
        try withSyncDirectoryAccess { directoryURL in
            try latestBackup(in: directoryURL)
        }
    }

    @MainActor
    static func importLatestBackup() throws -> (DataExportService.ImportResult, Date) {
        try withSyncDirectoryAccess { directoryURL in
            let latest = try latestBackup(in: directoryURL)
            let result = try DataExportService.importData(from: latest.url)
            return (result, latest.exportDate)
        }
    }

    @MainActor
    static func importLatestBackupAsync() async throws -> (DataExportService.ImportResult, Date) {
        try await withSyncDirectoryAccessAsync { directoryURL in
            let latest = try await latestBackupAsync(in: directoryURL)
            let result = try await DataExportService.importDataAsync(from: latest.url)
            return (result, latest.exportDate)
        }
    }

    nonisolated static func markImported(exportDate: Date) {
        UserDefaults.standard.set(exportDate, forKey: lastImportedExportDateKey)
        UserDefaults.standard.removeObject(forKey: lastDismissedExportDateKey)
    }

    nonisolated static func markExported(exportDate: Date) {
        UserDefaults.standard.set(exportDate, forKey: lastExportedExportDateKey)
    }

    nonisolated static func markDismissed(exportDate: Date) {
        UserDefaults.standard.set(exportDate, forKey: lastDismissedExportDateKey)
    }

    @MainActor static func shouldPromptForNewBackup() -> Bool {
        guard let latest = try? latestBackup() else { return false }

        return shouldPromptForNewBackup(latestExportDate: latest.exportDate)
    }

    @MainActor
    static func shouldPromptForNewBackup(in directoryURL: URL) -> Bool {
        guard let latest = try? latestBackup(in: directoryURL) else { return false }

        return shouldPromptForNewBackup(latestExportDate: latest.exportDate)
    }

    /// Obtiene el último backup una sola vez y conserva el filtrado de estado
    /// (importado, descartado o exportado) antes de mostrar el prompt.
    @MainActor
    static func latestBackupIfPromptNeeded() async throws -> BackupInfo? {
        let latest = try await latestBackupAsync()
        return shouldPromptForNewBackup(latestExportDate: latest.exportDate) ? latest : nil
    }

    private static func shouldPromptForNewBackup(latestExportDate: Date) -> Bool {
        let acknowledgedDate = maxDate(lastImportedExportDate, lastDismissedExportDate)
        let baseline = maxDate(acknowledgedDate, lastExportedExportDate)
        guard let baseline else { return true }
        return latestExportDate > baseline
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

    private nonisolated static func listBackups(in directoryURL: URL) throws -> [BackupInfo] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return files
            .filter { $0.lastPathComponent.hasPrefix("Finance_backup_") && $0.pathExtension.lowercased() == "json" }
            .compactMap { fileURL in
                guard let exportDate = DataExportService.readExportDate(from: fileURL) else { return nil }
                return BackupInfo(url: fileURL, exportDate: exportDate)
            }
            .sorted { lhs, rhs in
                if lhs.exportDate != rhs.exportDate {
                    return lhs.exportDate > rhs.exportDate
                }
                return lhs.url.lastPathComponent > rhs.url.lastPathComponent
            }
    }

    private nonisolated static func pruneBackups(in directoryURL: URL) throws {
        let backups = try listBackups(in: directoryURL)
        guard backups.count > maxBackupFiles else { return }

        for backup in backups.dropFirst(maxBackupFiles) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    @MainActor
    private static func exportToSyncDirectory(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget],
        in directoryURL: URL
    ) throws -> BackupInfo {
        try withBackupFileSerialization {
            let tempURL = try DataExportService.exportData(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets
            )

            let destinationURL = directoryURL.appendingPathComponent(tempURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)

            guard FileManager.default.fileExists(atPath: destinationURL.path),
                  let exportDate = DataExportService.readExportDate(from: destinationURL) else {
                throw SyncError.preRestoreBackupUnavailable
            }

            try pruneBackups(in: directoryURL)
            markExported(exportDate: exportDate)
            return BackupInfo(url: destinationURL, exportDate: exportDate)
        }
    }

    nonisolated static func latestBackup(in directoryURL: URL) throws -> BackupInfo {
        let backups = try listBackups(in: directoryURL)
        guard let latest = backups.first else {
            throw SyncError.noBackupsFound
        }
        return latest
    }

    nonisolated static func latestBackupAsync() async throws -> BackupInfo {
        try await withSyncDirectoryAccessAsync { directoryURL in
            try await latestBackupAsync(in: directoryURL)
        }
    }

    nonisolated private static func latestBackupAsync(in directoryURL: URL) async throws -> BackupInfo {
        let task = Task.detached(priority: .utility) { () throws -> BackupInfo in
            try Task.checkCancellation()
            return try latestBackup(in: directoryURL)
        }
        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private nonisolated static func resolveSyncDirectory() throws -> URL {
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

    nonisolated static func withSyncDirectoryAccess<T>(_ action: (URL) throws -> T) throws -> T {
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

    nonisolated static func withSyncDirectoryAccessAsync<T>(_ action: (URL) async throws -> T) async throws -> T {
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

    @MainActor
    private static func exportSnapshotAsync(
        _ snapshot: DataExportService.DataSnapshot,
        in directoryURL: URL
    ) async throws -> BackupInfo {
        let tempURL = try await DataExportService.exportDataAsync(snapshot: snapshot)
        return try await finalizeExport(tempURL: tempURL, in: directoryURL)
    }

    private nonisolated static func finalizeExport(tempURL: URL, in directoryURL: URL) async throws -> BackupInfo {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            return try withBackupFileSerialization {
                let destinationURL = directoryURL.appendingPathComponent(tempURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: tempURL, to: destinationURL)

                guard FileManager.default.fileExists(atPath: destinationURL.path),
                      let exportDate = DataExportService.readExportDate(from: destinationURL) else {
                    throw SyncError.preRestoreBackupUnavailable
                }

                try pruneBackups(in: directoryURL)
                markExported(exportDate: exportDate)
                return BackupInfo(url: destinationURL, exportDate: exportDate)
            }
        }
        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private nonisolated static func withBackupFileSerialization<T>(
        _ operation: () throws -> T
    ) rethrows -> T {
        BackupFileSerializationLock.value.lock()
        defer { BackupFileSerializationLock.value.unlock() }
        return try operation()
    }
}
