//
//  WalletExpenseDraftTests.swift
//  FinanceTests
//

import Foundation
import Testing
import SwiftData
@testable import Finance

struct WalletExpenseDraftTests {
    @Test func draftNormalizesOptionalValuesAndKeepsTransactionData() {
        let transactionDate = Date(timeIntervalSince1970: 1_786_464_000)
        let draft = WalletExpenseDraft(
            amount: Decimal(string: "9.83"),
            currencyCode: " eur ",
            merchant: "  Carrefour  ",
            cardName: " Revolut 7792 ",
            transactionDate: transactionDate
        )

        #expect(draft.amount == Decimal(string: "9.83"))
        #expect(draft.currencyCode == "EUR")
        #expect(draft.merchant == "Carrefour")
        #expect(draft.cardName == "Revolut 7792")
        #expect(draft.transactionDate == transactionDate)
        #expect(draft.suggestedConcept == "Carrefour")
    }

    @Test func draftFallsBackToWalletConceptAndIgnoresInvalidAmount() {
        let draft = WalletExpenseDraft(amount: -2, merchant: "   ")

        #expect(draft.amount == nil)
        #expect(draft.merchant == nil)
        #expect(draft.suggestedConcept == "Pago con Wallet")
    }

    @Test func pendingDraftStoreKeepsInsertionOrderUntilAcknowledgement() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = WalletExpenseDraft(merchant: "Primero")
        let second = WalletExpenseDraft(merchant: "Segundo")
        try WalletExpenseDraftStore.enqueue(first, in: defaults)
        try WalletExpenseDraftStore.enqueue(second, in: defaults)

