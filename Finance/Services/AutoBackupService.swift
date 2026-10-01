//
//  AutoBackupService.swift
//  Finance
//
//  Created by OpenCode on 17/02/2026.
//

import Foundation
import BackgroundTasks
import SwiftData

enum AutoBackupService {
    static let taskIdentifier = "com.getincouch.Finance.autobackup"

    static let enabledStorageKey = "autoBackupEnabled"
    static let hourStorageKey = "autoBackupHour"
    static let minuteStorageKey = "autoBackupMinute"
    static let lastAutoBackupAtStorageKey = "autoBackupLastRunAt"

    static func refreshBackgroundScheduleFromSettings() {
        refreshBackgroundSchedule(
            enabled: isEnabledInSettings,
            hour: configuredHour,
            minute: configuredMinute
        )
    }

    static func refreshBackgroundSchedule(enabled: Bool, hour: Int, minute: Int) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)

        guard enabled, ManualSyncService.isConfigured else { return }

        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = nextRunDate(after: Date(), hour: hour, minute: minute)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            return
        }
    }

    static func handleBackgroundRefresh(modelContainer: ModelContainer) async {
        refreshBackgroundScheduleFromSettings()

        do {
            _ = try await performAutoBackupIfDueAsync(modelContainer: modelContainer)
        } catch {
            return
        }
    }

    @MainActor
    @discardableResult
    static func performAutoBackupIfDue(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget],
        now: Date = Date()
    ) throws -> Bool {
        guard let lease = AutomaticBackupSerializationLease() else {
            return false
        }
        defer { _ = lease }
        return try performAutoBackupIfDueUnlocked(
            banks: banks,
            accounts: accounts,
            categories: categories,
            movements: movements,
            investmentSnapshots: investmentSnapshots,
            recurringMovements: recurringMovements,
            budgets: budgets,
            now: now
        )
    }

    /// Ejecuta el backup a partir de una captura puntual. La lectura de SwiftData
    /// se realiza antes de este método y la serialización/filesystem se delegan.
    @MainActor
    @discardableResult
    static func performAutoBackupIfDue(
        snapshot: DataExportService.DataSnapshot,
        now: Date = Date()
    ) async throws -> Bool {
        guard PersistenceOperationCoordinator.shared.begin(.automaticBackup) else {
            return false
        }
        defer { PersistenceOperationCoordinator.shared.finish(.automaticBackup) }

        guard let lease = AutomaticBackupSerializationLease() else {
            return false
        }
        defer { _ = lease }
        return try await performAutoBackupIfDueUnlocked(snapshot: snapshot, now: now)
    }

    @MainActor
    private static func performAutoBackupIfDueUnlocked(
        snapshot: DataExportService.DataSnapshot,
        now: Date
    ) async throws -> Bool {

        let hour = configuredHour
        let minute = configuredMinute

        guard isBackupDue(now: now, enabled: isEnabledInSettings, hour: hour, minute: minute) else {
            return false
        }

        _ = try await ManualSyncService.exportToSyncDirectoryAsync(snapshot: snapshot)

        UserDefaults.standard.set(now, forKey: lastAutoBackupAtStorageKey)
        refreshBackgroundSchedule(enabled: true, hour: hour, minute: minute)
        return true
    }

    @MainActor
    @discardableResult
    static func performAutoBackupIfDue(
        in modelContext: ModelContext,
        now: Date = Date()
    ) async throws -> Bool {
        guard PersistenceOperationCoordinator.shared.begin(.automaticBackup) else {
            return false
        }
        defer { PersistenceOperationCoordinator.shared.finish(.automaticBackup) }

        guard let lease = AutomaticBackupSerializationLease() else {
            return false
        }
        defer { _ = lease }
        let hour = configuredHour
        let minute = configuredMinute
        guard isBackupDue(now: now, enabled: isEnabledInSettings, hour: hour, minute: minute) else {
            return false
        }

        let snapshot = try DataExportService.fetchSnapshot(in: modelContext)
        return try await performAutoBackupIfDueUnlocked(snapshot: snapshot, now: now)
    }

    @MainActor
    private static func performAutoBackupIfDueAsync(
        modelContainer: ModelContainer,
        now: Date = Date()
    ) async throws -> Bool {
        guard PersistenceOperationCoordinator.shared.begin(.automaticBackup) else {
            return false
        }
        defer { PersistenceOperationCoordinator.shared.finish(.automaticBackup) }

        guard let lease = AutomaticBackupSerializationLease() else {
            return false
        }
        defer { _ = lease }
        let hour = configuredHour
        let minute = configuredMinute
        guard isBackupDue(now: now, enabled: isEnabledInSettings, hour: hour, minute: minute) else {
            return false
        }

        let context = ModelContext(modelContainer)
        let snapshot = try DataExportService.fetchSnapshot(in: context)
        return try await performAutoBackupIfDueUnlocked(snapshot: snapshot, now: now)
    }

    @MainActor
    @discardableResult
    static func performAutoBackupIfDue(modelContainer: ModelContainer, now: Date = Date()) throws -> Bool {
        guard PersistenceOperationCoordinator.shared.begin(.automaticBackup) else {
            return false
        }
        defer { PersistenceOperationCoordinator.shared.finish(.automaticBackup) }

        guard let lease = AutomaticBackupSerializationLease() else {
            return false
        }
        defer { _ = lease }

        let hour = configuredHour
        let minute = configuredMinute
        guard isBackupDue(now: now, enabled: isEnabledInSettings, hour: hour, minute: minute) else {
            return false
        }

        let context = ModelContext(modelContainer)
        let snapshot = try DataExportService.fetchSnapshot(in: context)

        return try performAutoBackupIfDueUnlocked(
            banks: snapshot.banks,
            accounts: snapshot.accounts,
            categories: snapshot.categories,
            movements: snapshot.movements,
            investmentSnapshots: snapshot.investmentSnapshots,
            recurringMovements: snapshot.recurringMovements,
            budgets: snapshot.budgets,
            now: now
        )
    }

    @MainActor
    private static func performAutoBackupIfDueUnlocked(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget],
        now: Date
    ) throws -> Bool {
        let hour = configuredHour
        let minute = configuredMinute

        guard isBackupDue(now: now, enabled: isEnabledInSettings, hour: hour, minute: minute) else {
            return false
        }

        _ = try ManualSyncService.exportToSyncDirectory(
            banks: banks,
            accounts: accounts,
            categories: categories,
            movements: movements,
            investmentSnapshots: investmentSnapshots,
            recurringMovements: recurringMovements,
            budgets: budgets
        )

        UserDefaults.standard.set(now, forKey: lastAutoBackupAtStorageKey)
        refreshBackgroundSchedule(enabled: true, hour: hour, minute: minute)
        return true
    }

    private static var isEnabledInSettings: Bool {
        UserDefaults.standard.bool(forKey: enabledStorageKey)
    }

    private static var configuredHour: Int {
        let value = UserDefaults.standard.object(forKey: hourStorageKey) as? Int ?? 0
        return min(max(value, 0), 23)
    }

    private static var configuredMinute: Int {
        let value = UserDefaults.standard.object(forKey: minuteStorageKey) as? Int ?? 0
        return min(max(value, 0), 59)
    }

    private static var lastAutoBackupAt: Date? {
        UserDefaults.standard.object(forKey: lastAutoBackupAtStorageKey) as? Date
    }

    private static func isBackupDue(now: Date, enabled: Bool, hour: Int, minute: Int) -> Bool {
        guard enabled else { return false }
        guard ManualSyncService.isConfigured else { return false }

        let todayScheduledDate = scheduledDate(on: now, hour: hour, minute: minute)
        guard now >= todayScheduledDate else { return false }

        guard let lastAutoBackupAt else { return true }
        return lastAutoBackupAt < todayScheduledDate
    }

    private static func scheduledDate(on referenceDate: Date, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: referenceDate)

        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: startOfDay
        ) ?? startOfDay
    }

    private static func nextRunDate(after referenceDate: Date, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        let todayScheduledDate = scheduledDate(on: referenceDate, hour: hour, minute: minute)

        if referenceDate < todayScheduledDate {
            return todayScheduledDate
        }

        return calendar.date(byAdding: .day, value: 1, to: todayScheduledDate)
            ?? referenceDate.addingTimeInterval(24 * 60 * 60)
    }

}

private final class AutomaticBackupSerializationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isInFlight = false

    func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isInFlight else { return false }
        isInFlight = true
        return true
    }

    func release() {
        lock.lock()
        isInFlight = false
        lock.unlock()
    }
}

/// Reserva única para todas las sobrecargas (síncronas y asíncronas). La
/// reserva no mantiene bloqueado el hilo durante un `await`, pero impide que
/// otra ejecución entre mientras la copia y su marca/poda están en curso.
private final class AutomaticBackupSerializationLease {
    private static let state = AutomaticBackupSerializationState()

    init?() {
        guard Self.state.acquire() else { return nil }
    }

    deinit {
        Self.state.release()
    }
}
