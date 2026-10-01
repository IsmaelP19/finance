//
//  WalletExpenseDraftTests.swift
//  FinanceTests
//

import Foundation
import Testing
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

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "WalletExpenseDraftTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
