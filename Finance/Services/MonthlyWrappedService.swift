//
//  MonthlyWrappedService.swift
//  Finance
//
//  Created by OpenCode on 03/03/2026.
//

import Foundation
import SwiftUI
import UserNotifications
import SwiftData

struct WrappedMonth: Hashable, Identifiable {
    let year: Int
    let month: Int

    var id: String { key }

    var key: String {
        String(format: "%04d-%02d", year, month)
    }

    var monthStart: Date {
        let components = DateComponents(year: year, month: month, day: 1)
        return Calendar.current.date(from: components) ?? Date()
    }

    var shortLabel: String {
        WrappedMonthFormatter.short.string(from: monthStart)
    }

    var longLabel: String {
        WrappedMonthFormatter.long.string(from: monthStart)
    }

    var previousMonth: WrappedMonth {
        let calendar = Calendar.current
        let previousDate = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        return WrappedMonth(
            year: calendar.component(.year, from: previousDate),
            month: calendar.component(.month, from: previousDate)
        )
    }
}

struct WrappedCategoryStat: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let color: Color
    let amount: Decimal
    let movementCount: Int
}

struct WrappedDayStat: Identifiable {
    let date: Date
    let totalExpense: Decimal
    let movementCount: Int

    var id: Date { date }
}

struct WrappedMovementHighlight: Identifiable {
    let id: UUID
    let concept: String
    let amount: Decimal
    let date: Date
    let categoryName: String
    let categoryIconName: String
}

struct WrappedWeekdayStat: Identifiable {
    let weekday: Int
    let weekdayName: String
    let movementCount: Int

    var id: Int { weekday }
}

struct WrappedCategorySavingsStat: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let color: Color
    let currentExpense: Decimal
    let historicalAverageExpense: Decimal
    let savingsDelta: Decimal
    let comparedMonths: Int
}

struct WrappedDailyExpenseAverage {
    let averageExpense: Decimal
    let dayCount: Int
}

struct WrappedWeekBalanceStat: Identifiable {
    let id: String
    let weekOfMonth: Int
    let startDate: Date
    let endDate: Date
    let incomeTotal: Decimal
    let expenseTotal: Decimal
    let movementCount: Int

    var netBalance: Decimal {
        incomeTotal - expenseTotal
    }
}

struct WrappedComparison {
    let previousMonth: WrappedMonth
    let previousIncomeTotal: Decimal
    let previousExpenseTotal: Decimal
    let previousNetBalance: Decimal
    let previousSavingsRate: Decimal?
    let incomeDelta: Decimal
    let expenseDelta: Decimal
    let netDelta: Decimal
    let savingsRateDelta: Decimal?
}

struct WrappedSharedExpenseHighlight: Identifiable {
    let id: UUID
    let concept: String
    let expectedReimbursement: Decimal
    let date: Date
    let categoryIconName: String
}

struct WrappedSharedExpenseSummary {
    let movementCount: Int
    let totalExpected: Decimal
    let totalRecovered: Decimal
    let totalPending: Decimal
    let recoveryRate: Decimal?
    let topSharedExpense: WrappedSharedExpenseHighlight
}

struct WrappedReimbursementCompletionHighlight: Identifiable {
    let id: UUID
    let concept: String
    let expectedReimbursement: Decimal
    let completionDate: Date
    let expenseDate: Date
    let daysToComplete: Int
}

struct WrappedSummary {
    let month: WrappedMonth
    let movementCount: Int
    let incomeTotal: Decimal
    let expenseTotal: Decimal
    let netBalance: Decimal
    let savingsRate: Decimal?
    let topExpenseCategories: [WrappedCategoryStat]
    let highestExpenseDay: WrappedDayStat?
    let mostExpensiveMovement: WrappedMovementHighlight?
    let savingsStreakMonths: Int
    let mostActiveWeekday: WrappedWeekdayStat?
    let bestSavingsCategory: WrappedCategorySavingsStat?
    let averageDailyExpense: WrappedDailyExpenseAverage
    let bestWeek: WrappedWeekBalanceStat?
    let comparison: WrappedComparison?
    let sharedExpenseSummary: WrappedSharedExpenseSummary?
    let slowestReimbursementCompletion: WrappedReimbursementCompletionHighlight?
}

