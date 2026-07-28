//
//  MovementBalanceService.swift
//  Finance
//

import Foundation
import SwiftData

/// Reconstruye los saldos históricos a partir de los totales actuales de las cuentas.
///
/// El cálculo es independiente de SwiftData para poder verificarse con snapshots
/// deterministas en FinanceTests.
enum MovementBalanceService {
    struct AccountSnapshot: Equatable {
        let id: UUID
        let currentBalance: Decimal
    }

    struct MovementSnapshot: Equatable {
        let id: UUID
        let occurredAt: Date
        let createdAt: Date
        let sourceAccountID: UUID?
        let destinationAccountID: UUID?
        let type: MovementType
        let amount: Decimal
    }

    struct Reconstruction: Equatable {
        let openingBalances: [UUID: Decimal]
        let resultingBalances: [UUID: Decimal]
        let finalBalances: [UUID: Decimal]
    }

    struct RepairReport: Equatable {
        let accountsChecked: Int
        let movementsChecked: Int
        let accountsChanged: Int
        let movementsChanged: Int
    }

    nonisolated static func reconstruct(
        accounts: [AccountSnapshot],
        movements: [MovementSnapshot]
    ) -> Reconstruction {
        var netImpacts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, Decimal.zero) })

        for movement in movements {
            applyNetImpact(of: movement, to: &netImpacts)
        }

        let openingBalances = Dictionary(uniqueKeysWithValues: accounts.map { account in
            (account.id, account.currentBalance - (netImpacts[account.id] ?? 0))
        })
        var balances = openingBalances
        var resultingBalances: [UUID: Decimal] = [:]

        for movement in movements.sorted(by: stableOrder) {
            applyBalanceImpact(of: movement, to: &balances)
            if let sourceAccountID = movement.sourceAccountID,
               balances[sourceAccountID] != nil {
                resultingBalances[movement.id] = balances[sourceAccountID]
            }
        }

        return Reconstruction(
            openingBalances: openingBalances,
            resultingBalances: resultingBalances,
            finalBalances: balances
        )
    }

    /// Recalcula los valores históricos persistidos conservando los totales
    /// representados por el estado actual de las cuentas.
    @discardableResult
    @MainActor
    static func rebuild(in modelContext: ModelContext) throws -> Reconstruction {
        let accounts = try modelContext.fetch(FetchDescriptor<BankAccount>())
        let movements = try modelContext.fetch(FetchDescriptor<Movement>())
        let reconstruction = reconstruct(
            accounts: accounts.map { AccountSnapshot(id: $0.id, currentBalance: $0.balance) },
            movements: movements.map {
                MovementSnapshot(
                    id: $0.id,
                    occurredAt: $0.occurredAt,
                    createdAt: $0.createdAt,
                    sourceAccountID: $0.account?.id,
                    destinationAccountID: $0.destinationAccount?.id,
                    type: $0.type,
                    amount: $0.amount
                )
            }
        )

        for account in accounts {
            if let finalBalance = reconstruction.finalBalances[account.id] {
                account.balance = finalBalance
            }
        }
        for movement in movements {
            movement.resultingBalance = reconstruction.resultingBalances[movement.id]
        }

        return reconstruction
    }

    @discardableResult
    @MainActor
    static func repair(in modelContext: ModelContext) throws -> RepairReport {
        let accounts = try modelContext.fetch(FetchDescriptor<BankAccount>())
        let movements = try modelContext.fetch(FetchDescriptor<Movement>())
        let previousAccountBalances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balance) })
        let previousMovementBalances = Dictionary(uniqueKeysWithValues: movements.map { ($0.id, $0.resultingBalance) })

        _ = try rebuild(in: modelContext)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        return RepairReport(
            accountsChecked: accounts.count,
            movementsChecked: movements.count,
            accountsChanged: accounts.count { previousAccountBalances[$0.id] != $0.balance },
            movementsChanged: movements.count { previousMovementBalances[$0.id] != $0.resultingBalance }
        )
    }

    nonisolated private static func stableOrder(_ lhs: MovementSnapshot, _ rhs: MovementSnapshot) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func applyNetImpact(
        of movement: MovementSnapshot,
        to impacts: inout [UUID: Decimal]
    ) {
        guard let sourceAccountID = movement.sourceAccountID else { return }
        switch movement.type {
        case .expense, .transfer:
            impacts[sourceAccountID, default: 0] -= movement.amount
        case .income:
            impacts[sourceAccountID, default: 0] += movement.amount
        }
        if movement.type == .transfer, let destinationAccountID = movement.destinationAccountID {
            impacts[destinationAccountID, default: 0] += movement.amount
        }
    }

    nonisolated private static func applyBalanceImpact(
        of movement: MovementSnapshot,
        to balances: inout [UUID: Decimal]
    ) {
        guard let sourceAccountID = movement.sourceAccountID else { return }
        switch movement.type {
        case .expense, .transfer:
            balances[sourceAccountID, default: 0] -= movement.amount
        case .income:
            balances[sourceAccountID, default: 0] += movement.amount
        }
        if movement.type == .transfer, let destinationAccountID = movement.destinationAccountID {
            balances[destinationAccountID, default: 0] += movement.amount
        }
    }
}
