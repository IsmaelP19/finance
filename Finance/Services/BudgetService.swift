//
//  BudgetService.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import UserNotifications

/// Calcula el progreso del presupuesto mensual único y gestiona notificaciones locales
/// por categoría cuando se alcanzan los umbrales del 80 % y 100 % de la asignación.
enum BudgetService {
    private struct BudgetNotificationAction: Sendable {
        let id80: String
        let id100: String
        let categoryName: String
        let notifyAt80Percent: Bool
        let notifyAt100Percent: Bool
        let progress: Decimal
    }

    // MARK: - Spending calculations

    static func forecast(for budget: Budget, movements: [Movement], asOf date: Date = Date()) -> SpendingForecast {
        let spent = totalSpent(for: budget, movements: movements, asOf: date)
        let spendingDays = monthlySpendingDays(for: budget, movements: movements, asOf: date)
        let historicalSample = historicalRemainingSpendAverage(for: budget, movements: movements, asOf: date)

        return SpendingForecastCalculator.makeForecast(
            monthlyBudget: budget.totalAmount,
            spentSoFar: spent,
            spendingDays: spendingDays,
            historicalRemainingSpendAverage: historicalSample?.average,
            historicalMonthsUsed: historicalSample?.monthsUsed ?? 0,
            asOf: date
        )
    }

    static func forecast(for item: BudgetItem, movements: [Movement], asOf date: Date = Date()) -> SpendingForecast? {
        // Uso interno heredado para cálculos puntuales por ítem. La experiencia de previsión
        // soportada en producto es solo global para evitar extrapolar gastos puntuales por categoría.
        guard let category = item.category else { return nil }
        let spent = spentAmount(for: category, movements: movements, asOf: date)
        let spendingDays = monthlySpendingDays(for: category, movements: movements, asOf: date)

        return SpendingForecastCalculator.makeForecast(
            monthlyBudget: item.allocatedAmount,
            spentSoFar: spent,
            spendingDays: spendingDays,
            asOf: date
        )
    }

    /// Gasto real del mes en curso para una categoría concreta.
    static func spentAmount(
        for category: MovementCategory,
        movements: [Movement],
        asOf date: Date = Date()
    ) -> Decimal {
        let calendar = Calendar.current
        let year  = calendar.component(.year,  from: date)
        let month = calendar.component(.month, from: date)

        return movements
            .filter { movement in
                guard movement.type == .expense else { return false }
                guard movement.category?.id == category.id else { return false }
                guard movement.occurredAt <= date else { return false }
                let mYear  = calendar.component(.year,  from: movement.occurredAt)
                let mMonth = calendar.component(.month, from: movement.occurredAt)
                return mYear == year && mMonth == month
            }
            .reduce(Decimal(0)) { $0 + $1.statsExpenseAmount }
    }

