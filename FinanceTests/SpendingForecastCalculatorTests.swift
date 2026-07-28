//
//  SpendingForecastCalculatorTests.swift
//  FinanceTests
//
//  Created by OpenCode on 04/06/2026.
//

import Foundation
import Testing
@testable import Finance

@MainActor
struct SpendingForecastCalculatorTests {
    @Test func projectsMonthEndSpendFromCurrentDailyAverage() async throws {
        let forecast = SpendingForecastCalculator.makeForecast(
            monthlyBudget: 1_000,
            spentSoFar: 250,
            spendingDays: 4,
            asOf: date(year: 2026, month: 6, day: 10),
            calendar: calendar
        )

        #expect(forecast.projectedMonthEndSpend == 750)
        #expect(forecast.projectedMargin == 250)
        #expect(forecast.status == .good)
    }

    @Test func detectsExpectedBudgetDepletionDate() async throws {
        let forecast = SpendingForecastCalculator.makeForecast(
            monthlyBudget: 1_000,
            spentSoFar: 600,
            spendingDays: 8,
            asOf: date(year: 2026, month: 6, day: 10),
            calendar: calendar
        )

        #expect(forecast.status == .risk)
        #expect(forecast.estimatedDepletionDate == date(year: 2026, month: 6, day: 17))
    }

    @Test func reportsLowReliabilityWithFewDaysOrFewSpendingDays() async throws {
        let forecast = SpendingForecastCalculator.makeForecast(
            monthlyBudget: 1_000,
            spentSoFar: 100,
            spendingDays: 1,
            asOf: date(year: 2026, month: 6, day: 3),
            calendar: calendar
        )

        #expect(forecast.reliability == .low)
    }

    @Test func usesHistoricalAverageWhenThereAreAtLeastTwoRecentValidMonths() async throws {
        let category = MovementCategory(name: "Compras")
        let budget = Budget(totalAmount: 600)
        budget.items = [BudgetItem(allocatedAmount: 600, category: category)]

        let forecast = BudgetService.forecast(
            for: budget,
            movements: [
                movement(amount: 100, category: category, date: date(year: 2026, month: 6, day: 1)),
                movement(amount: 999, category: category, date: date(year: 2026, month: 6, day: 10)),
                movement(amount: 50, category: category, date: date(year: 2026, month: 5, day: 4)),
                movement(amount: 200, category: category, date: date(year: 2026, month: 5, day: 5)),
                movement(amount: 75, category: category, date: date(year: 2026, month: 4, day: 2)),
                movement(amount: 300, category: category, date: date(year: 2026, month: 4, day: 20))
            ],
            asOf: date(year: 2026, month: 6, day: 4)
        )

        #expect(forecast.basis == .historicalAverage)
        #expect(forecast.historicalMonthsUsed == 2)
        #expect(forecast.spentSoFar == 100)
        #expect(forecast.historicalRemainingSpendAverage == 250)
        #expect(forecast.projectedMonthEndSpend == 350)
    }

    @Test func fallsBackToCurrentPaceWithOnlyOneValidHistoricalMonth() async throws {
        let category = MovementCategory(name: "Compras")
        let budget = Budget(totalAmount: 600)
        budget.items = [BudgetItem(allocatedAmount: 600, category: category)]

        let forecast = BudgetService.forecast(
            for: budget,
            movements: [
                movement(amount: 100, category: category, date: date(year: 2026, month: 6, day: 1)),
                movement(amount: 200, category: category, date: date(year: 2026, month: 5, day: 5))
            ],
            asOf: date(year: 2026, month: 6, day: 4)
        )

        #expect(forecast.basis == .currentPace)
        #expect(forecast.historicalMonthsUsed == 0)
        #expect(forecast.projectedMonthEndSpend == 750)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))!
    }

    private func movement(amount: Decimal, category: MovementCategory, date: Date) -> Movement {
        Movement(
            concept: "Test",
            amount: amount,
            type: .expense,
            occurredAt: date,
            category: category
        )
    }
}