        #expect(WalletExpenseDraftStore.pendingDrafts(in: defaults).map(\.id) == [first.id, second.id])
        #expect(WalletExpenseDraftStore.nextPending(from: defaults)?.id == first.id)
        WalletExpenseDraftStore.acknowledge(first.id, in: defaults)
        #expect(WalletExpenseDraftStore.nextPending(from: defaults)?.id == second.id)
        WalletExpenseDraftStore.acknowledge(second.id, in: defaults)
        #expect(WalletExpenseDraftStore.nextPending(from: defaults) == nil)
        #expect(defaults.object(forKey: WalletExpenseDraftStore.storageKey) == nil)
    }

    @Test func pendingDraftStoreDiscardsCorruptPayload() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: WalletExpenseDraftStore.storageKey)

        #expect(WalletExpenseDraftStore.nextPending(from: defaults) == nil)
        #expect(defaults.object(forKey: WalletExpenseDraftStore.storageKey) == nil)
    }

    @Test func pendingDraftStoreDecodesPersistedWalletPayload() {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let payload = "W3siY3VycmVuY3lDb2RlIjoiRVVSIiwiY3JlYXRlZEF0Ijo4MDgxNzY2MDAsImlkIjoiMTExMTExMTEtMjIyMi0zMzMzLTQ0NDQtNTU1NTU1NTU1NTU1IiwibWVyY2hhbnQiOiJDYWZldGVyw61hIFBydWViYSIsImNhcmROYW1lIjoiUmV2b2x1dCDigKLigKLigKLigKIgNzc5MiIsImFtb3VudCI6OS44MywidHJhbnNhY3Rpb25EYXRlIjo4MDgxNzY2MDB9XQ=="
        defaults.set(Data(base64Encoded: payload), forKey: WalletExpenseDraftStore.storageKey)

        let draft = WalletExpenseDraftStore.nextPending(from: defaults)

        #expect(draft?.amount == Decimal(string: "9.83"))
        #expect(draft?.currencyCode == "EUR")
        #expect(draft?.merchant == "Cafetería Prueba")
        #expect(draft?.cardName == "Revolut •••• 7792")
    }

    @Test func pendingDraftRemainsUntilExplicitAcknowledgement() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let draft = WalletExpenseDraft(merchant: "Pendiente")
        try WalletExpenseDraftStore.enqueue(draft, in: defaults)

        #expect(WalletExpenseDraftStore.nextPending(from: defaults)?.id == draft.id)
        #expect(WalletExpenseDraftStore.nextPending(from: defaults)?.id == draft.id)

        WalletExpenseDraftStore.acknowledge(draft.id, in: defaults)

        #expect(WalletExpenseDraftStore.nextPending(from: defaults) == nil)
    }

    @Test func pendingDraftStoreDoesNotDiscardOlderDrafts() throws {
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let drafts = (0..<25).map { WalletExpenseDraft(merchant: "Comercio \($0)") }
        for draft in drafts {
            try WalletExpenseDraftStore.enqueue(draft, in: defaults)
        }

        #expect(WalletExpenseDraftStore.pendingDrafts(in: defaults).map(\.id) == drafts.map(\.id))
    }

    @Test func walletTextAmountParserKeepsCentsAndChecksEmbeddedCurrency() throws {
        for text in ["12,50", "12.50", "12,50 €", "€12.50", "EUR 12,50", "12.50 EUR", " 12,50 € "] {
            #expect(try RegisterWalletExpenseIntent.decimalAmount(from: text, currencyCode: "EUR") == Decimal(string: "12.50"))
        }
        #expect(try RegisterWalletExpenseIntent.decimalAmount(from: "9,83", currencyCode: "EUR") == Decimal(string: "9.83"))
        for text in ["", "NaN", "infinity", "-1", "1.234", "1,234", "1.234,50", "1,234.50", "12,50 basura", "$12.50", "12 50", "1+2"] {
            #expect(throws: RegisterWalletExpenseIntent.WalletIntentError.invalidAmountFormat) {
                try RegisterWalletExpenseIntent.decimalAmount(from: text, currencyCode: "EUR")
            }
        }
        #expect(throws: AddExpenseIntent.IntentError.invalidAmount) {
            try RegisterWalletExpenseIntent.decimalAmount(from: "0,00", currencyCode: "EUR")
        }
        for text in ["USD 12.50", "12,50 GBP", "£12.50"] {
            #expect(throws: RegisterWalletExpenseIntent.WalletIntentError.currencyMismatch) {
                try RegisterWalletExpenseIntent.decimalAmount(from: text, currencyCode: "EUR")
            }
        }
    }

    @Test @MainActor func automaticWalletExpenseKeepsCentsAndRebuildsBackdatedHistory() throws {
        let context = try makeWalletContext()
        let account = BankAccount(name: "Cuenta Wallet", accountType: .checking, balance: 90)
        context.insert(account)
        let later = Movement(
            concept: "Posterior", amount: 10, type: .expense,
            occurredAt: Date(timeIntervalSince1970: 200), account: account,
            resultingBalance: 90
        )
        context.insert(later)
        try context.save()

        let movement = try RegisterWalletExpenseIntent.register(
            amount: Decimal(string: "12.50")!, currencyCode: "EUR", accountID: account.id,
            merchant: " Cafetería ", cardName: " Visa de prueba ",
            transactionDate: Date(timeIntervalSince1970: 100),
            in: context, appCurrencyCode: "EUR"
        )

        #expect(movement.amount == Decimal(string: "12.50"))
        #expect(movement.concept == "Cafetería")
        #expect(movement.category == nil)
        #expect(movement.notes == "Tarjeta Wallet: Visa de prueba")
        #expect(movement.occurredAt == Date(timeIntervalSince1970: 100))
        #expect(account.balance == Decimal(string: "77.50"))
        #expect(movement.resultingBalance == Decimal(string: "87.50"))
        #expect(later.resultingBalance == Decimal(string: "77.50"))
        #expect(try context.fetchCount(FetchDescriptor<Movement>()) == 2)
    }

    @Test @MainActor func automaticWalletExpenseRejectsInvalidInputsWithoutSaving() throws {
        let context = try makeWalletContext()
        let account = BankAccount(name: "Cuenta Wallet", accountType: .checking, balance: 100)
        context.insert(account)
        try context.save()

        for amount: Decimal in [0, -1, .nan] {
            #expect(throws: AddExpenseIntent.IntentError.invalidAmount) {
                try RegisterWalletExpenseIntent.register(
                    amount: amount, currencyCode: "EUR", accountID: account.id,
                    in: context, appCurrencyCode: "EUR"
                )
            }
        }
        #expect(throws: RegisterWalletExpenseIntent.WalletIntentError.currencyMismatch) {
            try RegisterWalletExpenseIntent.register(
                amount: 12.50, currencyCode: "USD", accountID: account.id,
                in: context, appCurrencyCode: "EUR"
            )
        }
        #expect(throws: RegisterWalletExpenseIntent.WalletIntentError.currencyMismatch) {
            try RegisterWalletExpenseIntent.register(
                amount: 12.50, currencyCode: "", accountID: account.id,
                in: context, appCurrencyCode: "EUR"
            )
        }
        #expect(throws: AddExpenseIntent.IntentError.accountNotFound) {
            try RegisterWalletExpenseIntent.register(
                amount: 12.50, currencyCode: "EUR", accountID: UUID(),
                in: context, appCurrencyCode: "EUR"
            )
        }
        account.archive()
        try context.save()
        #expect(throws: AddExpenseIntent.IntentError.accountNotFound) {
            try RegisterWalletExpenseIntent.register(
                amount: 12.50, currencyCode: "EUR", accountID: account.id,
                in: context, appCurrencyCode: "EUR"
            )
        }
        #expect(account.balance == 100)
        #expect(try context.fetchCount(FetchDescriptor<Movement>()) == 0)
    }

    @MainActor private func makeWalletContext() throws -> ModelContext {
        let schema = Schema([
            Bank.self, BankAccount.self, MovementCategory.self, Movement.self,
            InvestmentSnapshot.self, RecurringMovement.self, Budget.self, BudgetItem.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "WalletExpenseDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