private enum WrappedMonthFormatter {
    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    static let long: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "MMMM 'de' yyyy"
        return formatter
    }()
}

private enum WrappedWeekdayFormatter {
    static let symbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.weekdaySymbols
    }()
}

private struct WrappedPeriodTotals {
    var income: Decimal = 0
    var expense: Decimal = 0
    var movementCount: Int = 0

    var net: Decimal {
        income - expense
    }

    var savingsRate: Decimal? {
        guard income > 0 else { return nil }
        return (net / income) * 100
    }
}

private struct WrappedCategoryDescriptor {
    let id: String
    let name: String
    let iconName: String
    let color: Color
}

private struct WrappedCategoryTotal {
    let descriptor: WrappedCategoryDescriptor
    let amount: Decimal
    let movementCount: Int
}

private struct WrappedWeekAccumulator {
    let startDate: Date
    let endDate: Date
    var income: Decimal = 0
    var expense: Decimal = 0
    var movementCount: Int = 0

    var netBalance: Decimal {
        income - expense
    }
}

enum MonthlyWrappedService {
    private static let lastViewedMonthKey = "monthlyWrappedLastViewedMonth"
    private static let reminderIdentifier = "monthlyWrappedReminder"

    @MainActor
    static func configureMonthlyReminder() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                scheduleMonthlyReminder()
            case .notDetermined:
                guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
                scheduleMonthlyReminder()
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    static func closedMonths(from movements: [Movement], now: Date = Date()) -> [WrappedMonth] {
        let calendar = Calendar.current
        let currentMonthStart = startOfMonth(for: now)

        let uniqueMonths = Set(
            movements
                .filter { $0.occurredAt < currentMonthStart }
                .map { movement in
                    WrappedMonth(
                        year: calendar.component(.year, from: movement.occurredAt),
                        month: calendar.component(.month, from: movement.occurredAt)
                    )
                }
        )

        return uniqueMonths.sorted { lhs, rhs in
            if lhs.year == rhs.year {
                return lhs.month > rhs.month
            }

            return lhs.year > rhs.year
        }
    }

    static func latestClosedMonth(from movements: [Movement], now: Date = Date()) -> WrappedMonth? {
        closedMonths(from: movements, now: now).first
    }

    static func hasSeen(month: WrappedMonth) -> Bool {
        UserDefaults.standard.string(forKey: lastViewedMonthKey) == month.key
    }

    static func markSeen(month: WrappedMonth) {
        UserDefaults.standard.set(month.key, forKey: lastViewedMonthKey)
    }

    static func summary(for month: WrappedMonth, movements: [Movement]) -> WrappedSummary {
        let currentInterval = interval(for: month)
        let currentMovements = movements.filter { currentInterval.contains($0.occurredAt) }
        let currentTotals = periodTotals(for: currentMovements)
        let reimbursementsByExpenseID = reimbursementIncomesByExpenseID(from: movements)

        let currentExpenseMovements = currentMovements.filter { $0.type == .expense }

        let previousMonth = month.previousMonth
        let previousInterval = interval(for: previousMonth)
        let previousMovements = movements.filter { previousInterval.contains($0.occurredAt) }
        let previousTotals = periodTotals(for: previousMovements)

        let comparison: WrappedComparison?
        if previousMovements.isEmpty {
            comparison = nil
        } else {
            comparison = WrappedComparison(
                previousMonth: previousMonth,
                previousIncomeTotal: previousTotals.income,
                previousExpenseTotal: previousTotals.expense,
                previousNetBalance: previousTotals.net,
                previousSavingsRate: previousTotals.savingsRate,
                incomeDelta: currentTotals.income - previousTotals.income,
                expenseDelta: currentTotals.expense - previousTotals.expense,
                netDelta: currentTotals.net - previousTotals.net,
                savingsRateDelta: savingsRateDelta(current: currentTotals.savingsRate, previous: previousTotals.savingsRate)
            )
        }

        let sharedSummary = sharedExpenseSummary(
            for: month,
            currentMovements: currentMovements,
            reimbursementsByExpenseID: reimbursementsByExpenseID
        )
        let slowestCompletion = slowestReimbursementCompletion(
            for: month,
            movements: movements,
            reimbursementsByExpenseID: reimbursementsByExpenseID
        )

        return WrappedSummary(
            month: month,
            movementCount: currentTotals.movementCount,
            incomeTotal: currentTotals.income,
            expenseTotal: currentTotals.expense,
            netBalance: currentTotals.net,
            savingsRate: currentTotals.savingsRate,
            topExpenseCategories: topExpenseCategories(from: currentExpenseMovements, limit: 5),
            highestExpenseDay: highestExpenseDay(from: currentExpenseMovements),
            mostExpensiveMovement: mostExpensiveMovement(from: currentExpenseMovements),
            savingsStreakMonths: savingsStreakMonths(for: month, movements: movements),
            mostActiveWeekday: mostActiveWeekday(from: currentMovements),
            bestSavingsCategory: bestSavingsCategory(for: month, currentExpenseMovements: currentExpenseMovements, allMovements: movements),
            averageDailyExpense: averageDailyExpense(for: month, expenseTotal: currentTotals.expense),
            bestWeek: bestWeek(for: month, movements: currentMovements),
            comparison: comparison,
            sharedExpenseSummary: sharedSummary,
            slowestReimbursementCompletion: slowestCompletion
        )
    }

