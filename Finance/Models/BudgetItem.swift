//
//  BudgetItem.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import SwiftData

/// Línea de distribución de un presupuesto mensual.
/// Asocia una categoría con el importe máximo asignado dentro del presupuesto.
@Model
final class BudgetItem {
    var id: UUID
    /// Importe asignado a esta categoría dentro del presupuesto.
    var allocatedAmount: Decimal
    var createdAt: Date

    /// Presupuesto al que pertenece este ítem.
    var budget: Budget?

    /// Categoría de gasto. Si se elimina la categoría, el ítem queda huérfano
    /// pero no se borra: el usuario puede reasignarlo o eliminar el presupuesto.
    @Relationship(deleteRule: .nullify)
    var category: MovementCategory?

    init(allocatedAmount: Decimal, category: MovementCategory? = nil) {
        self.id = UUID()
        self.allocatedAmount = allocatedAmount
        self.category = category
        self.createdAt = Date()
    }
}

// MARK: - Codable DTO para Export/Import JSON

nonisolated struct BudgetItemDTO: Codable, Sendable {
    let id: UUID
    let allocatedAmount: Decimal
    let createdAt: Date
    let categoryId: UUID?

    init(from item: BudgetItem) {
        self.id = item.id
        self.allocatedAmount = item.allocatedAmount
        self.createdAt = item.createdAt
        self.categoryId = item.category?.id
    }

    func toModel() -> BudgetItem {
        let item = BudgetItem(
            allocatedAmount: allocatedAmount,
            category: nil
        )
        item.id = id
        item.createdAt = createdAt
        return item
    }
}