    /// Gasto real del mes en todas las categorías del presupuesto.
    static func totalSpent(for budget: Budget, movements: [Movement], asOf date: Date = Date()) -> Decimal {
        budget.items.reduce(Decimal(0)) { total, item in
            guard let category = item.category else { return total }
            return total + spentAmount(for: category, movements: movements, asOf: date)
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

    @MainActor
    static func requestNotificationAuthorizationIfNeeded(
        completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let authorizationStatus = await center.notificationSettings().authorizationStatus
            switch authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion?(true)
            case .notDetermined:
                completion?((try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true)
            case .denied:
                completion?(false)
            @unknown default:
                completion?(false)
            }
        }
    }

    /// Evalúa cada ítem del presupuesto y programa/cancela notificaciones de umbral
    /// según el gasto actual de cada categoría. Llamar después de guardar un gasto.
    @MainActor
    static func evaluateAndNotify(budget: Budget, movements: [Movement]) {
        guard budget.isActive else { return }
        let actions = budget.items.compactMap { notificationAction(for: $0, budget: budget, movements: movements) }

        guard !actions.isEmpty else { return }

        requestNotificationAuthorizationIfNeeded { granted in
            guard granted else { return }
            let center = UNUserNotificationCenter.current()
            for action in actions {
                evaluateAction(action, center: center)
            }
        }
    }

    private static func notificationAction(
        for item: BudgetItem,
        budget: Budget,
        movements: [Movement]
    ) -> BudgetNotificationAction? {
        guard let category = item.category else { return nil }

        return BudgetNotificationAction(
            id80: "\(itemNotificationPrefix)\(item.id.uuidString)-80",
            id100: "\(itemNotificationPrefix)\(item.id.uuidString)-100",
            categoryName: category.name,
            notifyAt80Percent: budget.notifyAt80Percent,
            notifyAt100Percent: budget.notifyAt100Percent,
            progress: progress(for: item, movements: movements)
        )
    }

    @MainActor
    private static func evaluateAction(_ action: BudgetNotificationAction, center: UNUserNotificationCenter) {
        if action.notifyAt100Percent && action.progress >= 1 {
            scheduleThresholdNotification(
                identifier: action.id100,
                title: "Presupuesto superado",
                body: "Has superado el presupuesto de \(action.categoryName) este mes."
            )
        } else {
            cancelNotification(center: center, identifier: action.id100)
        }

        if action.notifyAt80Percent && action.progress >= 0.8 && action.progress < 1 {
            scheduleThresholdNotification(
                identifier: action.id80,
                title: "Alerta de presupuesto",
                body: "Llevas el 80 % del presupuesto de \(action.categoryName) este mes."
            )
        } else {
            cancelNotification(center: center, identifier: action.id80)
        }
    }

    @MainActor
    private static func scheduleThresholdNotification(
        identifier: String,
        title: String,
        body: String
    ) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard !pending.contains(where: { $0.identifier == identifier }) else { return }

            let delivered = await center.deliveredNotifications()
            guard !delivered.contains(where: { $0.request.identifier == identifier }) else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body  = body
            content.sound = .default

            // Immediate trigger (nil) — fire as soon as possible.
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    @MainActor
    private static func cancelNotification(center: UNUserNotificationCenter, identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func monthlySpendingDays(for budget: Budget, movements: [Movement], asOf date: Date) -> Int {
        let categoryIDs = Set(budget.items.compactMap { $0.category?.id })
        guard !categoryIDs.isEmpty else { return 0 }

        return monthlySpendingDays(for: movements, asOf: date) { movement in
            guard let categoryID = movement.category?.id else { return false }
            return categoryIDs.contains(categoryID)
        }
    }

    private static func monthlySpendingDays(for category: MovementCategory, movements: [Movement], asOf date: Date) -> Int {
        monthlySpendingDays(for: movements, asOf: date) { movement in
            movement.category?.id == category.id
        }
    }

    private static func monthlySpendingDays(
        for movements: [Movement],
        asOf date: Date,
        matchesCategory: (Movement) -> Bool
    ) -> Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let days = movements.compactMap { movement -> Date? in
            guard movement.type == .expense else { return nil }
            guard matchesCategory(movement) else { return nil }
            guard movement.occurredAt <= date else { return nil }
            guard calendar.component(.year, from: movement.occurredAt) == year,
                  calendar.component(.month, from: movement.occurredAt) == month else { return nil }
            return calendar.startOfDay(for: movement.occurredAt)
        }

        return Set(days).count
    }

    private static func historicalRemainingSpendAverage(
        for budget: Budget,
        movements: [Movement],
        asOf date: Date,
        calendar: Calendar = .current
    ) -> (average: Decimal, monthsUsed: Int)? {
        let categoryIDs = Set(budget.items.compactMap { $0.category?.id })
        guard !categoryIDs.isEmpty else { return nil }

        let currentDay = calendar.component(.day, from: date)
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let samples = (1...6).compactMap { offset -> Decimal? in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart),
                  let daysRange = calendar.range(of: .day, in: .month, for: monthStart),
                  let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                return nil
            }

            let daysInHistoricalMonth = daysRange.count
            let firstProjectedDay = min(currentDay + 1, daysInHistoricalMonth + 1)
            let firstProjectedDate = calendar.date(
                from: DateComponents(
                    year: calendar.component(.year, from: monthStart),
                    month: calendar.component(.month, from: monthStart),
                    day: min(firstProjectedDay, daysInHistoricalMonth)
                )
            ) ?? monthStart

            var monthHadBudgetSpend = false
            var remainingWindowSpend = Decimal(0)

            for movement in movements {
                guard movement.type == .expense else { continue }
                guard let categoryID = movement.category?.id, categoryIDs.contains(categoryID) else { continue }
                guard movement.occurredAt >= monthStart, movement.occurredAt < nextMonthStart else { continue }

                monthHadBudgetSpend = true
                if firstProjectedDay <= daysInHistoricalMonth, movement.occurredAt >= firstProjectedDate {
                    remainingWindowSpend += movement.statsExpenseAmount
                }
            }

            return monthHadBudgetSpend ? remainingWindowSpend : nil
        }

