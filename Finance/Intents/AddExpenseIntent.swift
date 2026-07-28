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

    enum IntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
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
    }
}
