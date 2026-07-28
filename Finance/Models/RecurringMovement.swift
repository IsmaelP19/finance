//
//  RecurringMovement.swift
//  Finance
//
//  Created by OpenCode on 17/02/2026.
//

import Foundation
import SwiftData

enum RecurringMovementFrequency: String, CaseIterable, Codable, Identifiable {
    case weekly = "weekly"
    case monthly = "monthly"
    case yearly = "yearly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly:
            return "Semanal"
        case .monthly:
            return "Mensual"
        case .yearly:
            return "Anual"
        }
    }
}

/// Plantilla de movimiento recurrente.
/// No impacta el saldo hasta que el usuario confirma la ocurrencia pendiente.
@Model
final class RecurringMovement {
    var id: UUID
    var concept: String
    var amount: Decimal
    var typeRaw: String
    var frequencyRaw: String
    var dayOfMonth: Int
    var startDate: Date
    var endDate: Date?
    var notes: String
    var isActive: Bool
    var skippedOccurrenceDatesData: Data = Data()
    var createdAt: Date
    var updatedAt: Date

    var account: BankAccount?
    var category: MovementCategory?

    var type: MovementType {
        get {
            let resolved = MovementType(rawValue: typeRaw) ?? .expense
            return resolved == .transfer ? .expense : resolved
        }
        set {
            typeRaw = newValue == .transfer ? MovementType.expense.rawValue : newValue.rawValue
        }
    }

    var frequency: RecurringMovementFrequency {
        get { RecurringMovementFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var skippedOccurrenceDates: [Date] {
        get {
            guard !skippedOccurrenceDatesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([Date].self, from: skippedOccurrenceDatesData)) ?? []
        }
        set {
            skippedOccurrenceDatesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        concept: String,
        amount: Decimal,
        type: MovementType,
        frequency: RecurringMovementFrequency = .monthly,
        dayOfMonth: Int,
        startDate: Date,
        endDate: Date? = nil,
        account: BankAccount? = nil,
        category: MovementCategory? = nil,
        notes: String = "",
        isActive: Bool = true,
        skippedOccurrenceDates: [Date] = []
    ) {
        self.id = UUID()
        self.concept = concept
        self.amount = amount
        self.typeRaw = type == .transfer ? MovementType.expense.rawValue : type.rawValue
        self.frequencyRaw = frequency.rawValue
        self.dayOfMonth = min(max(dayOfMonth, 1), 31)
        self.startDate = startDate
        self.endDate = endDate
        self.account = account
        self.category = category
        self.notes = notes
        self.isActive = isActive
        self.skippedOccurrenceDatesData = (try? JSONEncoder().encode(skippedOccurrenceDates)) ?? Data()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO para Export/Import JSON

struct RecurringMovementDTO: Codable {
    let id: UUID
    let concept: String
    let amount: Decimal
    let type: String
    let frequency: String
    let dayOfMonth: Int
    let startDate: Date
    let endDate: Date?
    let notes: String
    let isActive: Bool
    let skippedOccurrenceDates: [Date]
    let createdAt: Date
    let updatedAt: Date
    let accountId: UUID?
    let categoryId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case concept
        case amount
        case type
        case frequency
        case dayOfMonth
        case startDate
        case endDate
        case notes
        case isActive
        case skippedOccurrenceDates
        case createdAt
        case updatedAt
        case accountId
        case categoryId
    }

    init(from recurring: RecurringMovement) {
        id = recurring.id
        concept = recurring.concept
        amount = recurring.amount
        type = recurring.typeRaw
        frequency = recurring.frequencyRaw
        dayOfMonth = recurring.dayOfMonth
        startDate = recurring.startDate
        endDate = recurring.endDate
        notes = recurring.notes
        isActive = recurring.isActive
        skippedOccurrenceDates = recurring.skippedOccurrenceDates
        createdAt = recurring.createdAt
        updatedAt = recurring.updatedAt
        accountId = recurring.account?.id
        categoryId = recurring.category?.id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        concept = try container.decode(String.self, forKey: .concept)
        amount = try container.decode(Decimal.self, forKey: .amount)
        type = try container.decode(String.self, forKey: .type)
        frequency = try container.decodeIfPresent(String.self, forKey: .frequency) ?? RecurringMovementFrequency.monthly.rawValue
        dayOfMonth = try container.decode(Int.self, forKey: .dayOfMonth)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        skippedOccurrenceDates = try container.decodeIfPresent([Date].self, forKey: .skippedOccurrenceDates) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        accountId = try container.decodeIfPresent(UUID.self, forKey: .accountId)
        categoryId = try container.decodeIfPresent(UUID.self, forKey: .categoryId)
    }

    func toModel() -> RecurringMovement {
        let recurring = RecurringMovement(
            concept: concept,
            amount: amount,
            type: MovementType(rawValue: type) ?? .expense,
            frequency: RecurringMovementFrequency(rawValue: frequency) ?? .monthly,
            dayOfMonth: dayOfMonth,
            startDate: startDate,
            endDate: endDate,
            account: nil,
            category: nil,
            notes: notes,
            isActive: isActive,
            skippedOccurrenceDates: skippedOccurrenceDates
        )

        recurring.id = id
        recurring.createdAt = createdAt
        recurring.updatedAt = updatedAt
        return recurring
    }
}
