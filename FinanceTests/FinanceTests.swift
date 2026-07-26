//
//  FinanceTests.swift
//  FinanceTests
//
//  Created by Ismael Pérez on 11/02/2026.
//

import Testing
import Foundation
import SwiftData
@testable import Finance

struct FinanceTests {

    @Test func activeAccountIsVisibleAfterCreation() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))

        #expect(account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 2)))
    }

    @Test func accountIsNotVisibleBeforeCreation() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 2))

        #expect(!account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 1)))
    }

    @Test func archivedAccountRemainsVisibleBeforeArchiveDate() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))
        account.archive(at: date(year: 2026, month: 5, day: 20))

        #expect(account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 10)))
    }

    @Test func archivedAccountIsNotVisibleAfterArchiveDate() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))
        account.archive(at: date(year: 2026, month: 5, day: 20))

        #expect(!account.isVisibleInPatrimony(at: date(year: 2026, month: 6, day: 1)))
    }

    @Test func archivedAccountWithoutArchiveDateFallsBackToUpdatedAt() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))
        account.isArchived = true
        account.archivedAt = nil
        account.updatedAt = date(year: 2026, month: 5, day: 20)

        #expect(account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 10)))
        #expect(!account.isVisibleInPatrimony(at: date(year: 2026, month: 6, day: 1)))
    }

    @Test func recurringOccurrenceConfirmedOnDifferentDayMatchesScheduledDate() async throws {
        let ruleID = UUID()
        let scheduledDate = date(year: 2026, month: 5, day: 5)
        let confirmationDate = date(year: 2026, month: 5, day: 7)
        let movement = Movement(
            concept: "Recurring expense",
            amount: 10,
            type: .expense,
            occurredAt: confirmationDate,
            recurringRuleId: ruleID,
            recurringScheduledAt: scheduledDate
        )

        #expect(RecurringMovementService.isOccurrenceConfirmed(
            ruleID: ruleID,
            dueDate: scheduledDate,
            movements: [movement],
            calendar: testCalendar
        ))
        #expect(!RecurringMovementService.isOccurrenceConfirmed(
            ruleID: ruleID,
            dueDate: confirmationDate,
            movements: [movement],
            calendar: testCalendar
        ))
    }

    @Test func reconstructsHistoricalExpenseAndIncomeBalances() async throws {
        let accountID = UUID()
        let incomeID = UUID()
        let expenseID = UUID()
        let firstDate = date(year: 2026, month: 5, day: 1)
        let secondDate = date(year: 2026, month: 5, day: 2)

        let result = MovementBalanceService.reconstruct(
            accounts: [.init(id: accountID, currentBalance: 70)],
            movements: [
                .init(id: incomeID, occurredAt: firstDate, createdAt: firstDate, sourceAccountID: accountID, destinationAccountID: nil, type: .income, amount: 100),
                .init(id: expenseID, occurredAt: secondDate, createdAt: secondDate, sourceAccountID: accountID, destinationAccountID: nil, type: .expense, amount: 30)
            ]
        )

        #expect(result.openingBalances[accountID] == 0)
        #expect(result.resultingBalances[incomeID] == 100)
        #expect(result.resultingBalances[expenseID] == 70)
        #expect(result.finalBalances[accountID] == 70)
    }

    @Test func reconstructsEditedHistoricalMovement() async throws {
        let accountID = UUID()
        let incomeID = UUID()
        let editedExpenseID = UUID()
        let firstDate = date(year: 2026, month: 5, day: 1)
        let secondDate = date(year: 2026, month: 5, day: 2)

        let result = MovementBalanceService.reconstruct(
            accounts: [.init(id: accountID, currentBalance: 80)],
            movements: [
                .init(id: incomeID, occurredAt: firstDate, createdAt: firstDate, sourceAccountID: accountID, destinationAccountID: nil, type: .income, amount: 100),
                .init(id: editedExpenseID, occurredAt: secondDate, createdAt: secondDate, sourceAccountID: accountID, destinationAccountID: nil, type: .expense, amount: 20)
            ]
        )

        #expect(result.resultingBalances[incomeID] == 100)
        #expect(result.resultingBalances[editedExpenseID] == 80)
        #expect(result.finalBalances[accountID] == 80)
    }

    @Test func reconstructsBalancesAfterDeletingHistoricalMovement() async throws {
        let accountID = UUID()
        let incomeID = UUID()
        let deletedExpenseID = UUID()
        let firstDate = date(year: 2026, month: 5, day: 1)
        let secondDate = date(year: 2026, month: 5, day: 2)
        let allMovements = [
            MovementBalanceService.MovementSnapshot(
                id: incomeID,
                occurredAt: firstDate,
                createdAt: firstDate,
                sourceAccountID: accountID,
                destinationAccountID: nil,
                type: .income,
                amount: 100
            ),
            MovementBalanceService.MovementSnapshot(
                id: deletedExpenseID,
                occurredAt: secondDate,
                createdAt: secondDate,
                sourceAccountID: accountID,
                destinationAccountID: nil,
                type: .expense,
                amount: 30
            )
        ]
        let postDeletionMovements = allMovements.filter { $0.id != deletedExpenseID }

        let result = MovementBalanceService.reconstruct(
            accounts: [.init(id: accountID, currentBalance: 100)],
            movements: postDeletionMovements
        )

        #expect(result.resultingBalances[deletedExpenseID] == nil)
        #expect(result.resultingBalances[incomeID] == 100)
        #expect(result.finalBalances[accountID] == 100)
    }

    @Test func reconstructsTransferBalancesForBothAccounts() async throws {
        let sourceID = UUID()
        let destinationID = UUID()
        let incomeID = UUID()
        let transferID = UUID()
        let firstDate = date(year: 2026, month: 5, day: 1)
        let secondDate = date(year: 2026, month: 5, day: 2)

        let result = MovementBalanceService.reconstruct(
            accounts: [
                .init(id: sourceID, currentBalance: 70),
                .init(id: destinationID, currentBalance: 30)
            ],
            movements: [
                .init(id: incomeID, occurredAt: firstDate, createdAt: firstDate, sourceAccountID: sourceID, destinationAccountID: nil, type: .income, amount: 100),
                .init(id: transferID, occurredAt: secondDate, createdAt: secondDate, sourceAccountID: sourceID, destinationAccountID: destinationID, type: .transfer, amount: 30)
            ]
        )

        #expect(result.resultingBalances[incomeID] == 100)
        #expect(result.resultingBalances[transferID] == 70)
        #expect(result.finalBalances[sourceID] == 70)
        #expect(result.finalBalances[destinationID] == 30)
    }

    @Test func recurrentConfirmationKeepsOccurrenceDateSeparateFromBalanceDate() async throws {
        let accountID = UUID()
        let movementID = UUID()
        let scheduledDate = date(year: 2026, month: 5, day: 5)
        let confirmationDate = date(year: 2026, month: 5, day: 7)
        let movement = Movement(
            concept: "Recurring expense",
            amount: 10,
            type: .expense,
            occurredAt: confirmationDate,
            recurringScheduledAt: scheduledDate
        )
        movement.id = movementID

        let result = MovementBalanceService.reconstruct(
            accounts: [.init(id: accountID, currentBalance: -10)],
            movements: [.init(id: movementID, occurredAt: movement.occurredAt, createdAt: movement.createdAt, sourceAccountID: accountID, destinationAccountID: nil, type: movement.type, amount: movement.amount)]
        )

        #expect(movement.occurredAt == confirmationDate)
        #expect(movement.recurringScheduledAt == scheduledDate)
        #expect(result.resultingBalances[movementID] == -10)
    }

    @Test @MainActor func deleteMovementRebuildsAndSavesHistoricalBalanceInMemory() async throws {
        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
            Budget.self,
            BudgetItem.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let account = BankAccount(name: "Test account", accountType: .checking, balance: 70)
        let income = Movement(concept: "Income", amount: 100, type: .income, account: account)
        let expense = Movement(concept: "Expense", amount: 30, type: .expense, account: account)

        context.insert(account)
        context.insert(income)
        context.insert(expense)
        try context.save()

        context.delete(expense)
        account.balance += 30
        _ = try MovementBalanceService.rebuild(in: context)
        try context.save()

        let savedMovements = try context.fetch(FetchDescriptor<Movement>())
        #expect(savedMovements.count == 1)
        #expect(savedMovements.first?.id == income.id)
        #expect(savedMovements.first?.resultingBalance == 100)
        #expect(account.balance == 100)
    }

    @Test @MainActor func mergeKeepsLocalAccountAndAppliesOnlyNewMovementImpact() async throws {
        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
            Budget.self,
            BudgetItem.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let localAccount = BankAccount(
            name: "Cuenta local",
            accountType: .investment,
            balance: 100,
            investedAmount: nil,
            marketValue: 120
        )
        context.insert(localAccount)
        try context.save()

        let importedConflictingAccount = BankAccount(name: "Cuenta importada", accountType: .investment, balance: 999)
        importedConflictingAccount.id = localAccount.id
        let importedDestinationAccount = BankAccount(
            name: "Destino importado",
            accountType: .investment,
            balance: 40,
            investedAmount: nil,
            marketValue: 50
        )
        let importedMovement = Movement(
            concept: "Nueva transferencia",
            amount: 20,
            type: .transfer,
            account: importedConflictingAccount,
            destinationAccount: importedDestinationAccount
        )
        let importResult = DataExportService.ImportResult(
            banks: [],
            accounts: [importedConflictingAccount, importedDestinationAccount],
            categories: [],
            movements: [importedMovement],
            investmentSnapshots: [],
            recurringMovements: [],
            budgets: []
        )

        let report = try DataExportService.importData(
            importResult,
            into: context,
            mode: .merge,
            currencyCode: "EUR"
        )

        let savedMovements = try context.fetch(FetchDescriptor<Movement>())
        #expect(report.conflicts.accounts == 1)
        #expect(report.imported.accounts == 1)
        #expect(report.imported.movements == 1)
        #expect(localAccount.name == "Cuenta local")
        #expect(localAccount.balance == 80)
        #expect(localAccount.investedAmount == 80)
        #expect(localAccount.marketValue == 120)
        #expect(importedDestinationAccount.balance == 40)
        #expect(importedDestinationAccount.investedAmount == nil)
        #expect(importedDestinationAccount.marketValue == 50)
        #expect(try context.fetch(FetchDescriptor<BankAccount>()).count == 2)
        #expect(savedMovements.count == 1)
        #expect(savedMovements.first?.destinationAccount?.id == importedDestinationAccount.id)
        #expect(savedMovements.first?.resultingBalance == 80)
    }

    @Test @MainActor func mergeAppliesInvestmentTransfersChronologically() async throws {
        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
            Budget.self,
            BudgetItem.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let sourceAccount = BankAccount(
            name: "Origen",
            accountType: .investment,
            balance: 100,
            investedAmount: 100,
            marketValue: 100
        )
        let destinationAccount = BankAccount(
            name: "Destino",
            accountType: .investment,
            balance: 0,
            investedAmount: 0,
            marketValue: 0
        )
        context.insert(sourceAccount)
        context.insert(destinationAccount)
        try context.save()

        let firstTransfer = Movement(
            concept: "Salida histórica",
            amount: 20,
            type: .transfer,
            occurredAt: date(year: 2026, month: 5, day: 1),
            account: sourceAccount,
            destinationAccount: destinationAccount
        )
        let secondTransfer = Movement(
            concept: "Entrada histórica",
            amount: 10,
            type: .transfer,
            occurredAt: date(year: 2026, month: 5, day: 2),
            account: destinationAccount,
            destinationAccount: sourceAccount
        )

        let report = try DataExportService.importData(
            DataExportService.ImportResult(
                banks: [],
                accounts: [],
                categories: [],
                movements: [secondTransfer, firstTransfer],
                investmentSnapshots: [],
                recurringMovements: [],
                budgets: []
            ),
            into: context,
            mode: .merge,
            currencyCode: "EUR"
        )

        #expect(report.imported.movements == 2)
        #expect(sourceAccount.investedAmount == 90)
        #expect(destinationAccount.investedAmount == 10)
        #expect(sourceAccount.balance == 90)
        #expect(destinationAccount.balance == 10)
    }

    @Test @MainActor func importPreservesInvestmentAccountFieldsFromBackup() async throws {
        let account = BankAccount(
            name: "Cuenta inversión",
            accountType: .investment,
            balance: 100,
            investedAmount: 60,
            marketValue: 120,
            marketValueUpdatedAt: date(year: 2026, month: 5, day: 1)
        )
        let url = try DataExportService.exportData(
            banks: [],
            accounts: [account],
            categories: [],
            movements: [],
            investmentSnapshots: [],
            recurringMovements: [],
            budgets: []
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataExportService.importData(from: url)
        let importedAccount = try #require(result.accounts.first)

        #expect(importedAccount.balance == 100)
        #expect(importedAccount.investedAmount == 60)
        #expect(importedAccount.marketValue == 120)
        #expect(importedAccount.marketValueUpdatedAt == date(year: 2026, month: 5, day: 1))
    }

    @Test @MainActor func importRejectsMissingMovementAccountReferenceBeforeMutation() async throws {
        let movementID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let missingAccountID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let date = "2026-05-01T00:00:00Z"
        let json = """
        {
          "version": 7,
          "exportDate": "\(date)",
          "banks": [],
          "accounts": [],
          "categories": [],
          "movements": [{
            "id": "\(movementID.uuidString)",
            "concept": "Invalid movement",
            "amount": 10,
            "type": "expense",
            "occurredAt": "\(date)",
            "notes": "",
            "resultingBalance": null,
            "recurringRuleId": null,
            "recurringScheduledAt": null,
            "personalAmount": null,
            "reimbursementForId": null,
            "createdAt": "\(date)",
            "updatedAt": "\(date)",
            "accountId": "\(missingAccountID.uuidString)",
            "destinationAccountId": null,
            "categoryId": null
          }],
          "investmentSnapshots": [],
          "recurringMovements": [],
          "budgets": []
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Finance_invalid_reference_\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try DataExportService.importData(from: url)
            #expect(Bool(false), "La referencia inexistente debe rechazar el archivo completo.")
        } catch {
            #expect(error.localizedDescription.contains("referencia inexistente"))
        }
    }

    @Test @MainActor func importRepairsMissingRecurringRuleReference() async throws {
        let movementID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let missingRuleID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let date = "2026-05-01T00:00:00Z"
        let json = """
        {
          "version": 7,
          "exportDate": "\(date)",
          "banks": [],
          "accounts": [],
          "categories": [],
          "movements": [{
            "id": "\(movementID.uuidString)",
            "concept": "Invalid recurring movement",
            "amount": 10,
            "type": "expense",
            "occurredAt": "\(date)",
            "notes": "",
            "resultingBalance": null,
            "recurringRuleId": "\(missingRuleID.uuidString)",
            "recurringScheduledAt": null,
            "personalAmount": null,
            "reimbursementForId": null,
            "createdAt": "\(date)",
            "updatedAt": "\(date)",
            "accountId": null,
            "destinationAccountId": null,
            "categoryId": null
          }],
          "investmentSnapshots": [],
          "recurringMovements": [],
          "budgets": []
        }
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Finance_invalid_recurring_reference_\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try DataExportService.importData(from: url)
        let importedMovement = try #require(result.movements.first)
        #expect(importedMovement.recurringRuleId == nil)
        #expect(result.repairedReferences == 1)
    }

    @Test @MainActor func mergeKeepsConflictingBudgetItemWhenBudgetIsNew() async throws {
        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
            Budget.self,
            BudgetItem.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let localBudget = Budget(totalAmount: 100)
        let localItem = BudgetItem(allocatedAmount: 100)
        localBudget.items = [localItem]
        context.insert(localBudget)
        context.insert(localItem)
        try context.save()

        let importedBudget = Budget(totalAmount: 200)
        let conflictingItem = BudgetItem(allocatedAmount: 100)
        conflictingItem.id = localItem.id
        let newItem = BudgetItem(allocatedAmount: 100)
        importedBudget.items = [conflictingItem, newItem]
        let importResult = DataExportService.ImportResult(
            banks: [],
            accounts: [],
            categories: [],
            movements: [],
            investmentSnapshots: [],
            recurringMovements: [],
            budgets: [importedBudget]
        )

        let report = try DataExportService.importData(
            importResult,
            into: context,
            mode: .merge,
            currencyCode: "EUR"
        )

        let savedBudgets = try context.fetch(FetchDescriptor<Budget>())
        let savedImportedBudget = try #require(savedBudgets.first { $0.id == importedBudget.id })
        #expect(report.imported.budgets == 1)
        #expect(report.imported.budgetItems == 1)
        #expect(report.conflicts.budgetItems == 1)
        #expect(savedBudgets.count == 2)
        #expect(localBudget.items.count == 1)
        #expect(savedImportedBudget.items.count == 1)
        #expect(savedImportedBudget.items.first?.id == newItem.id)
    }

    @Test func importReportSummaryExplainsConflictsByType() async throws {
        let imported = DataExportService.ImportCounts(
            banks: 0,
            accounts: 1,
            categories: 0,
            movements: 1,
            investmentSnapshots: 0,
            recurringMovements: 0,
            budgets: 0,
            budgetItems: 0
        )
        let conflicts = DataExportService.ImportCounts(
            banks: 1,
            accounts: 1,
            categories: 0,
            movements: 2,
            investmentSnapshots: 0,
            recurringMovements: 0,
            budgets: 0,
            budgetItems: 0
        )

        let report = DataExportService.ImportReport(
            mode: .merge,
            imported: imported,
            conflicts: conflicts
        )

        #expect(report.alertTitle == "Importación parcial")
        #expect(report.summary == "Se incorporaron 2 registros (1 cuenta, 1 movimiento). Se conservaron 4 conflictos locales (1 banco, 1 cuenta, 2 movimientos) y se omitieron los importados.")
    }

    @Test func importReportSummaryExplainsWhenNothingChanges() async throws {
        let empty = DataExportService.ImportCounts(
            banks: 0,
            accounts: 0,
            categories: 0,
            movements: 0,
            investmentSnapshots: 0,
            recurringMovements: 0,
            budgets: 0,
            budgetItems: 0
        )
        let conflicts = DataExportService.ImportCounts(
            banks: 0,
            accounts: 1,
            categories: 0,
            movements: 0,
            investmentSnapshots: 0,
            recurringMovements: 0,
            budgets: 0,
            budgetItems: 0
        )

        let report = DataExportService.ImportReport(
            mode: .merge,
            imported: empty,
            conflicts: conflicts
        )

        #expect(report.alertTitle == "Importación sin cambios")
        #expect(report.summary == "No se incorporó ningún registro. Se conservaron 1 conflicto local (1 cuenta) y se omitieron los importados.")
    }

    @Test @MainActor func repairReportsHistoricalValuesChanged() async throws {
        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
            Budget.self,
            BudgetItem.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let account = BankAccount(name: "Cuenta", accountType: .checking, balance: 70)
        let movement = Movement(
            concept: "Gasto histórico",
            amount: 30,
            type: .expense,
            occurredAt: date(year: 2026, month: 5, day: 2),
            account: account
        )
        movement.resultingBalance = 999
        context.insert(account)
        context.insert(movement)
        try context.save()

        let report = try MovementBalanceService.repair(in: context)

        #expect(report.accountsChecked == 1)
        #expect(report.movementsChecked == 1)
        #expect(report.accountsChanged == 0)
        #expect(report.movementsChanged == 1)
        #expect(movement.resultingBalance == 70)
    }

    private func makeAccount(createdAt: Date) -> BankAccount {
        let account = BankAccount(
            name: "Test account",
            accountType: .checking,
            balance: 0
        )
        account.createdAt = createdAt
        account.updatedAt = createdAt
        return account
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        testCalendar.date(from: DateComponents(
            timeZone: testCalendar.timeZone,
            year: year,
            month: month,
            day: day
        ))!
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

}
