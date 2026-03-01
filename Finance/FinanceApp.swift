//
//  FinanceApp.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct FinanceApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .backgroundTask(.appRefresh(AutoBackupService.taskIdentifier)) {
            await AutoBackupService.handleBackgroundRefresh(modelContainer: sharedModelContainer)
        }
    }

    init() {
        AutoBackupService.refreshBackgroundScheduleFromSettings()
    }
}
