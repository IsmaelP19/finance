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
        recurringScheduledAt: Date? = nil
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
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO para Export/Import JSON

struct MovementDTO: Codable {
    let id: UUID
    let concept: String
    let amount: Decimal
    let type: String
    let occurredAt: Date
    let notes: String
    let resultingBalance: Decimal?
    let recurringRuleId: UUID?
    let recurringScheduledAt: Date?
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
            recurringScheduledAt: recurringScheduledAt
        )
        movement.id = id
        movement.createdAt = createdAt
        movement.updatedAt = updatedAt
        return movement
    }
}
