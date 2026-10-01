//
//  Budget.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import SwiftData

/// Presupuesto mensual global único.
/// Contiene un importe total y una lista de ítems por categoría
/// que deben sumar exactamente el total.
@Model
final class Budget {
    var id: UUID
    /// Importe total del presupuesto mensual.
    var totalAmount: Decimal
    /// Si false, el presupuesto existe pero no se muestra ni evalúa.
    var isActive: Bool
    /// Enviar push cuando el gasto de una categoría alcanza el 80 % de su asignación.
    var notifyAt80Percent: Bool
    /// Enviar push cuando el gasto de una categoría alcanza o supera el 100 % de su asignación.
    var notifyAt100Percent: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Distribución del presupuesto por categoría.
    /// Al eliminar el presupuesto, se eliminan en cascada todos sus ítems.
    @Relationship(deleteRule: .cascade, inverse: \BudgetItem.budget)
    var items: [BudgetItem] = []

    init(
        totalAmount: Decimal,
        isActive: Bool = true,
        notifyAt80Percent: Bool = true,
        notifyAt100Percent: Bool = true
    ) {
        self.id = UUID()
        self.totalAmount = totalAmount
        self.isActive = isActive
        self.notifyAt80Percent = notifyAt80Percent
        self.notifyAt100Percent = notifyAt100Percent
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO para Export/Import JSON

nonisolated struct BudgetDTO: Codable, Sendable {
    let id: UUID
    let totalAmount: Decimal
    let isActive: Bool
    let notifyAt80Percent: Bool
    let notifyAt100Percent: Bool
    let createdAt: Date
    let updatedAt: Date
    let items: [BudgetItemDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case totalAmount
        case isActive
        case notifyAt80Percent
        case notifyAt100Percent
        case createdAt
        case updatedAt
        case items
    }

    init(from budget: Budget) {
        self.id = budget.id
        self.totalAmount = budget.totalAmount
        self.isActive = budget.isActive
        self.notifyAt80Percent = budget.notifyAt80Percent
        self.notifyAt100Percent = budget.notifyAt100Percent
        self.createdAt = budget.createdAt
        self.updatedAt = budget.updatedAt
        self.items = budget.items.map { BudgetItemDTO(from: $0) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        totalAmount = try container.decode(Decimal.self, forKey: .totalAmount)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        notifyAt80Percent = try container.decodeIfPresent(Bool.self, forKey: .notifyAt80Percent) ?? true
        notifyAt100Percent = try container.decodeIfPresent(Bool.self, forKey: .notifyAt100Percent) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        items = try container.decodeIfPresent([BudgetItemDTO].self, forKey: .items) ?? []
    }

    func toModel() -> Budget {
        let budget = Budget(
            totalAmount: totalAmount,
            isActive: isActive,
            notifyAt80Percent: notifyAt80Percent,
            notifyAt100Percent: notifyAt100Percent
        )
        budget.id = id
        budget.createdAt = createdAt
        budget.updatedAt = updatedAt
        return budget
    }
}
