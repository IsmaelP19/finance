//
//  AccountDeletionService.swift
//  Finance
//
//  Created by OpenCode on 15/05/2026.
//

import Foundation
import SwiftData

@MainActor
enum AccountDeletionService {
    static func delete(
        _ account: BankAccount,
        allMovements: [Movement],
        recurringMovements: [RecurringMovement],
        in modelContext: ModelContext
    ) throws {
        try delete([account], allMovements: allMovements, recurringMovements: recurringMovements, in: modelContext)
    }

    static func delete(
        _ accounts: [BankAccount],
        allMovements _: [Movement],
        recurringMovements: [RecurringMovement],
        in modelContext: ModelContext
    ) throws {
        let accountIDs = Set(accounts.map(\.id))
        let now = Date()

        for recurring in recurringMovements where recurring.account.map({ accountIDs.contains($0.id) }) == true {
            recurring.isActive = false
            recurring.updatedAt = now
        }

        for account in accounts where !account.isArchived {
            account.archive(at: now)
        }

        try modelContext.save()
    }
}
