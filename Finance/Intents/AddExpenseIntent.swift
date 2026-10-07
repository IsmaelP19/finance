//
//  AddExpenseIntent.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import AppIntents
import SwiftData
import Foundation

/// Shortcut / Siri intent that creates an expense movement in Finance.
struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Apuntar gasto"
    static let description: IntentDescription = "Registra un gasto rápido en Finance."
    static let openAppWhenRun = false

    @Parameter(title: "Importe")
    var amount: Double

    @Parameter(title: "Concepto")
    var concept: String

    @Parameter(title: "Categoría")
    var category: MovementCategoryEntity

    @Parameter(title: "Cuenta bancaria")
    var account: BankAccountEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let decimalAmount = Decimal(amount)

        guard decimalAmount > 0 else {
            throw IntentError.invalidAmount
        }

        let container = FinanceModelContainerProvider.shared
        let context = ModelContext(container)

        // Extract IDs into local vars so #Predicate captures plain UUID values
        // (capturing AppEntity properties directly is unsupported by the macro).
        let accountID = account.id
        let categoryID = category.id

        // Find the real BankAccount in the current context
        let accountDescriptor = FetchDescriptor<BankAccount>(
            predicate: #Predicate { $0.id == accountID }
        )
        guard let bankAccount = try context.fetch(accountDescriptor).first, bankAccount.isActive else {
            throw IntentError.accountNotFound
        }

        // Find the real MovementCategory in the current context
        let categoryDescriptor = FetchDescriptor<MovementCategory>(
            predicate: #Predicate { $0.id == categoryID }
        )
        let movementCategory = try context.fetch(categoryDescriptor).first

        // Update account balance
        bankAccount.balance -= decimalAmount
        bankAccount.updatedAt = Date()

        let currencyCode = UserDefaults.standard.string(forKey: AppCurrency.storageKey) ?? AppCurrency.fallbackCode
        bankAccount.currency = currencyCode

        // Create the movement
        let movement = Movement(
            concept: concept,
            amount: decimalAmount,
            type: .expense,
            occurredAt: Date(),
            account: bankAccount,
            category: movementCategory,
            resultingBalance: bankAccount.balance
        )

        context.insert(movement)
        do {
            _ = try MovementBalanceService.rebuild(in: context)
        } catch {
            context.rollback()
            throw IntentError.balanceRebuildFailed
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        let amountFormatter = NumberFormatter()
        amountFormatter.numberStyle = .currency
        amountFormatter.currencyCode = currencyCode
        amountFormatter.locale = Locale.current
        let formattedAmount = amountFormatter.string(from: decimalAmount as NSDecimalNumber) ?? "\(decimalAmount) \(currencyCode)"
        return .result(dialog: "Gasto registrado: \(concept) — \(formattedAmount) en \(bankAccount.name).")
    }

    enum IntentError: Swift.Error, Equatable, CustomLocalizedStringResourceConvertible {
        case invalidAmount
        case accountNotFound
        case balanceRebuildFailed

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .invalidAmount:
                return "El importe debe ser mayor que cero."
            case .accountNotFound:
                return "No se encontró la cuenta bancaria seleccionada."
            case .balanceRebuildFailed:
                return "No se pudo reconstruir el historial de saldos. No se registró el gasto."
            }
        }
    }
}