        guard samples.count >= 2 else { return nil }
        let total = samples.reduce(Decimal(0), +)
        return (total / Decimal(samples.count), samples.count)
    }

    /// Cancela todas las notificaciones de todos los ítems del presupuesto.
    @MainActor
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

struct SpendingForecast: Equatable {
    let monthlyBudget: Decimal
    let spentSoFar: Decimal
    let remainingBudget: Decimal
    let averageDailySpend: Decimal
    let recommendedDailySpend: Decimal?
    let projectedMonthEndSpend: Decimal
    let projectedMargin: Decimal
    let estimatedDepletionDate: Date?
    let status: SpendingForecastStatus
    let reliability: SpendingForecastReliability
    let basis: SpendingForecastBasis
    let historicalMonthsUsed: Int
    let historicalRemainingSpendAverage: Decimal?
    let daysElapsed: Int
    let daysRemaining: Int
    let daysInMonth: Int
    let spendingDays: Int
    let points: [SpendingForecastPoint]
}

struct SpendingForecastPoint: Identifiable, Equatable {
    let day: Int
    let amount: Decimal
    let isProjected: Bool

    var id: String { "\(day)-\(isProjected)" }
}

enum SpendingForecastStatus: Equatable {
    case noBudget
    case noSpending
    case good
    case tight
    case risk
    case exceeded
}

enum SpendingForecastReliability: Equatable {
    case low
    case medium
    case high
}

enum SpendingForecastBasis: Equatable {
    case currentPace
    case historicalAverage
}

enum SpendingForecastCalculator {
    static func makeForecast(
        monthlyBudget: Decimal,
        spentSoFar: Decimal,
        spendingDays: Int,
        historicalRemainingSpendAverage: Decimal? = nil,
        historicalMonthsUsed: Int = 0,
        asOf date: Date = Date(),
        calendar: Calendar = .current
    ) -> SpendingForecast {
        let monthRange = calendar.range(of: .day, in: .month, for: date)
        let daysInMonth = monthRange?.count ?? 30
        let dayOfMonth = calendar.component(.day, from: date)
        let daysElapsed = max(1, min(dayOfMonth, daysInMonth))
        let daysRemaining = max(daysInMonth - daysElapsed, 0)
        let remaining = monthlyBudget - spentSoFar
        let averageDaily = spentSoFar / Decimal(daysElapsed)
        let usesHistoricalData = historicalMonthsUsed >= 2 && historicalRemainingSpendAverage != nil && daysRemaining > 0
        let basis: SpendingForecastBasis = usesHistoricalData ? .historicalAverage : .currentPace
        let projected = usesHistoricalData
            ? spentSoFar + max(historicalRemainingSpendAverage ?? 0, 0)
            : averageDaily * Decimal(daysInMonth)
        let projectedMargin = monthlyBudget - projected
        let recommendedDaily: Decimal? = monthlyBudget > 0 ? max(remaining, 0) / Decimal(max(daysRemaining, 1)) : nil
        let reliability = reliability(
            dayOfMonth: daysElapsed,
            spendingDays: spendingDays,
            basis: basis,
            historicalMonthsUsed: historicalMonthsUsed
        )
        let depletionDate = estimatedDepletionDate(
            monthlyBudget: monthlyBudget,
            spentSoFar: spentSoFar,
            averageDailySpend: basis == .historicalAverage
                ? (max(historicalRemainingSpendAverage ?? 0, 0) / Decimal(max(daysRemaining, 1)))
                : averageDaily,
            asOf: date,
            daysRemaining: daysRemaining,
            calendar: calendar
        )
        let status = status(
            monthlyBudget: monthlyBudget,
            spentSoFar: spentSoFar,
            projectedMonthEndSpend: projected,
            estimatedDepletionDate: depletionDate,
            daysRemaining: daysRemaining
        )

        return SpendingForecast(
            monthlyBudget: monthlyBudget,
            spentSoFar: spentSoFar,
            remainingBudget: remaining,
            averageDailySpend: averageDaily,
            recommendedDailySpend: recommendedDaily,
            projectedMonthEndSpend: projected,
            projectedMargin: projectedMargin,
            estimatedDepletionDate: depletionDate,
            status: status,
            reliability: reliability,
            basis: basis,
            historicalMonthsUsed: basis == .historicalAverage ? historicalMonthsUsed : 0,
            historicalRemainingSpendAverage: basis == .historicalAverage ? historicalRemainingSpendAverage : nil,
            daysElapsed: daysElapsed,
            daysRemaining: daysRemaining,
            daysInMonth: daysInMonth,
            spendingDays: spendingDays,
            points: [
                SpendingForecastPoint(day: 1, amount: 0, isProjected: false),
                SpendingForecastPoint(day: daysElapsed, amount: spentSoFar, isProjected: false),
                SpendingForecastPoint(day: daysInMonth, amount: projected, isProjected: true)
            ]
        )
    }

