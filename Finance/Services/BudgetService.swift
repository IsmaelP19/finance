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

    private struct HistoricalWindow {
        let monthStart: Date
        let nextMonthStart: Date
        let firstProjectedDay: Int
        let firstProjectedDate: Date
        let daysInMonth: Int
    }

    private struct HistoricalMonthAggregate {
        var hadBudgetSpend = false
        var remainingWindowSpend = Decimal.zero
    }

    private struct SpendingAggregates {
        var spentByCategory: [UUID: Decimal] = [:]
        var spendingDaysByCategory: [UUID: Set<Date>] = [:]
        var historicalByMonth: [Date: HistoricalMonthAggregate] = [:]
    }

    // MARK: - Spending calculations

    static func forecast(for budget: Budget, movements: [Movement], asOf date: Date = Date()) -> SpendingForecast {
        let categoryIDs = Set(budget.items.compactMap { $0.category?.id })
        let aggregates = spendingAggregates(
            for: categoryIDs,
            movements: movements,
            asOf: date,
            includeHistorical: true
        )
        let spent = totalSpent(for: budget, aggregates: aggregates)
        let spendingDays = spendingDayCount(for: categoryIDs, aggregates: aggregates)
        let historicalSample = historicalRemainingSpendAverage(
            from: aggregates,
            asOf: date
        )

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
        let aggregates = spendingAggregates(
            for: Set([category.id]),
            movements: movements,
            asOf: date
        )
        let spent = aggregates.spentByCategory[category.id, default: 0]
        let spendingDays = spendingDayCount(for: Set([category.id]), aggregates: aggregates)

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
        let aggregates = spendingAggregates(
            for: Set([category.id]),
            movements: movements,
            asOf: date
        )
        return aggregates.spentByCategory[category.id, default: 0]
    }

    /// Gasto real del mes en todas las categorías del presupuesto.
    static func totalSpent(for budget: Budget, movements: [Movement], asOf date: Date = Date()) -> Decimal {
        let categoryIDs = Set(budget.items.compactMap { $0.category?.id })
        let aggregates = spendingAggregates(
            for: categoryIDs,
            movements: movements,
            asOf: date
        )
        return totalSpent(for: budget, aggregates: aggregates)
    }

    private static func totalSpent(for budget: Budget, aggregates: SpendingAggregates) -> Decimal {
        budget.items.reduce(Decimal(0)) { total, item in
            guard let categoryID = item.category?.id else { return total }
            return total + aggregates.spentByCategory[categoryID, default: 0]
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
        let categoryIDs = Set(budget.items.compactMap { $0.category?.id })
        let aggregates = spendingAggregates(
            for: categoryIDs,
            movements: movements,
            asOf: Date()
        )
        let actions = budget.items.compactMap {
            notificationAction(for: $0, budget: budget, aggregates: aggregates)
        }

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
        aggregates: SpendingAggregates
    ) -> BudgetNotificationAction? {
        guard let category = item.category else { return nil }
        let spent = aggregates.spentByCategory[category.id, default: 0]
        let progress = item.allocatedAmount > 0
            ? spent / item.allocatedAmount
            : Decimal.zero

        return BudgetNotificationAction(
            id80: "\(itemNotificationPrefix)\(item.id.uuidString)-80",
            id100: "\(itemNotificationPrefix)\(item.id.uuidString)-100",
            categoryName: category.name,
            notifyAt80Percent: budget.notifyAt80Percent,
            notifyAt100Percent: budget.notifyAt100Percent,
            progress: progress
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

    private static func spendingAggregates(
        for categoryIDs: Set<UUID>,
        movements: [Movement],
        asOf date: Date,
        includeHistorical: Bool = false,
        calendar: Calendar = .current
    ) -> SpendingAggregates {
        guard !categoryIDs.isEmpty else { return SpendingAggregates() }

        let currentYear = calendar.component(.year, from: date)
        let currentMonth = calendar.component(.month, from: date)
        let historicalWindows = includeHistorical
            ? makeHistoricalWindows(asOf: date, calendar: calendar)
            : []
        let historicalWindowsByStart = Dictionary(
            uniqueKeysWithValues: historicalWindows.map { ($0.monthStart, $0) }
        )
        var aggregates = SpendingAggregates()
        for window in historicalWindows {
            aggregates.historicalByMonth[window.monthStart] = HistoricalMonthAggregate()
        }

        for movement in movements {
            guard movement.type == .expense,
                  let categoryID = movement.category?.id,
                  categoryIDs.contains(categoryID) else {
                continue
            }

            if movement.occurredAt <= date,
               calendar.component(.year, from: movement.occurredAt) == currentYear,
               calendar.component(.month, from: movement.occurredAt) == currentMonth {
                aggregates.spentByCategory[categoryID, default: 0] += movement.statsExpenseAmount
                aggregates.spendingDaysByCategory[categoryID, default: []].insert(
                    calendar.startOfDay(for: movement.occurredAt)
                )
            }

            guard includeHistorical,
                  let movementMonthStart = calendar.date(
                      from: calendar.dateComponents([.year, .month], from: movement.occurredAt)
                  ),
                  var monthAggregate = aggregates.historicalByMonth[movementMonthStart],
                  let window = historicalWindowsByStart[movementMonthStart],
                  movement.occurredAt >= window.monthStart,
                  movement.occurredAt < window.nextMonthStart else {
                continue
            }

            monthAggregate.hadBudgetSpend = true
            if window.firstProjectedDay <= window.daysInMonth,
               movement.occurredAt >= window.firstProjectedDate {
                monthAggregate.remainingWindowSpend += movement.statsExpenseAmount
            }
            aggregates.historicalByMonth[movementMonthStart] = monthAggregate
        }

        return aggregates
    }

    private static func spendingDayCount(
        for categoryIDs: Set<UUID>,
        aggregates: SpendingAggregates
    ) -> Int {
        var days = Set<Date>()
        for categoryID in categoryIDs {
            days.formUnion(aggregates.spendingDaysByCategory[categoryID] ?? [])
        }
        return days.count
    }

    private static func makeHistoricalWindows(
        asOf date: Date,
        calendar: Calendar
    ) -> [HistoricalWindow] {
        let currentDay = calendar.component(.day, from: date)
        let currentMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? date

        return (1...6).compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonthStart),
                  let daysRange = calendar.range(of: .day, in: .month, for: monthStart),
                  let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: monthStart) else {
                return nil
            }

            let daysInMonth = daysRange.count
            let firstProjectedDay = min(currentDay + 1, daysInMonth + 1)
            let firstProjectedDate = calendar.date(
                from: DateComponents(
                    year: calendar.component(.year, from: monthStart),
                    month: calendar.component(.month, from: monthStart),
                    day: min(firstProjectedDay, daysInMonth)
                )
            ) ?? monthStart

            return HistoricalWindow(
                monthStart: monthStart,
                nextMonthStart: nextMonthStart,
                firstProjectedDay: firstProjectedDay,
                firstProjectedDate: firstProjectedDate,
                daysInMonth: daysInMonth
            )
        }
    }

    private static func historicalRemainingSpendAverage(
        from aggregates: SpendingAggregates,
        asOf date: Date,
        calendar: Calendar = .current
    ) -> (average: Decimal, monthsUsed: Int)? {
        let samples = makeHistoricalWindows(asOf: date, calendar: calendar).compactMap { window -> Decimal? in
            guard let monthAggregate = aggregates.historicalByMonth[window.monthStart],
                  monthAggregate.hadBudgetSpend else {
                return nil
            }
            return monthAggregate.remainingWindowSpend
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
