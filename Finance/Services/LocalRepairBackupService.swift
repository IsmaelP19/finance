//
//  LocalRepairBackupService.swift
//  Finance
//

import Foundation

@MainActor
enum LocalRepairBackupService {
    struct BackupInfo: Identifiable {
        let url: URL
        let exportDate: Date
        let fileSize: Int64

        var id: String { url.path }
    }

    enum BackupError: LocalizedError {
        case backupUnavailable

        var errorDescription: String? {
            switch self {
            case .backupUnavailable:
                return "No se pudo crear y verificar el backup local previo."
            }
        }
    }

    private static let backupDirectoryName = "PreRepairBackups"
    private static let maxBackupFiles = 2

    static func createVerifiedBackup(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget]
    ) throws -> BackupInfo {
        let directoryURL = try backupDirectoryURL()
        let tempURL = try DataExportService.exportData(
            banks: banks,
            accounts: accounts,
            categories: categories,
            movements: movements,
            investmentSnapshots: investmentSnapshots,
            recurringMovements: recurringMovements,
            budgets: budgets
        )

        let destinationURL = directoryURL.appendingPathComponent(backupFileName())
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: tempURL, to: destinationURL)

        guard FileManager.default.fileExists(atPath: destinationURL.path),
              let exportDate = DataExportService.readExportDate(from: destinationURL) else {
            throw BackupError.backupUnavailable
        }

        do {
            try DataExportService.validateExportFile(from: destinationURL)
        } catch {
            throw BackupError.backupUnavailable
        }

        try pruneBackups(in: directoryURL)
        return BackupInfo(url: destinationURL, exportDate: exportDate, fileSize: fileSize(of: destinationURL))
    }

    static func availableBackups() throws -> [BackupInfo] {
        let directoryURL = try backupDirectoryURL()
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var backups: [BackupInfo] = []

        for fileURL in fileURLs
            where fileURL.lastPathComponent.hasPrefix("Finance_pre_repair_") && fileURL.pathExtension.lowercased() == "json" {
            guard let exportDate = DataExportService.readExportDate(from: fileURL) ?? backupDateFromFilename(fileURL) else { continue }
            backups.append(BackupInfo(url: fileURL, exportDate: exportDate, fileSize: fileSize(of: fileURL)))
        }

        return backups.sorted { lhs, rhs in
            if lhs.exportDate != rhs.exportDate {
                return lhs.exportDate > rhs.exportDate
            }
            return lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }
    }

    static func prepareForRestore(_ backup: BackupInfo) throws -> DataExportService.ImportResult {
        guard FileManager.default.fileExists(atPath: backup.url.path) else {
            throw BackupError.backupUnavailable
        }
        try DataExportService.validateExportFile(from: backup.url)
        return try DataExportService.importData(from: backup.url)
    }

    private static func backupDirectoryURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL.appendingPathComponent(backupDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private static func backupFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return "Finance_pre_repair_\(formatter.string(from: Date())).json"
    }

    private static func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private static func backupDateFromFilename(_ url: URL) -> Date? {
        let prefix = "Finance_pre_repair_"
        let suffix = ".json"
        guard url.lastPathComponent.hasPrefix(prefix), url.lastPathComponent.hasSuffix(suffix) else { return nil }

        let dateString = String(url.lastPathComponent.dropFirst(prefix.count).dropLast(suffix.count))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter.date(from: dateString)
    }

    private static func pruneBackups(in directoryURL: URL) throws {
        let backupURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("Finance_pre_repair_") && $0.pathExtension == "json" }
        .sorted {
            let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
        }

        guard backupURLs.count > maxBackupFiles else { return }
        for backupURL in backupURLs.dropFirst(maxBackupFiles) {
            try? FileManager.default.removeItem(at: backupURL)
        }
    }
}