    private static func reliability(dayOfMonth: Int, spendingDays: Int) -> SpendingForecastReliability {
        reliability(dayOfMonth: dayOfMonth, spendingDays: spendingDays, basis: .currentPace, historicalMonthsUsed: 0)
    }

    private static func reliability(
        dayOfMonth: Int,
        spendingDays: Int,
        basis: SpendingForecastBasis,
        historicalMonthsUsed: Int
    ) -> SpendingForecastReliability {
        if basis == .historicalAverage {
            return historicalMonthsUsed >= 4 ? .high : .medium
        }
        if dayOfMonth <= 5 || spendingDays < 3 { return .low }
        if dayOfMonth <= 10 || spendingDays < 5 { return .medium }
        return .high
    }

    private static func status(
        monthlyBudget: Decimal,
        spentSoFar: Decimal,
        projectedMonthEndSpend: Decimal,
        estimatedDepletionDate: Date?,
        daysRemaining: Int
    ) -> SpendingForecastStatus {
        guard monthlyBudget > 0 else { return .noBudget }
        guard spentSoFar > 0 || projectedMonthEndSpend > 0 else { return .noSpending }
        if spentSoFar > monthlyBudget { return .exceeded }
        if estimatedDepletionDate != nil && daysRemaining > 0 { return .risk }

        let usage = projectedMonthEndSpend / monthlyBudget
        if usage >= Decimal(string: "0.98")! { return .tight }
        if usage >= Decimal(string: "0.90")! { return .tight }
        return .good
    }

    private static func estimatedDepletionDate(
        monthlyBudget: Decimal,
        spentSoFar: Decimal,
        averageDailySpend: Decimal,
        asOf date: Date,
        daysRemaining: Int,
        calendar: Calendar
    ) -> Date? {
        guard monthlyBudget > 0, spentSoFar <= monthlyBudget, averageDailySpend > 0 else { return nil }
        let daysUntilDepletion = ((monthlyBudget - spentSoFar) / averageDailySpend).roundedUpInt()
        guard daysUntilDepletion <= daysRemaining else { return nil }
        return calendar.date(byAdding: .day, value: max(daysUntilDepletion, 0), to: date)
    }
}

private extension Decimal {
    func roundedUpInt() -> Int {
        NSDecimalNumber(decimal: self).doubleValue.rounded(.up).isFinite
            ? Int(NSDecimalNumber(decimal: self).doubleValue.rounded(.up))
            : 0
    }
}
