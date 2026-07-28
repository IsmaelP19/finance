//
//  RecurringMovementService.swift
//  Finance
//
//  Created by OpenCode on 17/02/2026.
//

import Foundation
import SwiftData

enum PendingRecurringMovementStatus {
    case overdue
    case dueToday
    case upcoming

    var priority: Int {
        switch self {
        case .overdue:
            return 0
        case .dueToday:
            return 1
        case .upcoming:
            return 2
        }
    }

    var displayName: String {
        switch self {
        case .overdue:
            return "Vencido"
        case .dueToday:
            return "Hoy"
        case .upcoming:
            return "Próximo"
        }
    }
}

struct PendingRecurringMovement: Identifiable {
    let rule: RecurringMovement
    let dueDate: Date
    let status: PendingRecurringMovementStatus

    var id: String {
        "\(rule.id.uuidString)-\(Int(dueDate.timeIntervalSince1970))"
    }
}

enum RecurringMovementServiceError: LocalizedError {
    case invalidAmount
    case transferNotSupported
    case missingAccount
    case inactiveAccount
    case occurrenceAlreadyResolved

    var errorDescription: String? {
        switch self {
        case .invalidAmount:
            return "El importe debe ser mayor que cero."
        case .transferNotSupported:
            return "Las transferencias no se pueden confirmar como recurrentes."
        case .missingAccount:
            return "La cuenta asociada ya no está disponible. Edita la recurrencia para continuar."
        case .inactiveAccount:
            return "La cuenta asociada está archivada. Finaliza o edita la recurrencia para continuar."
        case .occurrenceAlreadyResolved:
            return "Esta ocurrencia ya estaba confirmada u omitida."
        }
    }
}

