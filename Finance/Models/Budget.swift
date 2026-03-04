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