/// Registers a Wallet payment using the account selected in its automation.
struct RegisterWalletExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Registrar gasto desde Wallet"
    static let description = IntentDescription(
        "Guarda el pago automáticamente en la cuenta seleccionada, sin abrir Finance. La categoría se asigna con los pagos anteriores de ese comercio."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Importe")
    var amount: String

    @Parameter(title: "Moneda")
    var currencyCode: String

    @Parameter(title: "Cuenta bancaria")
    var account: BankAccountEntity

    @Parameter(title: "Comercio")
    var merchant: String?

    @Parameter(title: "Tarjeta")
    var cardName: String?

    @Parameter(title: "Fecha")
    var transactionDate: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let decimalAmount = try Self.decimalAmount(from: amount, currencyCode: currencyCode)
        let context = ModelContext(FinanceModelContainerProvider.shared)
        // Only the explicit save below may persist the payment.
        context.autosaveEnabled = false
        let suggestedCategory = await WalletCategorySuggester.suggest(merchant: merchant, in: context)
        let movement = try Self.register(
            amount: decimalAmount,
            currencyCode: currencyCode,
            accountID: account.id,
            merchant: merchant,
            cardName: cardName,
            transactionDate: transactionDate,
            categoryID: suggestedCategory?.id,
            in: context,
            appCurrencyCode: AppCurrency.currentCode()
        )
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = AppCurrency.currentCode()
        formatter.locale = Locale.current
        let formatted = formatter.string(from: movement.amount as NSDecimalNumber) ?? "\(movement.amount)"
        let categorySuffix = movement.category.map { " (\($0.name))" } ?? ""
        return .result(dialog: "Gasto registrado: \(movement.concept) — \(formatted) en \(account.name)\(categorySuffix).")
    }

    /// Parses the original text, avoiding Shortcuts' numeric/currency conversions.
    /// Grouping separators are rejected because their interpretation is ambiguous.
    nonisolated static func decimalAmount(from text: String, currencyCode: String) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^(?:([A-Z]{3}|€|£|¥|\$)\s*)?([0-9]{1,30}(?:[,.][0-9]{1,2})?)(?:\s*([A-Z]{3}|€|£|¥|\$))?$"#
        let expression = try NSRegularExpression(pattern: pattern)
        guard let match = expression.firstMatch(
            in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)
        ), match.range.length == (trimmed as NSString).length else {
            throw WalletIntentError.invalidAmountFormat
        }
        let value = trimmed as NSString
        let expectedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        for index in [1, 3] where match.range(at: index).location != NSNotFound {
            let token = value.substring(with: match.range(at: index))
            let embeddedCurrency: String
            switch token {
            case "€": embeddedCurrency = "EUR"
            case "£": embeddedCurrency = "GBP"
            case "$", "¥":
                // These symbols identify several currencies; require an ISO code.
                throw WalletIntentError.invalidAmountFormat
            default: embeddedCurrency = token
            }
            guard embeddedCurrency == expectedCurrency else {
                throw WalletIntentError.currencyMismatch
            }
        }
        let number = value.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: ".")
        guard let amount = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")),
              !amount.isNaN, amount > 0 else {
            throw AddExpenseIntent.IntentError.invalidAmount
        }
        return amount
    }

    @MainActor
    @discardableResult
    static func register(
        amount: Decimal,
        currencyCode: String,
        accountID: UUID,
        merchant: String? = nil,
        cardName: String? = nil,
        transactionDate: Date? = nil,
        categoryID: UUID? = nil,
        in context: ModelContext,
        appCurrencyCode: String
    ) throws -> Movement {
        guard !amount.isNaN, amount > 0 else {
            throw AddExpenseIntent.IntentError.invalidAmount
        }
        let draft = WalletExpenseDraft(
            amount: amount, currencyCode: currencyCode, merchant: merchant,
            cardName: cardName, transactionDate: transactionDate
        )
        guard draft.currencyCode == appCurrencyCode else {
            throw WalletIntentError.currencyMismatch
        }
        let descriptor = FetchDescriptor<BankAccount>(predicate: #Predicate { $0.id == accountID })
        guard let bankAccount = try context.fetch(descriptor).first, bankAccount.isActive else {
            throw AddExpenseIntent.IntentError.accountNotFound
        }
        var movementCategory: MovementCategory?
        if let categoryID {
            let descriptor = FetchDescriptor<MovementCategory>(predicate: #Predicate { $0.id == categoryID })
            guard let selectedCategory = try context.fetch(descriptor).first else {
                throw WalletIntentError.categoryNotFound
            }
            movementCategory = selectedCategory
        }

        bankAccount.balance -= amount
        bankAccount.updatedAt = Date()
        bankAccount.currency = appCurrencyCode
        let movement = Movement(
            concept: draft.suggestedConcept,
            amount: amount,
            type: .expense,
            occurredAt: draft.transactionDate,
            account: bankAccount,
            category: movementCategory,
            notes: draft.cardName.map { "Tarjeta Wallet: \($0)" } ?? "",
            resultingBalance: bankAccount.balance
        )
        context.insert(movement)
        do {
            _ = try MovementBalanceService.rebuild(in: context)
        } catch {
            context.rollback()
            throw AddExpenseIntent.IntentError.balanceRebuildFailed
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return movement
    }

    enum WalletIntentError: Swift.Error, Equatable, CustomLocalizedStringResourceConvertible {
        case currencyMismatch
        case categoryNotFound
        case invalidAmountFormat

        var localizedStringResource: LocalizedStringResource {
            switch self {
            case .currencyMismatch:
                return "La moneda del pago no coincide con la moneda configurada en Finance. No se registró el gasto."
            case .categoryNotFound:
                return "No se encontró la categoría seleccionada. No se registró el gasto."
            case .invalidAmountFormat:
                return "El importe debe ser texto como 12,50 o 12.50, sin separadores de miles. Usa un código de moneda si el símbolo es ambiguo."
            }
        }
    }
}

/// Receives the values exposed by a Wallet transaction automation and opens a review draft.
struct PrepareWalletExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Preparar gasto desde Wallet"
    static let description = IntentDescription(
        "Abre Finance con un borrador para revisar el pago, elegir cuenta y categoría y guardarlo manualmente."
    )
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Importe")
    var amount: IntentCurrencyAmount?

    @Parameter(title: "Comercio")
    var merchant: String?

    @Parameter(title: "Tarjeta")
    var cardName: String?

    @Parameter(title: "Fecha")
    var transactionDate: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let draft = WalletExpenseDraft(
            amount: amount?.amount,
            currencyCode: amount?.currencyCode,
            merchant: merchant,
            cardName: cardName,
            transactionDate: transactionDate
        )
        try WalletExpenseDraftStore.enqueue(draft)
        DeepLinkRouter.shared.notifyWalletExpenseDraftAvailable()

        return .result(dialog: "Abriendo Finance para revisar el gasto. No se guardará hasta que lo confirmes.")
    }
}

/// Shortcuts provider that surfaces the AddExpenseIntent in the Shortcuts app.
struct FinanceShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Apunta un gasto en \(.applicationName)",
                "Registra un gasto en \(.applicationName)",
                "Añade un gasto en \(.applicationName)"
            ],
            shortTitle: "Apuntar gasto",
            systemImageName: "arrow.down.circle.fill"
        )

        AppShortcut(
            intent: RegisterWalletExpenseIntent(),
            phrases: [
                "Registra un pago de Wallet en \(.applicationName)"
            ],
            shortTitle: "Registrar Wallet",
            systemImageName: "wallet.pass.fill"
        )

        AppShortcut(
            intent: PrepareWalletExpenseIntent(),
            phrases: [
                "Prepara un gasto de Wallet en \(.applicationName)",
                "Revisa un pago de Wallet en \(.applicationName)"
            ],
            shortTitle: "Gasto de Wallet",
            systemImageName: "wallet.pass.fill"
        )
    }
}
