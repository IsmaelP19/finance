//
//  RecurringMovementService.swift
//  Finance
//
//  Created by OpenCode on 17/02/2026.
//

import Foundation

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

enum RecurringMovementService {
    static func pendingMovements(
        for rules: [RecurringMovement],
        confirmedMovements: [Movement],
        now: Date = Date(),
        horizonDays: Int = 90,
        calendar: Calendar = .current
    ) -> [PendingRecurringMovement] {
        let today = calendar.startOfDay(for: now)
        let pendingInterval = pendingWindow(for: now, horizonDays: horizonDays, calendar: calendar)

        var pending: [PendingRecurringMovement] = []

        for rule in rules {
            guard rule.isActive, rule.type != .transfer else { continue }
            guard rule.account?.isActive == true else { continue }

            let dueDates = dueDates(of: rule, in: pendingInterval, calendar: calendar)

            for dueDate in dueDates {
                guard !isOccurrenceConfirmed(ruleID: rule.id, dueDate: dueDate, movements: confirmedMovements, calendar: calendar) else {
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
        calendar: Calendar = .current
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

            if candidate >= interval.start {
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
        calendar: Calendar
    ) -> Date? {
        guard index >= 0 else { return nil }

        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: index * 7, to: startDate)
        case .monthly:
            return calendar.date(byAdding: .month, value: index, to: startDate)
        case .yearly:
            return calendar.date(byAdding: .year, value: index, to: startDate)
        }
    }

    static func isOccurrenceConfirmed(
        ruleID: UUID,
        dueDate: Date,
        movements: [Movement],
        calendar: Calendar = .current
    ) -> Bool {
        movements.contains { movement in
            guard movement.recurringRuleId == ruleID else { return false }
            if let scheduled = movement.recurringScheduledAt {
                return calendar.isDate(scheduled, inSameDayAs: dueDate)
            }
            return calendar.isDate(movement.occurredAt, inSameDayAs: dueDate)
        }
    }
}
