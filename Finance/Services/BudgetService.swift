//
//  BudgetService.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import UserNotifications

/// Calcula el progreso de presupuestos mensuales y dispara notificaciones push
/// cuando se alcanzan los umbrales del 80 % y 100 %.
enum BudgetService {

    // MARK: - Progress

    /// Gasto real del mes en curso para una categoría concreta.
    static func spentAmount(
        for category: MovementCategory,
        movements: [Movement]
    ) -> Decimal {
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
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

    /// Fracción [0, ∞) de presupuesto consumido. 1.0 = 100 %.
    static func progress(for budget: Budget, movements: [Movement]) -> Decimal {
        guard let category = budget.category else { return 0 }
        guard budget.limitAmount > 0 else { return 0 }
        let spent = spentAmount(for: category, movements: movements)
        return spent / budget.limitAmount
    }

    /// Número de presupuestos activos que han alcanzado o superado el 80 %.
    static func alertingBudgetsCount(budgets: [Budget], movements: [Movement]) -> Int {
        budgets.filter { budget in
            guard budget.isActive, budget.category != nil else { return false }
            return progress(for: budget, movements: movements) >= 0.8
        }.count
    }

    // MARK: - Notifications

    private static let notificationPrefix = "budget-threshold-"

    /// Evalúa todos los presupuestos activos y programa/cancela notificaciones
    /// de umbral según el gasto actual. Llamar después de guardar un gasto.
    static func evaluateAndNotify(budgets: [Budget], movements: [Movement]) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }
            for budget in budgets where budget.isActive {
                evaluateBudget(budget, movements: movements, center: center)
            }
        }
    }

    private static func evaluateBudget(
        _ budget: Budget,
        movements: [Movement],
        center: UNUserNotificationCenter
    ) {
        guard let category = budget.category else { return }

        let pct = progress(for: budget, movements: movements)
        let categoryName = category.name

        if budget.notifyAt100Percent && pct >= 1 {
            scheduleThresholdNotification(
                center: center,
                identifier: "\(notificationPrefix)\(budget.id.uuidString)-100",
                title: "Presupuesto superado",
                body: "Has superado el presupuesto de \(categoryName) este mes.",
                threshold: 100
            )
        } else {
            cancelNotification(center: center, identifier: "\(notificationPrefix)\(budget.id.uuidString)-100")
        }

        if budget.notifyAt80Percent && pct >= 0.8 && pct < 1 {
            scheduleThresholdNotification(
                center: center,
                identifier: "\(notificationPrefix)\(budget.id.uuidString)-80",
                title: "Alerta de presupuesto",
                body: "Llevas el 80 % del presupuesto de \(categoryName) este mes.",
                threshold: 80
            )
        } else {
            cancelNotification(center: center, identifier: "\(notificationPrefix)\(budget.id.uuidString)-80")
        }
    }

    private static func scheduleThresholdNotification(
        center: UNUserNotificationCenter,
        identifier: String,
        title: String,
        body: String,
        threshold: Int
    ) {
        // Only fire once per identifier: if already pending/delivered, skip.
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

    /// Cancela todas las notificaciones de un presupuesto (útil al borrarlo).
    static func cancelAllNotifications(for budget: Budget) {
        let center = UNUserNotificationCenter.current()
        let ids = [
            "\(notificationPrefix)\(budget.id.uuidString)-80",
            "\(notificationPrefix)\(budget.id.uuidString)-100",
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
