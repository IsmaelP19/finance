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
            _ = try await MainActor.run {
                try performAutoBackupIfDue(modelContainer: modelContainer)
            }
        } catch {
            return
        }
    }

    @discardableResult
    static func performAutoBackupIfDue(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        now: Date = Date()
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
            recurringMovements: recurringMovements
        )

        UserDefaults.standard.set(now, forKey: lastAutoBackupAtStorageKey)
        refreshBackgroundSchedule(enabled: true, hour: hour, minute: minute)
        return true
    }

    @MainActor
    @discardableResult
    static func performAutoBackupIfDue(modelContainer: ModelContainer, now: Date = Date()) throws -> Bool {
        let context = ModelContext(modelContainer)

        let banks = try context.fetch(
            FetchDescriptor<Bank>(sortBy: [SortDescriptor(\Bank.name)])
        )
        let accounts = try context.fetch(
            FetchDescriptor<BankAccount>(sortBy: [SortDescriptor(\BankAccount.name)])
        )
        let categories = try context.fetch(
            FetchDescriptor<MovementCategory>(sortBy: [SortDescriptor(\MovementCategory.name)])
        )
        let movements = try context.fetch(
            FetchDescriptor<Movement>(sortBy: [SortDescriptor(\Movement.occurredAt, order: .reverse)])
        )
        let snapshots = try context.fetch(
            FetchDescriptor<InvestmentSnapshot>(sortBy: [SortDescriptor(\InvestmentSnapshot.snapshotDate, order: .reverse)])
        )
        let recurringMovements = try context.fetch(
            FetchDescriptor<RecurringMovement>(sortBy: [SortDescriptor(\RecurringMovement.updatedAt, order: .reverse)])
        )

        return try performAutoBackupIfDue(
            banks: banks,
            accounts: accounts,
            categories: categories,
            movements: movements,
            investmentSnapshots: snapshots,
            recurringMovements: recurringMovements,
            now: now
        )
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
