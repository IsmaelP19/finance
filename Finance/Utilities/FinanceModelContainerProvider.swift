//
//  FinanceModelContainerProvider.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import SwiftData

/// Synchronous ModelContainer provider for use in AppIntents and other contexts
/// that cannot use async/await (EntityQuery, etc.).
enum FinanceModelContainerProvider {
    nonisolated static let shared: ModelContainer = {
        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
            Budget.self,
            BudgetItem.self,
            SavingsGoal.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
