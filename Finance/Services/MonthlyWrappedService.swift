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

nonisolated struct WrappedMonth: Hashable, Identifiable, Sendable {
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

private nonisolated enum WrappedMonthFormatter {
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

private nonisolated enum WrappedWeekdayFormatter {
    static let symbols: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        return formatter.weekdaySymbols
    }()
}

private nonisolated struct WrappedPeriodTotals: Sendable {
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

private nonisolated struct WrappedCategoryDescriptor: Sendable {
    let id: String
    let name: String
    let iconName: String
    let colorRaw: String
}

private nonisolated struct WrappedCategoryTotal: Sendable {
    let descriptor: WrappedCategoryDescriptor
    let amount: Decimal
    let movementCount: Int
}

private nonisolated struct WrappedWeekAccumulator {
    let startDate: Date
    let endDate: Date
    var income: Decimal = 0
    var expense: Decimal = 0
    var movementCount: Int = 0

    var netBalance: Decimal {
        income - expense
    }
}

nonisolated struct WrappedMovementValue: Sendable, Equatable {
    let id: UUID
    let concept: String
    let amount: Decimal
    let typeRaw: String
    let occurredAt: Date
    let updatedAt: Date
    let personalAmount: Decimal?
    let reimbursementForId: UUID?
    let categoryID: UUID?
    let categoryName: String?
    let categoryIconRaw: String?
    let categoryColorRaw: String?

    var isExpense: Bool { typeRaw != MovementType.income.rawValue && typeRaw != MovementType.transfer.rawValue }
    var isIncome: Bool { typeRaw == MovementType.income.rawValue }

    var normalizedPersonalAmount: Decimal? {
        guard isExpense, let personalAmount else { return nil }
        if personalAmount < 0 { return 0 }
        if personalAmount > amount { return amount }
        return personalAmount
    }

    var isSharedExpense: Bool {
        guard let normalizedPersonalAmount else { return false }
        return normalizedPersonalAmount < amount
    }

    var statsExpenseAmount: Decimal {
        guard isExpense else { return 0 }
        return normalizedPersonalAmount ?? amount
    }

    var statsIncomeAmount: Decimal {
        guard isIncome, reimbursementForId == nil else { return 0 }
        return amount
    }

    var expectedReimbursementAmount: Decimal {
        guard isExpense else { return 0 }
        return max(amount - statsExpenseAmount, 0)
    }
}

nonisolated struct WrappedCategoryStatValue: Sendable {
    let id: String
    let name: String
    let iconName: String
    let colorRaw: String
    let amount: Decimal
    let movementCount: Int
}

nonisolated struct WrappedDayStatValue: Sendable {
    let date: Date
    let totalExpense: Decimal
    let movementCount: Int
}

nonisolated struct WrappedMovementHighlightValue: Sendable {
    let id: UUID
    let concept: String
    let amount: Decimal
    let date: Date
    let categoryName: String
    let categoryIconName: String
}

nonisolated struct WrappedWeekdayStatValue: Sendable {
    let weekday: Int
    let weekdayName: String
    let movementCount: Int
}

nonisolated struct WrappedCategorySavingsStatValue: Sendable {
    let id: String
    let name: String
    let iconName: String
    let colorRaw: String
    let currentExpense: Decimal
    let historicalAverageExpense: Decimal
    let savingsDelta: Decimal
    let comparedMonths: Int
}

nonisolated struct WrappedDailyExpenseAverageValue: Sendable {
    let averageExpense: Decimal
    let dayCount: Int
}

nonisolated struct WrappedWeekBalanceStatValue: Sendable {
    let id: String
    let weekOfMonth: Int
    let startDate: Date
    let endDate: Date
    let incomeTotal: Decimal
    let expenseTotal: Decimal
    let movementCount: Int
}

nonisolated struct WrappedComparisonValue: Sendable {
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

nonisolated struct WrappedSharedExpenseHighlightValue: Sendable {
    let id: UUID
    let concept: String
    let expectedReimbursement: Decimal
    let date: Date
    let categoryIconName: String
}

nonisolated struct WrappedSharedExpenseSummaryValue: Sendable {
    let movementCount: Int
    let totalExpected: Decimal
    let totalRecovered: Decimal
    let totalPending: Decimal
    let recoveryRate: Decimal?
    let topSharedExpense: WrappedSharedExpenseHighlightValue
}

nonisolated struct WrappedReimbursementCompletionHighlightValue: Sendable {
    let id: UUID
    let concept: String
    let expectedReimbursement: Decimal
    let completionDate: Date
    let expenseDate: Date
    let daysToComplete: Int
}

nonisolated struct WrappedSummaryValue: Sendable {
    let month: WrappedMonth
    let movementCount: Int
    let incomeTotal: Decimal
    let expenseTotal: Decimal
    let netBalance: Decimal
    let savingsRate: Decimal?
    let topExpenseCategories: [WrappedCategoryStatValue]
    let highestExpenseDay: WrappedDayStatValue?
    let mostExpensiveMovement: WrappedMovementHighlightValue?
    let savingsStreakMonths: Int
    let mostActiveWeekday: WrappedWeekdayStatValue?
    let bestSavingsCategory: WrappedCategorySavingsStatValue?
    let averageDailyExpense: WrappedDailyExpenseAverageValue
    let bestWeek: WrappedWeekBalanceStatValue?
    let comparison: WrappedComparisonValue?
    let sharedExpenseSummary: WrappedSharedExpenseSummaryValue?
    let slowestReimbursementCompletion: WrappedReimbursementCompletionHighlightValue?
}

enum MonthlyWrappedService {
    private static let lastViewedMonthKey = "monthlyWrappedLastViewedMonth"
    private static let reminderIdentifier = "monthlyWrappedReminder"

    private nonisolated enum SummaryGenerationError: Error {
        case cancelled
    }

    private nonisolated struct HistoricalExpenseData {
        let movements: [WrappedMovementValue]
        let comparedMonths: Int
    }

    private nonisolated struct SummaryContext {
        let movementsByMonth: [WrappedMonth: [WrappedMovementValue]]
        let expenseMovementsByMonth: [WrappedMonth: [WrappedMovementValue]]
        let totalsByMonth: [WrappedMonth: WrappedPeriodTotals]
        let categoryTotalsByMonth: [WrappedMonth: [WrappedCategoryTotal]]
        let reimbursementsByExpenseID: [UUID: [WrappedMovementValue]]
        let completedReimbursementsByMonth: [WrappedMonth: [WrappedReimbursementCompletionHighlightValue]]
        let movementOrderByID: [UUID: Int]

        init(movements: [WrappedMovementValue]) {
            self = try! Self(movements: movements, isCancelled: { false })
        }

        init(movements: [WrappedMovementValue], isCancelled: () -> Bool) throws {
            let calendar = Calendar.current
            var movementsByMonth: [WrappedMonth: [WrappedMovementValue]] = [:]
            var expenseMovementsByMonth: [WrappedMonth: [WrappedMovementValue]] = [:]
            var totalsByMonth: [WrappedMonth: WrappedPeriodTotals] = [:]
            var categoryTotalsByMonth: [WrappedMonth: [WrappedCategoryTotal]] = [:]
            var sharedExpenses: [WrappedMovementValue] = []
            var movementOrderByID: [UUID: Int] = [:]

            for (index, movement) in movements.enumerated() {
                try MonthlyWrappedService.checkCancellation(isCancelled)
                movementOrderByID[movement.id] = index
                let month = WrappedMonth(
                    year: calendar.component(.year, from: movement.occurredAt),
                    month: calendar.component(.month, from: movement.occurredAt)
                )

                movementsByMonth[month, default: []].append(movement)

                var totals = totalsByMonth[month] ?? WrappedPeriodTotals()
                totals.movementCount += 1

                if movement.isIncome {
                    totals.income += movement.statsIncomeAmount
                } else if movement.isExpense {
                    totals.expense += movement.statsExpenseAmount
                    expenseMovementsByMonth[month, default: []].append(movement)

                    if movement.isSharedExpense && movement.expectedReimbursementAmount > 0 {
                        sharedExpenses.append(movement)
                    }
                }

                totalsByMonth[month] = totals
            }

            for (month, expenseMovements) in expenseMovementsByMonth {
                try MonthlyWrappedService.checkCancellation(isCancelled)
                categoryTotalsByMonth[month] = try MonthlyWrappedService.categoryTotals(
                    from: expenseMovements,
                    isCancelled: isCancelled
                )
            }

            let reimbursementsByExpenseID = try MonthlyWrappedService.reimbursementIncomesByExpenseID(
                from: movements,
                isCancelled: isCancelled
            )
            var completedReimbursementsByMonth: [WrappedMonth: [WrappedReimbursementCompletionHighlightValue]] = [:]

            for expense in sharedExpenses {
                try MonthlyWrappedService.checkCancellation(isCancelled)
                let reimbursements = reimbursementsByExpenseID[expense.id] ?? []
                guard let completionDate = try MonthlyWrappedService.completionDate(
                    for: expense,
                    reimbursements: reimbursements,
                    isCancelled: isCancelled
                ) else { continue }

                let completionMonth = WrappedMonth(
                    year: calendar.component(.year, from: completionDate),
                    month: calendar.component(.month, from: completionDate)
                )
                let completion = WrappedReimbursementCompletionHighlightValue(
                    id: expense.id,
                    concept: expense.concept,
                    expectedReimbursement: expense.expectedReimbursementAmount,
                    completionDate: completionDate,
                    expenseDate: expense.occurredAt,
                    daysToComplete: MonthlyWrappedService.daysBetween(start: expense.occurredAt, end: completionDate)
                )

                completedReimbursementsByMonth[completionMonth, default: []].append(completion)

                let previousMonth = completionMonth.previousMonth
                if MonthlyWrappedService.interval(for: previousMonth).contains(completionDate) {
                    completedReimbursementsByMonth[previousMonth, default: []].append(completion)
                }
            }

            self.movementsByMonth = movementsByMonth
            self.expenseMovementsByMonth = expenseMovementsByMonth
            self.totalsByMonth = totalsByMonth
            self.categoryTotalsByMonth = categoryTotalsByMonth
            self.reimbursementsByExpenseID = reimbursementsByExpenseID
            self.completedReimbursementsByMonth = completedReimbursementsByMonth
            self.movementOrderByID = movementOrderByID
        }

        func summary(for month: WrappedMonth) -> WrappedSummaryValue {
            try! summary(for: month, isCancelled: { false })
        }

        func summary(for month: WrappedMonth, isCancelled: () -> Bool) throws -> WrappedSummaryValue {
            try MonthlyWrappedService.checkCancellation(isCancelled)
            let currentMovements = movementsByMonth[month] ?? []
            let currentExpenseMovements = expenseMovementsByMonth[month] ?? []
            let currentTotals = totalsByMonth[month] ?? WrappedPeriodTotals()
            let currentCategoryTotals = categoryTotalsByMonth[month] ?? []

            let previousMonth = month.previousMonth
            let previousMovements = movementsByMonth[previousMonth] ?? []
            let previousTotals = totalsByMonth[previousMonth] ?? WrappedPeriodTotals()

            let comparison: WrappedComparisonValue?
            if previousMovements.isEmpty {
                comparison = nil
            } else {
                comparison = WrappedComparisonValue(
                    previousMonth: previousMonth,
                    previousIncomeTotal: previousTotals.income,
                    previousExpenseTotal: previousTotals.expense,
                    previousNetBalance: previousTotals.net,
                    previousSavingsRate: previousTotals.savingsRate,
                    incomeDelta: currentTotals.income - previousTotals.income,
                    expenseDelta: currentTotals.expense - previousTotals.expense,
                    netDelta: currentTotals.net - previousTotals.net,
                    savingsRateDelta: MonthlyWrappedService.savingsRateDelta(current: currentTotals.savingsRate, previous: previousTotals.savingsRate)
                )
            }

            let historicalData = try historicalExpenseData(for: month, isCancelled: isCancelled)

            return WrappedSummaryValue(
                month: month,
                movementCount: currentTotals.movementCount,
                incomeTotal: currentTotals.income,
                expenseTotal: currentTotals.expense,
                netBalance: currentTotals.net,
                savingsRate: currentTotals.savingsRate,
                topExpenseCategories: MonthlyWrappedService.topExpenseCategories(from: currentCategoryTotals, limit: 5),
                highestExpenseDay: try MonthlyWrappedService.highestExpenseDay(from: currentExpenseMovements, isCancelled: isCancelled),
                mostExpensiveMovement: try MonthlyWrappedService.mostExpensiveMovement(from: currentExpenseMovements, isCancelled: isCancelled),
                savingsStreakMonths: try MonthlyWrappedService.savingsStreakMonths(for: month, totalsByMonth: totalsByMonth, isCancelled: isCancelled),
                mostActiveWeekday: try MonthlyWrappedService.mostActiveWeekday(from: currentMovements, isCancelled: isCancelled),
                bestSavingsCategory: try MonthlyWrappedService.bestSavingsCategory(
                    currentCategoryTotals: currentCategoryTotals,
                    historicalExpenseMovements: historicalData.movements,
                    comparedMonths: historicalData.comparedMonths,
                    isCancelled: isCancelled
                ),
                averageDailyExpense: MonthlyWrappedService.averageDailyExpense(for: month, expenseTotal: currentTotals.expense),
                bestWeek: try MonthlyWrappedService.bestWeek(for: month, movements: currentMovements, isCancelled: isCancelled),
                comparison: comparison,
                sharedExpenseSummary: try MonthlyWrappedService.sharedExpenseSummary(
                    for: month,
                    currentMovements: currentMovements,
                    reimbursementsByExpenseID: reimbursementsByExpenseID,
                    isCancelled: isCancelled
                ),
                slowestReimbursementCompletion: MonthlyWrappedService.slowestReimbursementCompletion(
                    completions: completedReimbursementsByMonth[month] ?? []
                )
            )
        }

        private func historicalExpenseData(for month: WrappedMonth, isCancelled: () -> Bool) throws -> HistoricalExpenseData {
            let calendar = Calendar.current
            let currentInterval = MonthlyWrappedService.interval(for: month)
            guard calendar.date(byAdding: .month, value: -6, to: currentInterval.start) != nil else {
                return HistoricalExpenseData(movements: [], comparedMonths: 1)
            }

            var historicalMovements: [WrappedMovementValue] = []
            var historicalMonths = 0
            var cursor = month

            for _ in 1...6 {
                try MonthlyWrappedService.checkCancellation(isCancelled)
                cursor = cursor.previousMonth
                let monthMovements = movementsByMonth[cursor] ?? []
                guard !monthMovements.isEmpty else { continue }

                historicalMonths += 1
                historicalMovements.append(contentsOf: expenseMovementsByMonth[cursor] ?? [])
            }

            try MonthlyWrappedService.checkCancellation(isCancelled)
            historicalMovements.sort { lhs, rhs in
                (movementOrderByID[lhs.id] ?? 0) < (movementOrderByID[rhs.id] ?? 0)
            }
            try MonthlyWrappedService.checkCancellation(isCancelled)

            return HistoricalExpenseData(
                movements: historicalMovements,
                comparedMonths: max(1, min(6, historicalMonths))
            )
        }

    }

    private nonisolated static func checkCancellation(_ isCancelled: () -> Bool) throws {
        guard !isCancelled() else { throw SummaryGenerationError.cancelled }
    }

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

    nonisolated static func cancellableClosedMonths(
        from movements: [Movement],
        now: Date = Date(),
        isCancelled: () -> Bool
    ) -> [WrappedMonth]? {
        let calendar = Calendar.current
        let currentMonthStart = startOfMonth(for: now)
        var uniqueMonths: Set<WrappedMonth> = []

        for movement in movements {
            guard !isCancelled() else { return nil }
            guard movement.occurredAt < currentMonthStart else { continue }
            uniqueMonths.insert(
                WrappedMonth(
                    year: calendar.component(.year, from: movement.occurredAt),
                    month: calendar.component(.month, from: movement.occurredAt)
                )
            )
        }

        guard !isCancelled() else { return nil }
        return uniqueMonths.sorted { lhs, rhs in
            if lhs.year == rhs.year {
                return lhs.month > rhs.month
            }

            return lhs.year > rhs.year
        }
    }

    nonisolated static func cancellableClosedMonths(
        from movements: [WrappedMovementValue],
        now: Date,
        isCancelled: () -> Bool
    ) -> [WrappedMonth]? {
        let calendar = Calendar.current
        let currentMonthStart = startOfMonth(for: now)
        var uniqueMonths: Set<WrappedMonth> = []

        for movement in movements {
            guard !isCancelled() else { return nil }
            guard movement.occurredAt < currentMonthStart else { continue }
            uniqueMonths.insert(
                WrappedMonth(
                    year: calendar.component(.year, from: movement.occurredAt),
                    month: calendar.component(.month, from: movement.occurredAt)
                )
            )
        }

        guard !isCancelled() else { return nil }
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

    static func summaries(for months: [WrappedMonth], movements: [Movement]) -> [WrappedMonth: WrappedSummary] {
        guard !months.isEmpty else { return [:] }

        let context = SummaryContext(movements: movementValues(from: movements))
        return Dictionary(uniqueKeysWithValues: months.map { month in
            (month, materialize(context.summary(for: month)))
        })
    }

    static func cancellableSummaries(
        for months: [WrappedMonth],
        movements: [Movement],
        isCancelled: () -> Bool
    ) -> [WrappedMonth: WrappedSummary]? {
        guard !months.isEmpty else { return [:] }

        guard let values = cancellableSummaryValuesSync(
            for: months,
            movements: movementValues(from: movements),
            isCancelled: isCancelled
        ) else { return nil }
        return values.mapValues(materialize)
    }

    static func movementValues(from movements: [Movement]) -> [WrappedMovementValue] {
        movements.map { movement in
            WrappedMovementValue(
                id: movement.id,
                concept: movement.concept,
                amount: movement.amount,
                typeRaw: movement.typeRaw,
                occurredAt: movement.occurredAt,
                updatedAt: movement.updatedAt,
                personalAmount: movement.personalAmount,
                reimbursementForId: movement.reimbursementForId,
                categoryID: movement.category?.id,
                categoryName: movement.category?.name,
                categoryIconRaw: movement.category?.iconRaw,
                categoryColorRaw: movement.category?.colorRaw
            )
        }
    }

    nonisolated static func cancellableHistoryValues(
        for currentMonth: WrappedMonth,
        movements: [WrappedMovementValue]
    ) async -> (months: [WrappedMonth], summaries: [WrappedMonth: WrappedSummaryValue])? {
        let worker = Task.detached(priority: .userInitiated) { () -> (months: [WrappedMonth], summaries: [WrappedMonth: WrappedSummaryValue])? in
            guard let months = MonthlyWrappedService.cancellableClosedMonths(
                from: movements,
                now: currentMonth.monthStart,
                isCancelled: { Task.isCancelled }
            ) else { return nil }
            guard let summaries = MonthlyWrappedService.cancellableSummaryValuesSync(
                for: months,
                movements: movements,
                isCancelled: { Task.isCancelled }
            ) else { return nil }
            return (months: months, summaries: summaries)
        }

        return await withTaskCancellationHandler(operation: {
            await worker.value
        }, onCancel: {
            worker.cancel()
        })
    }

    static func materializeSummaries(_ values: [WrappedMonth: WrappedSummaryValue]) -> [WrappedMonth: WrappedSummary] {
        values.mapValues(materialize)
    }

    private nonisolated static func cancellableSummaryValuesSync(
        for months: [WrappedMonth],
        movements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) -> [WrappedMonth: WrappedSummaryValue]? {
        guard !months.isEmpty else { return [:] }

        do {
            let context = try SummaryContext(movements: movements, isCancelled: isCancelled)
            var summaries: [WrappedMonth: WrappedSummaryValue] = [:]
            summaries.reserveCapacity(months.count)

            for month in months {
                guard !isCancelled() else { return nil }
                let summary = try context.summary(for: month, isCancelled: isCancelled)
                guard !isCancelled() else { return nil }
                summaries[month] = summary
            }

            return summaries
        } catch SummaryGenerationError.cancelled {
            return nil
        } catch {
            return nil
        }
    }

    private nonisolated static func materialize(_ value: WrappedSummaryValue) -> WrappedSummary {
        WrappedSummary(
            month: value.month,
            movementCount: value.movementCount,
            incomeTotal: value.incomeTotal,
            expenseTotal: value.expenseTotal,
            netBalance: value.netBalance,
            savingsRate: value.savingsRate,
            topExpenseCategories: value.topExpenseCategories.map { category in
                WrappedCategoryStat(
                    id: category.id,
                    name: category.name,
                    iconName: category.iconName,
                    color: categoryColor(from: category.colorRaw),
                    amount: category.amount,
                    movementCount: category.movementCount
                )
            },
            highestExpenseDay: value.highestExpenseDay.map { day in
                WrappedDayStat(date: day.date, totalExpense: day.totalExpense, movementCount: day.movementCount)
            },
            mostExpensiveMovement: value.mostExpensiveMovement.map { movement in
                WrappedMovementHighlight(
                    id: movement.id,
                    concept: movement.concept,
                    amount: movement.amount,
                    date: movement.date,
                    categoryName: movement.categoryName,
                    categoryIconName: movement.categoryIconName
                )
            },
            savingsStreakMonths: value.savingsStreakMonths,
            mostActiveWeekday: value.mostActiveWeekday.map { weekday in
                WrappedWeekdayStat(
                    weekday: weekday.weekday,
                    weekdayName: weekday.weekdayName,
                    movementCount: weekday.movementCount
                )
            },
            bestSavingsCategory: value.bestSavingsCategory.map { category in
                WrappedCategorySavingsStat(
                    id: category.id,
                    name: category.name,
                    iconName: category.iconName,
                    color: categoryColor(from: category.colorRaw),
                    currentExpense: category.currentExpense,
                    historicalAverageExpense: category.historicalAverageExpense,
                    savingsDelta: category.savingsDelta,
                    comparedMonths: category.comparedMonths
                )
            },
            averageDailyExpense: WrappedDailyExpenseAverage(
                averageExpense: value.averageDailyExpense.averageExpense,
                dayCount: value.averageDailyExpense.dayCount
            ),
            bestWeek: value.bestWeek.map { week in
                WrappedWeekBalanceStat(
                    id: week.id,
                    weekOfMonth: week.weekOfMonth,
                    startDate: week.startDate,
                    endDate: week.endDate,
                    incomeTotal: week.incomeTotal,
                    expenseTotal: week.expenseTotal,
                    movementCount: week.movementCount
                )
            },
            comparison: value.comparison.map { comparison in
                WrappedComparison(
                    previousMonth: comparison.previousMonth,
                    previousIncomeTotal: comparison.previousIncomeTotal,
                    previousExpenseTotal: comparison.previousExpenseTotal,
                    previousNetBalance: comparison.previousNetBalance,
                    previousSavingsRate: comparison.previousSavingsRate,
                    incomeDelta: comparison.incomeDelta,
                    expenseDelta: comparison.expenseDelta,
                    netDelta: comparison.netDelta,
                    savingsRateDelta: comparison.savingsRateDelta
                )
            },
            sharedExpenseSummary: value.sharedExpenseSummary.map { shared in
                WrappedSharedExpenseSummary(
                    movementCount: shared.movementCount,
                    totalExpected: shared.totalExpected,
                    totalRecovered: shared.totalRecovered,
                    totalPending: shared.totalPending,
                    recoveryRate: shared.recoveryRate,
                    topSharedExpense: WrappedSharedExpenseHighlight(
                        id: shared.topSharedExpense.id,
                        concept: shared.topSharedExpense.concept,
                        expectedReimbursement: shared.topSharedExpense.expectedReimbursement,
                        date: shared.topSharedExpense.date,
                        categoryIconName: shared.topSharedExpense.categoryIconName
                    )
                )
            },
            slowestReimbursementCompletion: value.slowestReimbursementCompletion.map { completion in
                WrappedReimbursementCompletionHighlight(
                    id: completion.id,
                    concept: completion.concept,
                    expectedReimbursement: completion.expectedReimbursement,
                    completionDate: completion.completionDate,
                    expenseDate: completion.expenseDate,
                    daysToComplete: completion.daysToComplete
                )
            }
        )
    }

    private nonisolated static func categoryColor(from rawValue: String) -> Color {
        CategoryColor(rawValue: rawValue)?.color ?? .gray
    }

    static func summary(for month: WrappedMonth, movements: [Movement]) -> WrappedSummary {
        materialize(SummaryContext(movements: movementValues(from: movements)).summary(for: month))
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
        content.title = "Tu resumen mensual ya está listo"
        content.body = "Revisa tu balance, tus mayores gastos y la comparativa con el mes anterior."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: reminderIdentifier,
            content: content,
            trigger: trigger
        )

        center.add(request)
    }

    private nonisolated static func topExpenseCategories(from categoryTotals: [WrappedCategoryTotal], limit: Int) -> [WrappedCategoryStatValue] {
        categoryTotals
            .sorted { lhs, rhs in
                lhs.amount > rhs.amount
            }
            .prefix(limit)
            .map { categoryTotal in
                WrappedCategoryStatValue(
                    id: categoryTotal.descriptor.id,
                    name: categoryTotal.descriptor.name,
                    iconName: categoryTotal.descriptor.iconName,
                    colorRaw: categoryTotal.descriptor.colorRaw,
                    amount: categoryTotal.amount,
                    movementCount: categoryTotal.movementCount
                )
            }
    }

    private nonisolated static func highestExpenseDay(
        from movements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) throws -> WrappedDayStatValue? {
        let calendar = Calendar.current
        var grouped: [Date: (total: Decimal, movementCount: Int)] = [:]

        for movement in movements {
            try Self.checkCancellation(isCancelled)
            let day = calendar.startOfDay(for: movement.occurredAt)
            let previous = grouped[day] ?? (0, 0)
            grouped[day] = (
                previous.total + movement.statsExpenseAmount,
                previous.movementCount + 1
            )
        }

        return grouped
            .compactMap { day, values -> WrappedDayStatValue? in
                guard values.total > 0 else { return nil }
                return WrappedDayStatValue(
                    date: day,
                    totalExpense: values.total,
                    movementCount: values.movementCount
                )
            }
            .max { lhs, rhs in
                lhs.totalExpense < rhs.totalExpense
            }
    }

    private nonisolated static func mostExpensiveMovement(
        from movements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) throws -> WrappedMovementHighlightValue? {
        guard var movement = movements.first else { return nil }
        for candidate in movements.dropFirst() {
            try Self.checkCancellation(isCancelled)
            if movement.statsExpenseAmount < candidate.statsExpenseAmount {
                movement = candidate
            }
        }

        return WrappedMovementHighlightValue(
            id: movement.id,
            concept: movement.concept,
            amount: movement.statsExpenseAmount,
            date: movement.occurredAt,
            categoryName: movement.categoryName ?? "Sin categoría",
            categoryIconName: categoryIconName(for: movement)
        )
    }

    private nonisolated static func savingsStreakMonths(
        for month: WrappedMonth,
        totalsByMonth: [WrappedMonth: WrappedPeriodTotals],
        isCancelled: () -> Bool
    ) throws -> Int {
        var streak = 0
        var cursor = month

        while let totals = totalsByMonth[cursor], totals.net > 0 {
            try Self.checkCancellation(isCancelled)
            streak += 1
            cursor = cursor.previousMonth
        }

        return streak
    }

    private nonisolated static func mostActiveWeekday(
        from movements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) throws -> WrappedWeekdayStatValue? {
        guard !movements.isEmpty else { return nil }

        let calendar = Calendar.current
        let firstWeekday = calendar.firstWeekday
        var grouped: [Int: Int] = [:]
        for movement in movements {
            try Self.checkCancellation(isCancelled)
            let weekday = calendar.component(.weekday, from: movement.occurredAt)
            grouped[weekday, default: 0] += 1
        }

        guard let best = grouped.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return weekdaySortKey(lhs.key, firstWeekday: firstWeekday) > weekdaySortKey(rhs.key, firstWeekday: firstWeekday)
            }
            return lhs.value < rhs.value
        }) else {
            return nil
        }

        return WrappedWeekdayStatValue(
            weekday: best.key,
            weekdayName: weekdayName(for: best.key),
            movementCount: best.value
        )
    }

    private nonisolated static func bestSavingsCategory(
        currentCategoryTotals: [WrappedCategoryTotal],
        historicalExpenseMovements: [WrappedMovementValue],
        comparedMonths: Int,
        isCancelled: () -> Bool
    ) throws -> WrappedCategorySavingsStatValue? {
        guard !historicalExpenseMovements.isEmpty else { return nil }
        let historicalTotals = try categoryTotals(from: historicalExpenseMovements, isCancelled: isCancelled)
        let currentTotalsByCategory = Dictionary(uniqueKeysWithValues: currentCategoryTotals.map { total in
            (total.descriptor.id, total)
        })

        var candidates: [WrappedCategorySavingsStatValue] = []
        candidates.reserveCapacity(historicalTotals.count)
        for historical in historicalTotals {
            try Self.checkCancellation(isCancelled)
            let currentAmount = currentTotalsByCategory[historical.descriptor.id]?.amount ?? 0
            let average = historical.amount / Decimal(comparedMonths)
            candidates.append(
                WrappedCategorySavingsStatValue(
                    id: historical.descriptor.id,
                    name: historical.descriptor.name,
                    iconName: historical.descriptor.iconName,
                    colorRaw: historical.descriptor.colorRaw,
                    currentExpense: currentAmount,
                    historicalAverageExpense: average,
                    savingsDelta: average - currentAmount,
                    comparedMonths: comparedMonths
                )
            )
        }

        return candidates.sorted { lhs, rhs in
            if lhs.savingsDelta == rhs.savingsDelta {
                return lhs.historicalAverageExpense > rhs.historicalAverageExpense
            }
            return lhs.savingsDelta > rhs.savingsDelta
        }.first
    }

    private nonisolated static func averageDailyExpense(for month: WrappedMonth, expenseTotal: Decimal) -> WrappedDailyExpenseAverageValue {
        let dayCount = Calendar.current.range(of: .day, in: .month, for: month.monthStart)?.count ?? 30
        let average = dayCount > 0 ? (expenseTotal / Decimal(dayCount)) : 0

        return WrappedDailyExpenseAverageValue(
            averageExpense: average,
            dayCount: dayCount
        )
    }

    private nonisolated static func bestWeek(for month: WrappedMonth, movements: [WrappedMovementValue]) -> WrappedWeekBalanceStatValue? {
        try! bestWeek(for: month, movements: movements, isCancelled: { false })
    }

    private nonisolated static func bestWeek(
        for month: WrappedMonth,
        movements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) throws -> WrappedWeekBalanceStatValue? {
        let calendar = Calendar.current
        let monthInterval = interval(for: month)
        var buckets: [Date: WrappedWeekAccumulator] = [:]

        for movement in movements {
            try Self.checkCancellation(isCancelled)
            guard let weekInterval = calendar.dateInterval(of: .weekOfMonth, for: movement.occurredAt) else { continue }

            let clampedStart = weekInterval.start < monthInterval.start ? monthInterval.start : weekInterval.start
            let clampedEnd = weekInterval.end > monthInterval.end ? monthInterval.end : weekInterval.end
            let bucketKey = clampedStart

            var bucket = buckets[bucketKey] ?? WrappedWeekAccumulator(
                startDate: clampedStart,
                endDate: clampedEnd
            )

            bucket.movementCount += 1

            if movement.isIncome {
                bucket.income += movement.statsIncomeAmount
            } else if movement.isExpense {
                bucket.expense += movement.statsExpenseAmount
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

        return WrappedWeekBalanceStatValue(
            id: "\(month.key)-week-\(weekIndex)",
            weekOfMonth: weekIndex,
            startDate: bestBucket.startDate,
            endDate: bestBucket.endDate,
            incomeTotal: bestBucket.income,
            expenseTotal: bestBucket.expense,
            movementCount: bestBucket.movementCount
        )
    }

    private nonisolated static func sharedExpenseSummary(
        for month: WrappedMonth,
        currentMovements: [WrappedMovementValue],
        reimbursementsByExpenseID: [UUID: [WrappedMovementValue]]
    ) -> WrappedSharedExpenseSummaryValue? {
        try! sharedExpenseSummary(
            for: month,
            currentMovements: currentMovements,
            reimbursementsByExpenseID: reimbursementsByExpenseID,
            isCancelled: { false }
        )
    }

    private nonisolated static func sharedExpenseSummary(
        for month: WrappedMonth,
        currentMovements: [WrappedMovementValue],
        reimbursementsByExpenseID: [UUID: [WrappedMovementValue]],
        isCancelled: () -> Bool
    ) throws -> WrappedSharedExpenseSummaryValue? {
        let monthInterval = interval(for: month)
        var sharedExpenses: [WrappedMovementValue] = []
        for movement in currentMovements {
            try Self.checkCancellation(isCancelled)
            guard movement.isExpense, movement.isSharedExpense, movement.expectedReimbursementAmount > 0 else { continue }
            sharedExpenses.append(movement)
        }

        guard var topExpense = sharedExpenses.first else { return nil }
        for candidate in sharedExpenses.dropFirst() {
            try Self.checkCancellation(isCancelled)
            if candidate.expectedReimbursementAmount > topExpense.expectedReimbursementAmount ||
                (candidate.expectedReimbursementAmount == topExpense.expectedReimbursementAmount && candidate.occurredAt > topExpense.occurredAt) {
                topExpense = candidate
            }
        }

        var totalExpected: Decimal = 0
        var totalRecovered: Decimal = 0
        var totalPending: Decimal = 0

        for expense in sharedExpenses {
            try Self.checkCancellation(isCancelled)
            let reimbursements = reimbursementsByExpenseID[expense.id] ?? []
            var recoveredUntilMonthEnd: Decimal = 0
            for reimbursement in reimbursements {
                try Self.checkCancellation(isCancelled)
                guard reimbursement.occurredAt < monthInterval.end else { continue }
                recoveredUntilMonthEnd += max(reimbursement.amount, 0)
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

        return WrappedSharedExpenseSummaryValue(
            movementCount: sharedExpenses.count,
            totalExpected: totalExpected,
            totalRecovered: totalRecovered,
            totalPending: totalPending,
            recoveryRate: recoveryRate,
            topSharedExpense: WrappedSharedExpenseHighlightValue(
                id: topExpense.id,
                concept: topExpense.concept,
                expectedReimbursement: topExpense.expectedReimbursementAmount,
                date: topExpense.occurredAt,
                categoryIconName: categoryIconName(for: topExpense, missing: "person.2.fill")
            )
        )
    }

    private nonisolated static func slowestReimbursementCompletion(
        completions: [WrappedReimbursementCompletionHighlightValue]
    ) -> WrappedReimbursementCompletionHighlightValue? {
        completions.max(by: { lhs, rhs in
            if lhs.daysToComplete == rhs.daysToComplete {
                return lhs.expectedReimbursement < rhs.expectedReimbursement
            }
            return lhs.daysToComplete < rhs.daysToComplete
        })
    }

    private nonisolated static func weekIndexInMonth(for weekStartDate: Date, month: WrappedMonth, calendar: Calendar) -> Int {
        let monthStart = month.monthStart
        let anchorWeekStart = calendar.dateInterval(of: .weekOfMonth, for: monthStart)?.start ?? monthStart
        let weekDistance = calendar.dateComponents([.weekOfYear], from: anchorWeekStart, to: weekStartDate).weekOfYear ?? 0
        return max(1, weekDistance + 1)
    }

    private nonisolated static func categoryTotals(from movements: [WrappedMovementValue]) -> [WrappedCategoryTotal] {
        try! categoryTotals(from: movements, isCancelled: { false })
    }

    private nonisolated static func categoryTotals(
        from movements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) throws -> [WrappedCategoryTotal] {
        var grouped: [String: (descriptor: WrappedCategoryDescriptor, amount: Decimal, movementCount: Int)] = [:]

        for movement in movements {
            try Self.checkCancellation(isCancelled)
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

    private nonisolated static func reimbursementIncomesByExpenseID(from movements: [WrappedMovementValue]) -> [UUID: [WrappedMovementValue]] {
        try! reimbursementIncomesByExpenseID(from: movements, isCancelled: { false })
    }

    private nonisolated static func reimbursementIncomesByExpenseID(
        from movements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) throws -> [UUID: [WrappedMovementValue]] {
        var grouped: [UUID: [WrappedMovementValue]] = [:]

        for movement in movements where movement.isIncome {
            guard !isCancelled() else { throw SummaryGenerationError.cancelled }
            guard let expenseID = movement.reimbursementForId else { continue }
            grouped[expenseID, default: []].append(movement)
        }

        for expenseID in grouped.keys {
            guard !isCancelled() else { throw SummaryGenerationError.cancelled }
            grouped[expenseID]?.sort { lhs, rhs in
                lhs.occurredAt < rhs.occurredAt
            }
        }

        return grouped
    }

    private nonisolated static func completionDate(for expense: WrappedMovementValue, reimbursements: [WrappedMovementValue]) -> Date? {
        try! completionDate(for: expense, reimbursements: reimbursements, isCancelled: { false })
    }

    private nonisolated static func completionDate(
        for expense: WrappedMovementValue,
        reimbursements: [WrappedMovementValue],
        isCancelled: () -> Bool
    ) throws -> Date? {
        let expected = expense.expectedReimbursementAmount
        guard expected > 0 else { return nil }

        var recovered: Decimal = 0
        for reimbursement in reimbursements {
            try Self.checkCancellation(isCancelled)
            recovered += max(reimbursement.amount, 0)
            if recovered >= expected {
                return reimbursement.occurredAt
            }
        }

        return nil
    }

    private nonisolated static func daysBetween(start: Date, end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return max(calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0, 0)
    }

    private nonisolated static func categoryDescriptor(for movement: WrappedMovementValue) -> WrappedCategoryDescriptor {
        WrappedCategoryDescriptor(
            id: movement.categoryID?.uuidString ?? "no-category",
            name: movement.categoryName ?? "Sin categoría",
            iconName: categoryIconName(for: movement),
            colorRaw: categoryColorRaw(for: movement)
        )
    }

    private nonisolated static func categoryIconName(for movement: WrappedMovementValue, missing: String = "tag") -> String {
        guard movement.categoryID != nil else { return missing }
        if let iconRaw = movement.categoryIconRaw, CategoryIcon.emoji(from: iconRaw) != nil {
            return iconRaw
        }
        return CategoryIcon(rawValue: movement.categoryIconRaw ?? "")?.systemName ?? CategoryIcon.tag.systemName
    }

    private nonisolated static func categoryColorRaw(for movement: WrappedMovementValue) -> String {
        guard movement.categoryID != nil else { return CategoryColor.gray.rawValue }
        return CategoryColor(rawValue: movement.categoryColorRaw ?? "")?.rawValue ?? CategoryColor.blue.rawValue
    }

    private nonisolated static func weekdayName(for weekday: Int) -> String {
        let symbols = WrappedWeekdayFormatter.symbols
        guard symbols.indices.contains(weekday - 1) else {
            return "Día \(weekday)"
        }

        return symbols[weekday - 1]
    }

    private nonisolated static func weekdaySortKey(_ weekday: Int, firstWeekday: Int) -> Int {
        (weekday - firstWeekday + 7) % 7
    }

    private nonisolated static func savingsRateDelta(current: Decimal?, previous: Decimal?) -> Decimal? {
        guard let current, let previous else { return nil }
        return current - previous
    }

    private nonisolated static func startOfMonth(for date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? date
    }

    private nonisolated static func interval(for month: WrappedMonth) -> DateInterval {
        let start = month.monthStart
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }
}
