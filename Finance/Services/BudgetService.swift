//
//  BudgetService.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import UserNotifications

/// Calcula el progreso del presupuesto mensual único y dispara notificaciones push
/// por categoría cuando se alcanzan los umbrales del 80 % y 100 % de la asignación.
enum BudgetService {

    // MARK: - Spending calculations

    /// Gasto real del mes en curso para una categoría concreta.
    static func spentAmount(
        for category: MovementCategory,
        movements: [Movement]
    ) -> Decimal {
        let calendar = Calendar.current
        let now = Date()
        let year  = calendar.component(.year,  from: now)
        let month = calendar.component(.month, from: now)

        return movements
            .filter { movement in
                guard movement.type == .expense else { return false }
                guard movement.category?.id == category.id else { return false }
                let mYear  = calendar.component(.year,  from: movement.occurredAt)
                let mMonth = calendar.component(.month, from: movement.occurredAt)
                return mYear == year && mMonth == month
            }
            .reduce(Decimal(0)) { $0 + $1.statsExpenseAmount }
    }

    /// Gasto real del mes en todas las categorías del presupuesto.
    static func totalSpent(for budget: Budget, movements: [Movement]) -> Decimal {
        budget.items.reduce(Decimal(0)) { total, item in
            guard let category = item.category else { return total }
            return total + spentAmount(for: category, movements: movements)
        }
    }

    /// Fracción [0, ∞) del presupuesto global consumido. 1.0 = 100 %.
    static func globalProgress(for budget: Budget, movements: [Movement]) -> Decimal {
        guard budget.totalAmount > 0 else { return 0 }
        return totalSpent(for: budget, movements: movements) / budget.totalAmount
    }

    /// Fracción [0, ∞) consumida de la asignación de un ítem concreto. 1.0 = 100 %.
    static func progress(for item: BudgetItem, movements: [Movement]) -> Decimal {
        guard let category = item.category else { return 0 }
        guard item.allocatedAmount > 0 else { return 0 }
        return spentAmount(for: category, movements: movements) / item.allocatedAmount
    }

    /// True si el presupuesto global ha alcanzado o superado el 80 %.
    static func isAlerting(budget: Budget, movements: [Movement]) -> Bool {
        guard budget.isActive else { return false }
        return globalProgress(for: budget, movements: movements) >= 0.8
    }

    // MARK: - Notifications

    private static let itemNotificationPrefix = "budget-item-"

    /// Evalúa cada ítem del presupuesto y programa/cancela notificaciones de umbral
    /// según el gasto actual de cada categoría. Llamar después de guardar un gasto.
    static func evaluateAndNotify(budget: Budget, movements: [Movement]) {
        guard budget.isActive else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }
            for item in budget.items {
                evaluateItem(item, budget: budget, movements: movements, center: center)
            }
        }
    }

    private static func evaluateItem(
        _ item: BudgetItem,
        budget: Budget,
        movements: [Movement],
        center: UNUserNotificationCenter
    ) {
        guard let category = item.category else { return }
        let pct = progress(for: item, movements: movements)
        let categoryName = category.name

        let id100 = "\(itemNotificationPrefix)\(item.id.uuidString)-100"
        let id80  = "\(itemNotificationPrefix)\(item.id.uuidString)-80"

        if budget.notifyAt100Percent && pct >= 1 {
            scheduleThresholdNotification(
                center: center,
                identifier: id100,
                title: "Presupuesto superado",
                body: "Has superado el presupuesto de \(categoryName) este mes."
            )
        } else {
            cancelNotification(center: center, identifier: id100)
        }

        if budget.notifyAt80Percent && pct >= 0.8 && pct < 1 {
            scheduleThresholdNotification(
                center: center,
                identifier: id80,
                title: "Alerta de presupuesto",
                body: "Llevas el 80 % del presupuesto de \(categoryName) este mes."
            )
        } else {
            cancelNotification(center: center, identifier: id80)
        }
    }

    private static func scheduleThresholdNotification(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String
    ) {
        // Only fire once per identifier: skip if already pending or delivered.
        center.getPendingNotificationRequests { pending in
            guard !pending.contains(where: { $0.identifier == identifier }) else { return }
            center.getDeliveredNotifications { delivered in
                guard !delivered.contains(where: { $0.request.identifier == identifier }) else { return }

                let content = UNMutableNotificationContent()
                content.title = title
                content.body  = body
                content.sound = .default

                // Immediate trigger (nil) — fire as soon as possible.
                let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
                center.add(request)
            }
        }
    }

    private static func cancelNotification(center: UNUserNotificationCenter, identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Cancela todas las notificaciones de todos los ítems del presupuesto.
    static func cancelAllNotifications(for budget: Budget) {
        let center = UNUserNotificationCenter.current()
        let ids = budget.items.flatMap { item in
            [
                "\(itemNotificationPrefix)\(item.id.uuidString)-80",
                "\(itemNotificationPrefix)\(item.id.uuidString)-100",
            ]
        }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
