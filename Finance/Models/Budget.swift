//
//  Budget.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import SwiftData

/// Presupuesto mensual de gasto asociado a una categoría.
/// El progreso se calcula comparando el gasto real del mes en curso
/// contra `limitAmount` mediante `BudgetService`.
@Model
final class Budget {
    var id: UUID
    /// Límite de gasto mensual.
    var limitAmount: Decimal
    /// Si false, el presupuesto existe pero no se muestra ni evalúa.
    var isActive: Bool
    /// Enviar push cuando el gasto alcanza el 80 % del límite.
    var notifyAt80Percent: Bool
    /// Enviar push cuando el gasto alcanza o supera el 100 % del límite.
    var notifyAt100Percent: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Categoría a la que aplica este presupuesto.
    /// Si se elimina la categoría, el presupuesto queda huérfano (nullify)
    /// pero no se borra: el usuario puede reasignar o eliminar el presupuesto.
    @Relationship(deleteRule: .nullify)
    var category: MovementCategory?

    init(
        limitAmount: Decimal,
        category: MovementCategory? = nil,
        isActive: Bool = true,
        notifyAt80Percent: Bool = true,
        notifyAt100Percent: Bool = true
    ) {
        self.id = UUID()
        self.limitAmount = limitAmount
        self.category = category
        self.isActive = isActive
        self.notifyAt80Percent = notifyAt80Percent
        self.notifyAt100Percent = notifyAt100Percent
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
