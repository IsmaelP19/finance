//
//  Movement.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import Foundation
import SwiftData

/// Movimiento financiero registrado sobre una cuenta.
@Model
final class Movement {
    var id: UUID
    var concept: String
    var amount: Decimal
    var typeRaw: String
    var occurredAt: Date
    var notes: String
    var resultingBalance: Decimal?
    var recurringRuleId: UUID?
    var recurringScheduledAt: Date?
    var personalAmount: Decimal?
    var reimbursementForId: UUID?
    var createdAt: Date
    var updatedAt: Date

    /// Cuenta asociada al movimiento.
    var account: BankAccount?

    /// Cuenta destino para transferencias entre cuentas.
    var destinationAccount: BankAccount?

    /// Categoría del movimiento.
    var category: MovementCategory?

    var type: MovementType {
        get { MovementType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    /// Importe con signo aplicado según tipo (gasto negativo, ingreso positivo).
    var signedAmount: Decimal {
        amount * type.signMultiplier
    }

    var normalizedPersonalAmount: Decimal? {
        guard type == .expense, let personalAmount else { return nil }
        if personalAmount < 0 { return 0 }
        if personalAmount > amount { return amount }
        return personalAmount
    }

    var isSharedExpense: Bool {
        guard let normalizedPersonalAmount else { return false }
        return normalizedPersonalAmount < amount
    }

    var isReimbursementIncome: Bool {
        type == .income && reimbursementForId != nil
    }

    var statsExpenseAmount: Decimal {
        guard type == .expense else { return 0 }
        return normalizedPersonalAmount ?? amount
    }

    var statsIncomeAmount: Decimal {
        guard type == .income else { return 0 }
        return isReimbursementIncome ? 0 : amount
    }

    var expectedReimbursementAmount: Decimal {
        guard type == .expense else { return 0 }
        return max(amount - statsExpenseAmount, 0)
    }

    func pendingReimbursementAmount(recoveredAmount: Decimal) -> Decimal {
        guard type == .expense else { return 0 }
        return max(expectedReimbursementAmount - max(recoveredAmount, 0), 0)
    }

    func reimbursementOverageAmount(recoveredAmount: Decimal) -> Decimal {
        guard type == .expense else { return 0 }
        return max(max(recoveredAmount, 0) - expectedReimbursementAmount, 0)
    }

    func duplicatedForNewEntry(on date: Date = Date()) -> Movement {
        Movement(
            concept: concept,
            amount: amount,
            type: type,
            occurredAt: date,
            account: account,
            destinationAccount: destinationAccount,
            category: category,
            notes: notes,
            personalAmount: personalAmount
        )
    }

    init(
        concept: String,
        amount: Decimal,
        type: MovementType,
        occurredAt: Date = Date(),
        account: BankAccount? = nil,
        destinationAccount: BankAccount? = nil,
        category: MovementCategory? = nil,
        notes: String = "",
        resultingBalance: Decimal? = nil,
        recurringRuleId: UUID? = nil,
        recurringScheduledAt: Date? = nil,
        personalAmount: Decimal? = nil,
        reimbursementForId: UUID? = nil
    ) {
        self.id = UUID()
        self.concept = concept
        self.amount = amount
        self.typeRaw = type.rawValue
        self.occurredAt = occurredAt
        self.account = account
        self.destinationAccount = destinationAccount
        self.category = category
        self.notes = notes
        self.resultingBalance = resultingBalance
        self.recurringRuleId = recurringRuleId
        self.recurringScheduledAt = recurringScheduledAt
        self.personalAmount = personalAmount
        self.reimbursementForId = reimbursementForId
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO para Export/Import JSON

nonisolated struct MovementDTO: Codable, Sendable {
    let id: UUID
    let concept: String
    let amount: Decimal
    let type: String
    let occurredAt: Date
    let notes: String
    let resultingBalance: Decimal?
    let recurringRuleId: UUID?
    let recurringScheduledAt: Date?
    let personalAmount: Decimal?
    let reimbursementForId: UUID?
    let createdAt: Date
    let updatedAt: Date
    let accountId: UUID?
    let destinationAccountId: UUID?
    let categoryId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case concept
        case amount
        case type
        case occurredAt
        case notes
        case resultingBalance
        case recurringRuleId
        case recurringScheduledAt
        case personalAmount
        case reimbursementForId
        case createdAt
        case updatedAt
        case accountId
        case destinationAccountId
        case categoryId
    }

    init(from movement: Movement) {
        self.id = movement.id
        self.concept = movement.concept
        self.amount = movement.amount
        self.type = movement.typeRaw
        self.occurredAt = movement.occurredAt
        self.notes = movement.notes
        self.resultingBalance = movement.resultingBalance
        self.recurringRuleId = movement.recurringRuleId
        self.recurringScheduledAt = movement.recurringScheduledAt
        self.personalAmount = movement.personalAmount
        self.reimbursementForId = movement.reimbursementForId
        self.createdAt = movement.createdAt
        self.updatedAt = movement.updatedAt
        self.accountId = movement.account?.id
        self.destinationAccountId = movement.destinationAccount?.id
        self.categoryId = movement.category?.id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        concept = try container.decode(String.self, forKey: .concept)
        amount = try container.decode(Decimal.self, forKey: .amount)
        type = try container.decode(String.self, forKey: .type)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        notes = try container.decode(String.self, forKey: .notes)
        resultingBalance = try container.decodeIfPresent(Decimal.self, forKey: .resultingBalance)
        recurringRuleId = try container.decodeIfPresent(UUID.self, forKey: .recurringRuleId)
        recurringScheduledAt = try container.decodeIfPresent(Date.self, forKey: .recurringScheduledAt)
        personalAmount = try container.decodeIfPresent(Decimal.self, forKey: .personalAmount)
        reimbursementForId = try container.decodeIfPresent(UUID.self, forKey: .reimbursementForId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        accountId = try container.decodeIfPresent(UUID.self, forKey: .accountId)
        destinationAccountId = try container.decodeIfPresent(UUID.self, forKey: .destinationAccountId)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
    }

    func toModel() -> Movement {
        let movement = Movement(
            concept: concept,
            amount: amount,
            type: MovementType(rawValue: type) ?? .expense,
            occurredAt: occurredAt,
            account: nil,
            destinationAccount: nil,
            category: nil,
            notes: notes,
            resultingBalance: resultingBalance,
            recurringRuleId: recurringRuleId,
            recurringScheduledAt: recurringScheduledAt,
            personalAmount: personalAmount,
            reimbursementForId: reimbursementForId
        )
        movement.id = id
        movement.createdAt = createdAt
        movement.updatedAt = updatedAt
        return movement
    }
}
