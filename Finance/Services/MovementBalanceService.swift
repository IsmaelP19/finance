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
        modelContext.processPendingChanges()

        guard let plan = incrementalRebuildPlan(in: modelContext),
              plan.affectedAccountIDs.count <= 8 else {
            return try rebuild(in: modelContext, scope: .full)
        }

        return try rebuild(
            in: modelContext,
            scope: .incremental(plan)
        )
    }

    private struct IncrementalRebuildPlan {
        let affectedAccountIDs: Set<UUID>
        let earliestAffectedDateByAccountID: [UUID: Date]
        let accountsWithInsertedMovements: Set<UUID>
        let insertedMovementIDs: Set<UUID>
    }

    private enum RebuildScope {
        case full
        case incremental(IncrementalRebuildPlan)
    }

    @discardableResult
    @MainActor
    private static func rebuild(
        in modelContext: ModelContext,
        scope: RebuildScope
    ) throws -> Reconstruction {
        let accounts = try modelContext.fetch(FetchDescriptor<BankAccount>())

        if case let .incremental(plan) = scope,
           canIncrementallyRebuild(plan: plan, accounts: accounts),
           let reconstruction = try rebuildIncrementally(
               plan: plan,
               in: modelContext,
               accounts: accounts
           ) {
            return reconstruction
        }

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

    private static func incrementalRebuildPlan(in modelContext: ModelContext) -> IncrementalRebuildPlan? {
        let insertedModels = modelContext.insertedModelsArray
        let changedModels = modelContext.changedModelsArray
        let deletedModels = modelContext.deletedModelsArray

        let insertedObjectIDs = Set(insertedModels.map { ObjectIdentifier($0 as AnyObject) })
        if changedModels.contains(where: { model in
            model is Movement && !insertedObjectIDs.contains(ObjectIdentifier(model as AnyObject))
        }) {
            // SwiftData exposes the current relationship, but not the previous
            // one. A full rebuild is the only safe option for an edited movement
            // because its old source/destination account may no longer be known.
            return nil
        }
        if deletedModels.contains(where: { $0 is Movement || $0 is BankAccount }) {
            // The deleted model may be the only place where an old account
            // relationship is still available. Do not risk leaving an account
            // with stale historical balances.
            return nil
        }

        var affectedAccountIDs = Set<UUID>()
        var earliestAffectedDateByAccountID: [UUID: Date] = [:]
        var accountsWithInsertedMovements = Set<UUID>()
        var insertedMovementIDs = Set<UUID>()

        func markAffectedAccount(_ accountID: UUID?, from date: Date) {
            guard let accountID else { return }
            affectedAccountIDs.insert(accountID)
            if let currentDate = earliestAffectedDateByAccountID[accountID] {
                earliestAffectedDateByAccountID[accountID] = min(currentDate, date)
            } else {
                earliestAffectedDateByAccountID[accountID] = date
            }
        }

        for model in insertedModels {
            if let account = model as? BankAccount {
                markAffectedAccount(account.id, from: .distantPast)
            } else if let movement = model as? Movement {
                guard let sourceAccountID = movement.account?.id else {
                    // A destination-only insertion cannot identify the source
                    // history that must be rebuilt. Use the complete route.
                    return nil
                }
                insertedMovementIDs.insert(movement.id)
                accountsWithInsertedMovements.insert(sourceAccountID)
                if let destinationAccountID = movement.destinationAccount?.id {
                    accountsWithInsertedMovements.insert(destinationAccountID)
                }
                markAffectedAccount(movement.account?.id, from: movement.occurredAt)
                markAffectedAccount(movement.destinationAccount?.id, from: movement.occurredAt)
            }
        }
        if changedModels.contains(where: { $0 is BankAccount }) {
            // SwiftData does not expose whether the change was caused by the
            // movement being inserted or by a manual account edit. Any changed
            // account therefore requires the complete route.
            return nil
        }

        guard !affectedAccountIDs.isEmpty else {
            return nil
        }
        return IncrementalRebuildPlan(
            affectedAccountIDs: affectedAccountIDs,
            earliestAffectedDateByAccountID: earliestAffectedDateByAccountID,
            accountsWithInsertedMovements: accountsWithInsertedMovements,
            insertedMovementIDs: insertedMovementIDs
        )
    }

    private static func canIncrementallyRebuild(
        plan: IncrementalRebuildPlan,
        accounts: [BankAccount]
    ) -> Bool {
        let accountIDs = Set(accounts.map(\.id))
        return plan.affectedAccountIDs.isSubset(of: accountIDs)
            && plan.affectedAccountIDs.allSatisfy {
                plan.earliestAffectedDateByAccountID[$0] != nil
            }
    }

    private static func rebuildIncrementally(
        plan: IncrementalRebuildPlan,
        in modelContext: ModelContext,
        accounts: [BankAccount]
    ) throws -> Reconstruction? {
        let accountIDs = Set(accounts.map(\.id))
        let allMovements: [Movement]
        do {
            allMovements = try modelContext.fetch(FetchDescriptor<Movement>())
        } catch {
            return nil
        }

        guard let globalReconstruction = verifiedGlobalReconstruction(
            plan: plan,
            accounts: accounts,
            movements: allMovements,
            accountIDs: accountIDs
        ) else {
            return nil
        }

        var movementsByAffectedAccount: [UUID: [Movement]] = [:]
        var reconstructionsByAffectedAccount: [UUID: Reconstruction] = [:]
        var resultingBalances = globalReconstruction.resultingBalances

        for accountID in plan.affectedAccountIDs {
            guard let earliestAffectedDate = plan.earliestAffectedDateByAccountID[accountID] else {
                return nil
            }
            guard let account = accounts.first(where: { $0.id == accountID }) else {
                return nil
            }

            let descriptor = FetchDescriptor<Movement>(
                predicate: #Predicate<Movement> { movement in
                    movement.account?.id == accountID || movement.destinationAccount?.id == accountID
                }
            )
            let allAccountMovements: [Movement]
            do {
                allAccountMovements = try modelContext.fetch(descriptor)
            } catch {
                // A scoped relationship query is an optimisation, not a reason
                // to make the repair less reliable.
                return nil
            }

            for movement in allAccountMovements {
                let sourceAccountID = movement.account?.id
                let destinationAccountID = movement.destinationAccount?.id
                if let sourceAccountID, !accountIDs.contains(sourceAccountID) {
                    // A missing historical balance or dangling relationship may
                    // be legacy data. Let the complete route repair it safely.
                    return nil
                }
                if let destinationAccountID, !accountIDs.contains(destinationAccountID) {
                    return nil
                }
            }

            let accountSnapshots = allAccountMovements.map {
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
            let accountReconstruction = reconstruct(
                accounts: [
                    AccountSnapshot(id: accountID, currentBalance: account.balance)
                ],
                movements: accountSnapshots
            )

            if plan.accountsWithInsertedMovements.contains(accountID) {
                let priorMovements = allAccountMovements.filter { $0.occurredAt < earliestAffectedDate }
                if !priorMovements.isEmpty {
                    // A previous source movement is the only persisted anchor
                    // from which the balance immediately before the affected
                    // range can be verified. Without it, use the full route.
                    guard priorMovements.contains(where: { $0.account?.id == accountID }) else {
                        return nil
                    }

                    for movement in priorMovements where movement.account?.id == accountID {
                        guard let expectedResultingBalance = accountReconstruction.resultingBalances[movement.id],
                              movement.resultingBalance == expectedResultingBalance else {
                            // Do not derive a new base from an untrusted
                            // historical resultingBalance.
                            return nil
                        }
                    }
                }
            }

            let accountMovements = allAccountMovements.filter { $0.occurredAt >= earliestAffectedDate }
            for movement in accountMovements {
                if movement.account?.id != nil, movement.resultingBalance == nil {
                    // A missing historical balance may be legacy data. Let the
                    // complete route repair it safely.
                    return nil
                }
            }
            movementsByAffectedAccount[accountID] = accountMovements
            reconstructionsByAffectedAccount[accountID] = accountReconstruction
        }

        var openingBalances = globalReconstruction.openingBalances
        var finalBalances = globalReconstruction.finalBalances

        for account in accounts where plan.affectedAccountIDs.contains(account.id) {
            let accountMovements = movementsByAffectedAccount[account.id, default: []]
            guard let accountReconstruction = reconstructionsByAffectedAccount[account.id] else {
                return nil
            }

            guard let finalBalance = accountReconstruction.finalBalances[account.id] else {
                return nil
            }
            if account.balance != finalBalance {
                account.balance = finalBalance
            }
            finalBalances[account.id] = finalBalance

            for movement in accountMovements where movement.account?.id == account.id {
                guard let resultingBalance = accountReconstruction.resultingBalances[movement.id] else {
                    return nil
                }
                if movement.resultingBalance != resultingBalance {
                    movement.resultingBalance = resultingBalance
                }
                resultingBalances[movement.id] = resultingBalance
            }

            openingBalances[account.id] = accountReconstruction.openingBalances[account.id] ?? openingBalances[account.id]
        }

        return Reconstruction(
            openingBalances: openingBalances,
            resultingBalances: resultingBalances,
            finalBalances: finalBalances
        )
    }

    private static func verifiedGlobalReconstruction(
        plan: IncrementalRebuildPlan,
        accounts: [BankAccount],
        movements: [Movement],
        accountIDs: Set<UUID>
    ) -> Reconstruction? {
        let snapshots = movements.map {
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

        guard snapshots.allSatisfy({ movement in
            guard let sourceAccountID = movement.sourceAccountID,
                  accountIDs.contains(sourceAccountID) else {
                return false
            }
            if let destinationAccountID = movement.destinationAccountID {
                return accountIDs.contains(destinationAccountID)
            }
            return true
        }) else {
            return nil
        }

        let reconstruction = reconstruct(
            accounts: accounts.map { AccountSnapshot(id: $0.id, currentBalance: $0.balance) },
            movements: snapshots
        )

        for movement in movements {
            guard let sourceAccountID = movement.account?.id else {
                return nil
            }

            let isNewMovement = plan.insertedMovementIDs.contains(movement.id)
            let isAffectedHistory: Bool
            if plan.affectedAccountIDs.contains(sourceAccountID) {
                guard let earliestAffectedDate = plan.earliestAffectedDateByAccountID[sourceAccountID] else {
                    return nil
                }
                isAffectedHistory = movement.occurredAt >= earliestAffectedDate
            } else {
                isAffectedHistory = false
            }
            if isNewMovement || isAffectedHistory {
                continue
            }

            guard movement.resultingBalance == reconstruction.resultingBalances[movement.id] else {
                // Every value left outside the incremental range must already
                // agree with the complete reconstruction. Otherwise an
                // unrelated account could retain an obsolete history.
                return nil
            }
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

        _ = try rebuild(in: modelContext, scope: .full)

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
