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

@MainActor
struct FinanceTests {

    @Test func activeAccountIsVisibleAfterCreation() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))

        #expect(account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 2)))
    }

    @Test func accountIsNotVisibleBeforeCreation() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 2))

        #expect(!account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 1)))
    }

    @Test func recentlyExportedBackupDoesNotPromptWhenModificationDateIsNewer() async throws {
        let exportDate = date(year: 2026, month: 7, day: 1)
        let directoryURL = try makeBackupDirectory()
        defer {
            ManualSyncService.clearConfiguration()
            try? FileManager.default.removeItem(at: directoryURL)
        }

        let backupURL = try writeBackup(named: "Finance_backup_recent.json", exportDate: exportDate, in: directoryURL)
        try FileManager.default.setAttributes(
            [.modificationDate: exportDate.addingTimeInterval(86_400)],
            ofItemAtPath: backupURL.path
        )
        ManualSyncService.markExported(exportDate: exportDate)

        #expect(!ManualSyncService.shouldPromptForNewBackup(in: directoryURL))
    }

    @Test func latestBackupUsesEmbeddedExportDateWhenModificationDatesDiffer() async throws {
        let olderExportDate = date(year: 2026, month: 7, day: 1)
        let newerExportDate = date(year: 2026, month: 7, day: 3)
        let directoryURL = try makeBackupDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let olderURL = try writeBackup(named: "Finance_backup_older.json", exportDate: olderExportDate, in: directoryURL)
        let newerURL = try writeBackup(named: "Finance_backup_newer.json", exportDate: newerExportDate, in: directoryURL)
        try FileManager.default.setAttributes(
            [.modificationDate: newerExportDate.addingTimeInterval(-86_400)],
            ofItemAtPath: newerURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: newerExportDate.addingTimeInterval(86_400)],
            ofItemAtPath: olderURL.path
        )

        let latest = try ManualSyncService.latestBackup(in: directoryURL)

        #expect(latest.url == newerURL)
        #expect(latest.exportDate == newerExportDate)
    }

    @Test func genuinelyNewerRemoteBackupPrompts() async throws {
        let localExportDate = date(year: 2026, month: 7, day: 1)
        let remoteExportDate = date(year: 2026, month: 7, day: 2)
        let directoryURL = try makeBackupDirectory()
        defer {
            ManualSyncService.clearConfiguration()
            try? FileManager.default.removeItem(at: directoryURL)
        }

        _ = try writeBackup(named: "Finance_backup_remote.json", exportDate: remoteExportDate, in: directoryURL)
        ManualSyncService.markExported(exportDate: localExportDate)

        #expect(ManualSyncService.shouldPromptForNewBackup(in: directoryURL))
    }

    @Test func invalidBackupIsIgnoredWithoutBreakingLatestBackupFlow() async throws {
        let exportDate = date(year: 2026, month: 7, day: 2)
        let directoryURL = try makeBackupDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        try Data("not valid json".utf8).write(to: directoryURL.appendingPathComponent("Finance_backup_invalid.json"))
        let validURL = try writeBackup(named: "Finance_backup_valid.json", exportDate: exportDate, in: directoryURL)

        let latest = try ManualSyncService.latestBackup(in: directoryURL)

        #expect(latest.url == validURL)
        #expect(latest.exportDate == exportDate)
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

    @Test func skippedRecurringOccurrenceIsNotPendingButLaterOccurrencesRemain() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))
        let skippedDate = date(year: 2026, month: 5, day: 5)
        let rule = RecurringMovement(
            concept: "Variable bill",
            amount: 40,
            type: .expense,
            dayOfMonth: 5,
            startDate: skippedDate,
            account: account,
            skippedOccurrenceDates: [skippedDate]
        )

        let pending = RecurringMovementService.pendingMovements(
            for: [rule],
            confirmedMovements: [],
            now: date(year: 2026, month: 5, day: 1),
            horizonDays: 70,
            calendar: testCalendar
        )

        #expect(!pending.contains { testCalendar.isDate($0.dueDate, inSameDayAs: skippedDate) })
        #expect(pending.contains { testCalendar.isDate($0.dueDate, inSameDayAs: date(year: 2026, month: 6, day: 5)) })
    }

    @Test func recurringDTOBackupRoundTripPreservesSkippedOccurrences() async throws {
        let skippedDate = date(year: 2026, month: 5, day: 5)
        let rule = RecurringMovement(
            concept: "Variable bill",
            amount: 40,
            type: .expense,
            dayOfMonth: 5,
            startDate: skippedDate,
            skippedOccurrenceDates: [skippedDate]
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let restored = try decoder.decode(
            RecurringMovementDTO.self,
            from: encoder.encode(RecurringMovementDTO(from: rule))
        ).toModel()

        #expect(restored.skippedOccurrenceDates == [skippedDate])
    }

    @Test @MainActor func confirmingRecurringOccurrenceUsesActualAmountWithoutChangingTemplate() async throws {
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
        let account = BankAccount(name: "Cuenta", accountType: .checking, balance: 100)
        let dueDate = date(year: 2026, month: 5, day: 5)
        let rule = RecurringMovement(
            concept: "Variable bill",
            amount: 40,
            type: .expense,
            dayOfMonth: 5,
            startDate: dueDate,
            account: account
        )
        context.insert(account)
        context.insert(rule)
        try context.save()

        let movement = try RecurringMovementService.confirmOccurrence(
            rule: rule,
            dueDate: dueDate,
            amount: 55,
            applyToFuture: false,
            currencyCode: "EUR",
            in: context,
            calendar: testCalendar
        )

        #expect(movement.amount == 55)
        #expect(movement.recurringRuleId == rule.id)
        #expect(movement.recurringScheduledAt == dueDate)
        #expect(rule.amount == 40)
        #expect(account.balance == 45)
        #expect(movement.resultingBalance == 45)
    }

    @Test @MainActor func applyingRecurringAmountToFutureSplitsSeriesAtScheduledDate() async throws {
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
        let account = BankAccount(name: "Cuenta", accountType: .checking, balance: 100)
        let startDate = date(year: 2026, month: 5, day: 5)
        let dueDate = date(year: 2026, month: 6, day: 5)
        let rule = RecurringMovement(
            concept: "Variable bill",
            amount: 40,
            type: .expense,
            dayOfMonth: 5,
            startDate: startDate,
            account: account
        )
        context.insert(account)
        context.insert(rule)
        try context.save()

        let movement = try RecurringMovementService.confirmOccurrence(
            rule: rule,
            dueDate: dueDate,
            amount: 55,
            applyToFuture: true,
            currencyCode: "EUR",
            in: context,
            calendar: testCalendar
        )
        let rules = try context.fetch(FetchDescriptor<RecurringMovement>())
        let futureRule = try #require(rules.first { $0.id == movement.recurringRuleId })

        #expect(rules.count == 2)
        #expect(!rule.isActive)
        #expect(rule.amount == 40)
        #expect(rule.endDate == date(year: 2026, month: 6, day: 4))
        #expect(futureRule.isActive)
        #expect(futureRule.startDate == dueDate)
        #expect(futureRule.amount == 55)
        #expect(movement.amount == 55)
    }

    @Test func monthlyRecurrenceKeepsOriginalAnchorDayAfterAClampedMonth() async throws {
        let startDate = date(year: 2026, month: 1, day: 31)
        let rule = RecurringMovement(
            concept: "Variable bill",
            amount: 40,
            type: .expense,
            dayOfMonth: 31,
            startDate: startDate
        )
        let interval = DateInterval(
            start: startDate,
            end: date(year: 2026, month: 4, day: 1)
        )

        let dueDates = RecurringMovementService.dueDates(
            of: rule,
            in: interval,
            calendar: testCalendar
        )

        #expect(dueDates == [
            date(year: 2026, month: 1, day: 31),
            date(year: 2026, month: 2, day: 28),
            date(year: 2026, month: 3, day: 31)
        ])
    }

    @Test func recurringSegmentNeverGeneratesAnOccurrenceBeforeItsStartDate() async throws {
        let startDate = date(year: 2026, month: 6, day: 15)
        let rule = RecurringMovement(
            concept: "Changed frequency",
            amount: 40,
            type: .expense,
            frequency: .monthly,
            dayOfMonth: 5,
            startDate: startDate
        )
        let interval = DateInterval(
            start: date(year: 2026, month: 6, day: 1),
            end: date(year: 2026, month: 8, day: 1)
        )

        let dueDates = RecurringMovementService.dueDates(
            of: rule,
            in: interval,
            calendar: testCalendar
        )

        #expect(dueDates == [date(year: 2026, month: 7, day: 5)])
    }

    @Test func endedRecurrenceKeepsEarlierUnresolvedOccurrencePending() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 6, day: 1))
        let rule = RecurringMovement(
            concept: "Variable bill",
            amount: 40,
            type: .expense,
            dayOfMonth: 5,
            startDate: date(year: 2026, month: 6, day: 5),
            endDate: date(year: 2026, month: 6, day: 14),
            account: account,
            isActive: false
        )

        let pending = RecurringMovementService.pendingMovements(
            for: [rule],
            confirmedMovements: [],
            now: date(year: 2026, month: 6, day: 10),
            horizonDays: 60,
            calendar: testCalendar
        )

        #expect(pending.count == 1)
        #expect(testCalendar.isDate(pending[0].dueDate, inSameDayAs: date(year: 2026, month: 6, day: 5)))
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

    private func makeBackupDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinanceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        return directoryURL
    }

    private func writeBackup(named name: String, exportDate: Date, in directoryURL: URL) throws -> URL {
        let data = Data(
            "{\"version\":8,\"exportDate\":\"\(ISO8601DateFormatter().string(from: exportDate))\"}".utf8
        )
        let fileURL = directoryURL.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL
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