    @MainActor
    private static func scheduleMonthlyReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])

        var components = DateComponents()
        components.day = 1
        components.hour = 9
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Tu Wrapped mensual ya está listo"
        content.body = "Revisa tu balance, tus mayores gastos y la comparativa con el mes anterior."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    private static func periodTotals(for movements: [Movement]) -> WrappedPeriodTotals {
        var totals = WrappedPeriodTotals()

        for movement in movements {
            totals.movementCount += 1

            switch movement.type {
            case .income:
                totals.income += movement.statsIncomeAmount
            case .expense:
                totals.expense += movement.statsExpenseAmount
            case .transfer:
                continue
            }
        }

        return totals
    }

    private static func topExpenseCategories(from movements: [Movement], limit: Int) -> [WrappedCategoryStat] {
        categoryTotals(from: movements)
            .sorted { lhs, rhs in
                lhs.amount > rhs.amount
            }
            .prefix(limit)
            .map { categoryTotal in
                WrappedCategoryStat(
                    id: categoryTotal.descriptor.id,
                    name: categoryTotal.descriptor.name,
                    iconName: categoryTotal.descriptor.iconName,
                    color: categoryTotal.descriptor.color,
                    amount: categoryTotal.amount,
                    movementCount: categoryTotal.movementCount
                )
            }
    }

    private static func highestExpenseDay(from movements: [Movement]) -> WrappedDayStat? {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: movements) { movement in
            calendar.startOfDay(for: movement.occurredAt)
        }

        return grouped
            .compactMap { day, groupedMovements -> WrappedDayStat? in
                let total = groupedMovements.reduce(Decimal(0)) { partial, movement in
                    partial + movement.statsExpenseAmount
                }

                guard total > 0 else { return nil }

                return WrappedDayStat(
                    date: day,
                    totalExpense: total,
                    movementCount: groupedMovements.count
                )
            }
            .max { lhs, rhs in
                lhs.totalExpense < rhs.totalExpense
            }
    }

    private static func mostExpensiveMovement(from movements: [Movement]) -> WrappedMovementHighlight? {
        guard let movement = movements.max(by: { lhs, rhs in
            lhs.statsExpenseAmount < rhs.statsExpenseAmount
        }) else {
            return nil
        }

        return WrappedMovementHighlight(
            id: movement.id,
            concept: movement.concept,
            amount: movement.statsExpenseAmount,
            date: movement.occurredAt,
            categoryName: movement.category?.name ?? "Sin categoría",
            categoryIconName: movement.category?.iconName ?? "tag"
        )
    }

    private static func savingsStreakMonths(for month: WrappedMonth, movements: [Movement]) -> Int {
        let totalsByMonth = monthTotals(from: movements)
        var streak = 0
        var cursor = month

        while let totals = totalsByMonth[cursor], totals.net > 0 {
            streak += 1
            cursor = cursor.previousMonth
        }

        return streak
    }

    private static func mostActiveWeekday(from movements: [Movement]) -> WrappedWeekdayStat? {
        guard !movements.isEmpty else { return nil }

        let calendar = Calendar.current
        let firstWeekday = calendar.firstWeekday
        let grouped = Dictionary(grouping: movements) { movement in
            calendar.component(.weekday, from: movement.occurredAt)
        }

        guard let best = grouped.max(by: { lhs, rhs in
            if lhs.value.count == rhs.value.count {
                return weekdaySortKey(lhs.key, firstWeekday: firstWeekday) > weekdaySortKey(rhs.key, firstWeekday: firstWeekday)
            }
            return lhs.value.count < rhs.value.count
        }) else {
            return nil
        }

        return WrappedWeekdayStat(
            weekday: best.key,
            weekdayName: weekdayName(for: best.key),
            movementCount: best.value.count
        )
    }

    private static func bestSavingsCategory(
        for month: WrappedMonth,
        currentExpenseMovements: [Movement],
        allMovements: [Movement]
    ) -> WrappedCategorySavingsStat? {
        let calendar = Calendar.current
        let lookbackMonths = 6
        let currentInterval = interval(for: month)

        guard let historyStart = calendar.date(byAdding: .month, value: -lookbackMonths, to: currentInterval.start) else {
            return nil
        }

        let historyInterval = DateInterval(start: historyStart, end: currentInterval.start)
        let historicalMovements = allMovements.filter { movement in
            historyInterval.contains(movement.occurredAt) && movement.type == .expense
        }

        guard !historicalMovements.isEmpty else { return nil }

        let historicalMonths = Set(
            allMovements
                .filter { historyInterval.contains($0.occurredAt) }
                .map { startOfMonth(for: $0.occurredAt) }
        )
        let comparedMonths = max(1, min(lookbackMonths, historicalMonths.count))

        let historicalTotals = categoryTotals(from: historicalMovements)
        let currentTotalsByCategory = Dictionary(uniqueKeysWithValues: categoryTotals(from: currentExpenseMovements).map { total in
            (total.descriptor.id, total)
        })

        return historicalTotals
            .map { historical in
                let currentAmount = currentTotalsByCategory[historical.descriptor.id]?.amount ?? 0
                let average = historical.amount / Decimal(comparedMonths)
                return WrappedCategorySavingsStat(
                    id: historical.descriptor.id,
                    name: historical.descriptor.name,
                    iconName: historical.descriptor.iconName,
                    color: historical.descriptor.color,
                    currentExpense: currentAmount,
                    historicalAverageExpense: average,
                    savingsDelta: average - currentAmount,
                    comparedMonths: comparedMonths
                )
            }
            .sorted { lhs, rhs in
                if lhs.savingsDelta == rhs.savingsDelta {
                    return lhs.historicalAverageExpense > rhs.historicalAverageExpense
                }
                return lhs.savingsDelta > rhs.savingsDelta
            }
            .first
    }

    private static func averageDailyExpense(for month: WrappedMonth, expenseTotal: Decimal) -> WrappedDailyExpenseAverage {
        let dayCount = Calendar.current.range(of: .day, in: .month, for: month.monthStart)?.count ?? 30
        let average = dayCount > 0 ? (expenseTotal / Decimal(dayCount)) : 0

        return WrappedDailyExpenseAverage(
            averageExpense: average,
            dayCount: dayCount
        )
    }

    private static func bestWeek(for month: WrappedMonth, movements: [Movement]) -> WrappedWeekBalanceStat? {
        let calendar = Calendar.current
        let monthInterval = interval(for: month)
        var buckets: [Date: WrappedWeekAccumulator] = [:]

        for movement in movements {
            guard let weekInterval = calendar.dateInterval(of: .weekOfMonth, for: movement.occurredAt) else { continue }

            let clampedStart = weekInterval.start < monthInterval.start ? monthInterval.start : weekInterval.start
            let clampedEnd = weekInterval.end > monthInterval.end ? monthInterval.end : weekInterval.end
            let bucketKey = clampedStart

            var bucket = buckets[bucketKey] ?? WrappedWeekAccumulator(
                startDate: clampedStart,
                endDate: clampedEnd
            )

            bucket.movementCount += 1

            switch movement.type {
            case .income:
                bucket.income += movement.statsIncomeAmount
            case .expense:
                bucket.expense += movement.statsExpenseAmount
            case .transfer:
                break
            }

            buckets[bucketKey] = bucket
        }

        guard let bestBucket = buckets.values
            .filter({ $0.expense > 0 })
            .min(by: { lhs, rhs in
                if lhs.expense == rhs.expense {
                    if lhs.movementCount == rhs.movementCount {
                        return lhs.startDate < rhs.startDate
                    }
                    return lhs.movementCount < rhs.movementCount
                }
                return lhs.expense < rhs.expense
            }) else {
            return nil
        }

        let weekIndex = weekIndexInMonth(for: bestBucket.startDate, month: month, calendar: calendar)

        return WrappedWeekBalanceStat(
            id: "\(month.key)-week-\(weekIndex)",
            weekOfMonth: weekIndex,
            startDate: bestBucket.startDate,
            endDate: bestBucket.endDate,
            incomeTotal: bestBucket.income,
            expenseTotal: bestBucket.expense,
            movementCount: bestBucket.movementCount
        )
    }

    private static func sharedExpenseSummary(
        for month: WrappedMonth,
        currentMovements: [Movement],
        reimbursementsByExpenseID: [UUID: [Movement]]
    ) -> WrappedSharedExpenseSummary? {
        let monthInterval = interval(for: month)
        let sharedExpenses = currentMovements
            .filter { $0.type == .expense && $0.isSharedExpense }
            .filter { $0.expectedReimbursementAmount > 0 }

        guard let topExpense = sharedExpenses.max(by: { lhs, rhs in
            if lhs.expectedReimbursementAmount == rhs.expectedReimbursementAmount {
                return lhs.occurredAt < rhs.occurredAt
            }
            return lhs.expectedReimbursementAmount < rhs.expectedReimbursementAmount
        }) else {
            return nil
        }

        var totalExpected: Decimal = 0
        var totalRecovered: Decimal = 0
        var totalPending: Decimal = 0

        for expense in sharedExpenses {
            let reimbursements = reimbursementsByExpenseID[expense.id] ?? []
            let recoveredUntilMonthEnd = reimbursements
                .filter { $0.occurredAt < monthInterval.end }
                .reduce(Decimal(0)) { partial, reimbursement in
                    partial + max(reimbursement.amount, 0)
                }
            let expected = expense.expectedReimbursementAmount
            let recoveredApplied = min(recoveredUntilMonthEnd, expected)
            let pending = max(expected - recoveredApplied, 0)

            totalExpected += expected
            totalRecovered += recoveredApplied
            totalPending += pending
        }

        let recoveryRate: Decimal?
        if totalExpected > 0 {
            recoveryRate = (totalRecovered / totalExpected) * 100
        } else {
            recoveryRate = nil
        }

        return WrappedSharedExpenseSummary(
            movementCount: sharedExpenses.count,
            totalExpected: totalExpected,
            totalRecovered: totalRecovered,
            totalPending: totalPending,
            recoveryRate: recoveryRate,
            topSharedExpense: WrappedSharedExpenseHighlight(
                id: topExpense.id,
                concept: topExpense.concept,
                expectedReimbursement: topExpense.expectedReimbursementAmount,
                date: topExpense.occurredAt,
                categoryIconName: topExpense.category?.iconName ?? "person.2.fill"
            )
        )
    }

    private static func slowestReimbursementCompletion(
        for month: WrappedMonth,
        movements: [Movement],
        reimbursementsByExpenseID: [UUID: [Movement]]
    ) -> WrappedReimbursementCompletionHighlight? {
        let monthInterval = interval(for: month)
        let sharedExpenses = movements
            .filter { $0.type == .expense && $0.isSharedExpense }
            .filter { $0.expectedReimbursementAmount > 0 }

        var completions: [WrappedReimbursementCompletionHighlight] = []

        for expense in sharedExpenses {
            let reimbursements = reimbursementsByExpenseID[expense.id] ?? []
            guard let completionDate = completionDate(for: expense, reimbursements: reimbursements) else {
                continue
            }
            guard monthInterval.contains(completionDate) else {
                continue
            }

            completions.append(
                WrappedReimbursementCompletionHighlight(
                    id: expense.id,
                    concept: expense.concept,
                    expectedReimbursement: expense.expectedReimbursementAmount,
                    completionDate: completionDate,
                    expenseDate: expense.occurredAt,
                    daysToComplete: daysBetween(start: expense.occurredAt, end: completionDate)
                )
            )
        }

        return completions.max(by: { lhs, rhs in
            if lhs.daysToComplete == rhs.daysToComplete {
                return lhs.expectedReimbursement < rhs.expectedReimbursement
            }
            return lhs.daysToComplete < rhs.daysToComplete
        })
    }

    private static func weekIndexInMonth(for weekStartDate: Date, month: WrappedMonth, calendar: Calendar) -> Int {
        let monthStart = month.monthStart
        let anchorWeekStart = calendar.dateInterval(of: .weekOfMonth, for: monthStart)?.start ?? monthStart
        let weekDistance = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: weekStartDate).weekOfYear ?? 0
        return max(1, weekDistance + 1)
    }

    private static func categoryTotals(from movements: [Movement]) -> [WrappedCategoryTotal] {
        var grouped: [String: (descriptor: WrappedCategoryDescriptor, amount: Decimal, movementCount: Int)] = [:]

        for movement in movements {
            let descriptor = categoryDescriptor(for: movement)
            let previous = grouped[descriptor.id] ?? (descriptor, 0, 0)
            grouped[descriptor.id] = (
                descriptor,
                previous.amount + movement.statsExpenseAmount,
                previous.movementCount + 1
            )
        }

        return grouped.values.map { value in
            WrappedCategoryTotal(
                descriptor: value.descriptor,
                amount: value.amount,
                movementCount: value.movementCount
            )
        }
    }

    private static func reimbursementIncomesByExpenseID(from movements: [Movement]) -> [UUID: [Movement]] {
        var grouped: [UUID: [Movement]] = [:]

        for movement in movements where movement.type == .income {
            guard let expenseID = movement.reimbursementForId else { continue }
            grouped[expenseID, default: []].append(movement)
        }

        for expenseID in grouped.keys {
            grouped[expenseID]?.sort { lhs, rhs in
                lhs.occurredAt < rhs.occurredAt
            }
        }

        return grouped
    }

    private static func completionDate(for expense: Movement, reimbursements: [Movement]) -> Date? {
        let expected = expense.expectedReimbursementAmount
        guard expected > 0 else { return nil }

        var recovered: Decimal = 0
        for reimbursement in reimbursements {
            recovered += max(reimbursement.amount, 0)
            if recovered >= expected {
                return reimbursement.occurredAt
            }
        }

        return nil
    }

    private static func daysBetween(start: Date, end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return max(calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0, 0)
    }

    private static func categoryDescriptor(for movement: Movement) -> WrappedCategoryDescriptor {
        WrappedCategoryDescriptor(
            id: movement.category?.id.uuidString ?? "no-category",
            name: movement.category?.name ?? "Sin categoría",
            iconName: movement.category?.iconName ?? "tag",
            color: movement.category?.color ?? .gray
        )
    }

    private static func monthTotals(from movements: [Movement]) -> [WrappedMonth: WrappedPeriodTotals] {
        var totalsByMonth: [WrappedMonth: WrappedPeriodTotals] = [:]
        let calendar = Calendar.current

        for movement in movements {
            let month = WrappedMonth(
                year: calendar.component(.year, from: movement.occurredAt),
                month: calendar.component(.month, from: movement.occurredAt)
            )

            var totals = totalsByMonth[month] ?? WrappedPeriodTotals()
            totals.movementCount += 1

            switch movement.type {
            case .income:
                totals.income += movement.statsIncomeAmount
            case .expense:
                totals.expense += movement.statsExpenseAmount
            case .transfer:
                break
            }

            totalsByMonth[month] = totals
        }

        return totalsByMonth
    }

    private static func weekdayName(for weekday: Int) -> String {
        let symbols = WrappedWeekdayFormatter.symbols
        guard symbols.indices.contains(weekday - 1) else {
            return "Día \(weekday)"
        }

        return symbols[weekday - 1]
    }

    private static func weekdaySortKey(_ weekday: Int, firstWeekday: Int) -> Int {
        (weekday - firstWeekday + 7) % 7
    }

    private static func savingsRateDelta(current: Decimal?, previous: Decimal?) -> Decimal? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    private static func startOfMonth(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func interval(for month: WrappedMonth) -> DateInterval {
        let start = month.monthStart
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}