enum RecurringMovementService {
    nonisolated static var recurrenceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    static func pendingMovements(
        for rules: [RecurringMovement],
        confirmedMovements: [Movement],
        now: Date = Date(),
        horizonDays: Int = 90,
        calendar: Calendar = recurrenceCalendar
    ) -> [PendingRecurringMovement] {
        let today = calendar.startOfDay(for: now)
        let pendingInterval = pendingWindow(for: now, horizonDays: horizonDays, calendar: calendar)

        var pending: [PendingRecurringMovement] = []

        for rule in rules {
            guard (rule.isActive || rule.endDate != nil), rule.type != .transfer else { continue }
            guard rule.account?.isActive == true else { continue }

            let dueDates = dueDates(of: rule, in: pendingInterval, calendar: calendar)

            for dueDate in dueDates {
                guard !isOccurrenceConfirmed(ruleID: rule.id, dueDate: dueDate, movements: confirmedMovements, calendar: calendar) else {
                    continue
                }
                guard !isOccurrenceSkipped(rule: rule, dueDate: dueDate, calendar: calendar) else {
                    continue
                }

                let status: PendingRecurringMovementStatus
                if dueDate < today {
                    status = .overdue
                } else if calendar.isDate(dueDate, inSameDayAs: today) {
                    status = .dueToday
                } else {
                    status = .upcoming
                }

                pending.append(PendingRecurringMovement(rule: rule, dueDate: dueDate, status: status))
            }
        }

        return pending.sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            return lhs.dueDate < rhs.dueDate
        }
    }

    static func dueDates(
        of rule: RecurringMovement,
        in interval: DateInterval,
        calendar: Calendar = recurrenceCalendar
    ) -> [Date] {
        let normalizedStart = calendar.startOfDay(for: rule.startDate)
        guard normalizedStart < interval.end else { return [] }

        let normalizedRuleEnd = rule.endDate.map { calendar.startOfDay(for: $0) }
        if let normalizedRuleEnd, normalizedRuleEnd < interval.start {
            return []
        }

        var dueDates: [Date] = []
        var occurrenceIndex = 0
        let maxIterations = 10000

        while occurrenceIndex < maxIterations {
            guard let candidate = dateForOccurrence(
                at: occurrenceIndex,
                frequency: rule.frequency,
                startDate: normalizedStart,
                anchorDay: rule.dayOfMonth,
                calendar: calendar
            ) else {
                break
            }

            if candidate >= interval.end {
                break
            }

            if let normalizedRuleEnd, candidate > normalizedRuleEnd {
                break
            }

            if candidate >= normalizedStart, candidate >= interval.start {
                dueDates.append(candidate)
            }

            occurrenceIndex += 1
        }

        return dueDates
    }

    private static func pendingWindow(for date: Date, horizonDays: Int, calendar: Calendar) -> DateInterval {
        let startComponents = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: startComponents) ?? calendar.startOfDay(for: date)
        let reference = calendar.startOfDay(for: date)
        let safeHorizonDays = max(horizonDays, 1)
        let end = calendar.date(byAdding: .day, value: safeHorizonDays, to: reference) ?? date
        return DateInterval(start: start, end: end)
    }

    private static func dateForOccurrence(
        at index: Int,
        frequency: RecurringMovementFrequency,
        startDate: Date,
        anchorDay: Int,
        calendar: Calendar
    ) -> Date? {
        guard index >= 0 else { return nil }

        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: index * 7, to: startDate)
        case .monthly:
            guard let targetMonth = calendar.date(byAdding: .month, value: index, to: startDate) else {
                return nil
            }
            return anchoredDate(
                in: targetMonth,
                month: calendar.component(.month, from: targetMonth),
                day: anchorDay,
                calendar: calendar
            )
        case .yearly:
            guard let targetYear = calendar.date(byAdding: .year, value: index, to: startDate) else {
                return nil
            }
            return anchoredDate(
                in: targetYear,
                month: calendar.component(.month, from: startDate),
                day: anchorDay,
                calendar: calendar
            )
        }
    }

    private static func anchoredDate(
        in referenceDate: Date,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> Date? {
        var components = calendar.dateComponents([.era, .year], from: referenceDate)
        components.month = month
        components.day = 1

        guard let firstDay = calendar.date(from: components),
              let validDays = calendar.range(of: .day, in: .month, for: firstDay) else {
            return nil
        }

        components.day = min(max(day, validDays.lowerBound), validDays.upperBound - 1)
        return calendar.date(from: components).map { calendar.startOfDay(for: $0) }
    }

    static func isOccurrenceConfirmed(
        ruleID: UUID,
        dueDate: Date,
        movements: [Movement],
        calendar: Calendar = recurrenceCalendar
    ) -> Bool {
        confirmedMovement(
            ruleID: ruleID,
            dueDate: dueDate,
            movements: movements,
            calendar: calendar
        ) != nil
    }

    static func confirmedMovement(
        ruleID: UUID,
        dueDate: Date,
        movements: [Movement],
        calendar: Calendar = recurrenceCalendar
    ) -> Movement? {
        movements.first { movement in
            guard movement.recurringRuleId == ruleID else { return false }
            if let scheduled = movement.recurringScheduledAt {
                return calendar.isDate(scheduled, inSameDayAs: dueDate)
            }
            return calendar.isDate(movement.occurredAt, inSameDayAs: dueDate)
        }
    }

    static func isOccurrenceSkipped(
        rule: RecurringMovement,
        dueDate: Date,
        calendar: Calendar = recurrenceCalendar
    ) -> Bool {
        rule.skippedOccurrenceDates.contains { skippedDate in
            calendar.isDate(skippedDate, inSameDayAs: dueDate)
        }
    }

    static func effectiveAmount(
        rule: RecurringMovement,
        dueDate: Date,
        movements: [Movement],
        calendar: Calendar = recurrenceCalendar
    ) -> Decimal {
        confirmedMovement(
            ruleID: rule.id,
            dueDate: dueDate,
            movements: movements,
            calendar: calendar
        )?.amount ?? rule.amount
    }

    @MainActor
    static func confirmOccurrence(
        rule: RecurringMovement,
        dueDate: Date,
        amount: Decimal,
        applyToFuture: Bool,
        currencyCode: String,
        in modelContext: ModelContext,
        calendar: Calendar = recurrenceCalendar
    ) throws -> Movement {
        guard amount > 0 else {
            throw RecurringMovementServiceError.invalidAmount
        }
        guard rule.type != .transfer else {
            throw RecurringMovementServiceError.transferNotSupported
        }
        guard let account = rule.account else {
            throw RecurringMovementServiceError.missingAccount
        }
        guard account.isActive else {
            throw RecurringMovementServiceError.inactiveAccount
        }

        let movements = try modelContext.fetch(FetchDescriptor<Movement>())
        guard !isOccurrenceConfirmed(
            ruleID: rule.id,
            dueDate: dueDate,
            movements: movements,
            calendar: calendar
        ), !isOccurrenceSkipped(rule: rule, dueDate: dueDate, calendar: calendar) else {
            throw RecurringMovementServiceError.occurrenceAlreadyResolved
        }

        let movementRule: RecurringMovement
        if applyToFuture {
            movementRule = ruleForFutureChanges(
                from: rule,
                boundaryDate: dueDate,
                movements: movements,
                in: modelContext,
                calendar: calendar
            )
            movementRule.amount = amount
        } else {
            movementRule = rule
        }

        account.currency = currencyCode
        switch movementRule.type {
        case .expense:
            account.balance -= amount
        case .income:
            account.balance += amount
        case .transfer:
            break
        }
        account.updatedAt = Date()

        let movement = Movement(
            concept: movementRule.concept,
            amount: amount,
            type: movementRule.type,
            occurredAt: Date(),
            account: account,
            destinationAccount: nil,
            category: movementRule.category,
            notes: movementRule.notes,
            resultingBalance: account.balance,
            recurringRuleId: movementRule.id,
            recurringScheduledAt: calendar.startOfDay(for: dueDate)
        )

        modelContext.insert(movement)
        movementRule.updatedAt = Date()
        _ = try MovementBalanceService.rebuild(in: modelContext)
        try modelContext.save()
        return movement
    }

    @MainActor
    static func skipOccurrence(
        rule: RecurringMovement,
        dueDate: Date,
        in modelContext: ModelContext,
        calendar: Calendar = recurrenceCalendar
    ) throws {
        let movements = try modelContext.fetch(FetchDescriptor<Movement>())
        guard !isOccurrenceConfirmed(
            ruleID: rule.id,
            dueDate: dueDate,
            movements: movements,
            calendar: calendar
        ) else {
            throw RecurringMovementServiceError.occurrenceAlreadyResolved
        }

        guard !isOccurrenceSkipped(rule: rule, dueDate: dueDate, calendar: calendar) else {
            return
        }

        rule.skippedOccurrenceDates.append(calendar.startOfDay(for: dueDate))
        rule.updatedAt = Date()
        try modelContext.save()
    }

    @MainActor
    static func endRecurrence(
        _ rule: RecurringMovement,
        before dueDate: Date,
        in modelContext: ModelContext,
        calendar: Calendar = recurrenceCalendar
    ) throws {
        let boundary = calendar.startOfDay(for: dueDate)
        rule.endDate = calendar.date(byAdding: .day, value: -1, to: boundary)
        rule.isActive = false
        rule.updatedAt = Date()
        try modelContext.save()
    }

    @MainActor
    static func ruleForFutureChanges(
        from rule: RecurringMovement,
        boundaryDate: Date,
        movements: [Movement],
        in modelContext: ModelContext,
        calendar: Calendar = recurrenceCalendar
    ) -> RecurringMovement {
        let boundary = calendar.startOfDay(for: boundaryDate)
        let currentStart = calendar.startOfDay(for: rule.startDate)
        guard boundary > currentStart else {
            return rule
        }

        let previousEndDate = rule.endDate
        let previousSkippedDates = rule.skippedOccurrenceDates
        let futureRule = RecurringMovement(
            concept: rule.concept,
            amount: rule.amount,
            type: rule.type,
            frequency: rule.frequency,
            dayOfMonth: rule.dayOfMonth,
            startDate: boundary,
            endDate: previousEndDate,
            account: rule.account,
            category: rule.category,
            notes: rule.notes,
            isActive: true,
            skippedOccurrenceDates: previousSkippedDates.filter {
                calendar.startOfDay(for: $0) >= boundary
            }
        )

        rule.skippedOccurrenceDates = previousSkippedDates.filter {
            calendar.startOfDay(for: $0) < boundary
        }
        rule.endDate = calendar.date(byAdding: .day, value: -1, to: boundary)
        rule.isActive = false
        rule.updatedAt = Date()

        for movement in movements where movement.recurringRuleId == rule.id {
            let scheduledDate = movement.recurringScheduledAt ?? movement.occurredAt
            if calendar.startOfDay(for: scheduledDate) >= boundary {
                movement.recurringRuleId = futureRule.id
                movement.updatedAt = Date()
            }
        }

        modelContext.insert(futureRule)
        return futureRule
    }
}
