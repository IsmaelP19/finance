//
//  WalletCategoryMatcherTests.swift
//  FinanceTests
//

import Foundation
import SwiftData
import Testing
@testable import Finance

struct WalletCategoryMatcherTests {
    @Test func normalizedMerchantIgnoresCaseAccentsAndPunctuation() {
        #expect(WalletCategoryMatcher.normalizedMerchant("  Café  Central, S.A. ") == "cafe central s a")
        #expect(WalletCategoryMatcher.normalizedMerchant("CAFE CENTRAL S.A.") == "cafe central s a")
        #expect(WalletCategoryMatcher.normalizedMerchant("   ") == nil)
        #expect(WalletCategoryMatcher.normalizedMerchant(nil) == nil)
    }

    @Test func preferredCategoryFollowsTheLatestPaymentAtThatMerchant() {
        let food = UUID()
        let transport = UUID()
        let samples = [
            WalletExpenseCategorySample(
                concept: "Cafe Central",
                categoryID: food,
                occurredAt: Date(timeIntervalSince1970: 10)
            ),
            WalletExpenseCategorySample(
                concept: "Otro comercio",
                categoryID: transport,
                occurredAt: Date(timeIntervalSince1970: 30)
            ),
            WalletExpenseCategorySample(
                concept: "CAFÉ CENTRAL",
                categoryID: transport,
                occurredAt: Date(timeIntervalSince1970: 20)
            )
        ]

        let merchant = WalletCategoryMatcher.normalizedMerchant("cafe central")
        #expect(WalletCategoryMatcher.preferredCategoryID(
            forNormalizedMerchant: merchant!,
            samples: samples
        ) == transport)
        #expect(WalletCategoryMatcher.preferredCategoryID(
            forNormalizedMerchant: "desconocido",
            samples: samples
        ) == nil)
    }

    @Test @MainActor func knownMerchantReusesItsCategoryWithoutCallingTheModel() async throws {
        let context = try makeContext()
        let account = BankAccount(name: "Cuenta", accountType: .checking, balance: 100)
        let food = MovementCategory(name: "Alimentación")
        let transport = MovementCategory(name: "Transporte")
        context.insert(account)
        context.insert(food)
        context.insert(transport)
        context.insert(Movement(
            concept: "Mercadona",
            amount: 10,
            type: .expense,
            occurredAt: Date(timeIntervalSince1970: 10),
            account: account,
            category: food
        ))
        context.insert(Movement(
            concept: "Mercadona",
            amount: 20,
            type: .income,
            occurredAt: Date(timeIntervalSince1970: 50),
            account: account,
            category: transport
        ))
        try context.save()

        let model = ScriptedWalletCategoryModel(result: "Transporte")
        let category = await WalletCategorySuggester.suggest(
            merchant: " mercadona ",
            in: context,
            model: model
        )

        #expect(category?.id == food.id)
        #expect(model.calls == 0)
    }

    @Test @MainActor func newMerchantUsesTheModelOnlyWhenTheNameExists() async throws {
        let context = try makeContext()
        let food = MovementCategory(name: "Alimentación")
        context.insert(food)
        try context.save()

        let matching = ScriptedWalletCategoryModel(result: "alimentacion")
        let category = await WalletCategorySuggester.suggest(
            merchant: "Panadería Norte",
            in: context,
            model: matching
        )
        #expect(category?.id == food.id)
        #expect(matching.calls == 1)

        let unknown = ScriptedWalletCategoryModel(result: "Ocio")
        let missing = await WalletCategorySuggester.suggest(
            merchant: "Panadería Norte",
            in: context,
            model: unknown
        )
        #expect(missing == nil)
        #expect(unknown.calls == 1)
    }

    @Test @MainActor func slowModelDoesNotBlockTheSuggestion() async throws {
        let context = try makeContext()
        context.insert(MovementCategory(name: "Alimentación"))
        try context.save()

        let model = ScriptedWalletCategoryModel(result: "Alimentación", delay: .seconds(2))
        let clock = ContinuousClock()
        let started = clock.now
        let category = await WalletCategorySuggester.suggest(
            merchant: "Comercio nuevo",
            in: context,
            model: model,
            modelTimeout: .milliseconds(200)
        )

        #expect(category == nil)
        #expect(clock.now - started < .seconds(1))
    }

    @Test @MainActor func blankMerchantSkipsHistoryAndTheModel() async throws {
        let context = try makeContext()
        context.insert(MovementCategory(name: "Alimentación"))
        try context.save()
        let model = ScriptedWalletCategoryModel(result: "Alimentación")

        let category = await WalletCategorySuggester.suggest(merchant: "  ", in: context, model: model)

        #expect(category == nil)
        #expect(model.calls == 0)
    }

    @MainActor private func makeContext() throws -> ModelContext {
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
}

private final class ScriptedWalletCategoryModel: WalletMerchantCategoryModeling, @unchecked Sendable {
    var result: String?
    var delay: Duration
    private let lock = NSLock()
    private var callCount = 0

    init(result: String?, delay: Duration = .zero) {
        self.result = result
        self.delay = delay
    }

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }

    func categoryName(forMerchant merchant: String, allowedNames: [String]) async -> String? {
        lock.lock()
        callCount += 1
        lock.unlock()
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return result
    }
}
