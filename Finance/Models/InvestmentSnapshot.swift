//
//  InvestmentSnapshot.swift
//  Finance
//
//  Created by OpenCode on 17/02/2026.
//

import Foundation
import SwiftData

/// Snapshot diario de inversión para construir series temporales.
@Model
final class InvestmentSnapshot {
    var id: UUID
    var snapshotDate: Date
    var investedAmount: Decimal
    var marketValue: Decimal
    var createdAt: Date
    var updatedAt: Date

    var account: BankAccount?

    init(
        snapshotDate: Date,
        investedAmount: Decimal,
        marketValue: Decimal,
        account: BankAccount? = nil
    ) {
        self.id = UUID()
        self.snapshotDate = snapshotDate
        self.investedAmount = investedAmount
        self.marketValue = marketValue
        self.account = account
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

extension InvestmentSnapshot {
    /// Devuelve una única medición por día, conservando la última añadida o actualizada.
    static func dailySnapshots(
        from snapshots: [InvestmentSnapshot],
        calendar: Calendar = .current
    ) -> [InvestmentSnapshot] {
        let snapshotsByDay = Dictionary(grouping: snapshots) {
            calendar.startOfDay(for: $0.snapshotDate)
        }

        return snapshotsByDay.values
            .compactMap { daySnapshots in
                daySnapshots.max { isEarlierMeasurement($0, than: $1) }
            }
            .sorted {
                if $0.snapshotDate != $1.snapshotDate {
                    return $0.snapshotDate < $1.snapshotDate
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    /// Devuelve la última medición registrada para el día indicado.
    static func latestSnapshot(
        on date: Date,
        from snapshots: [InvestmentSnapshot],
        calendar: Calendar = .current
    ) -> InvestmentSnapshot? {
        dailySnapshots(from: snapshots, calendar: calendar)
            .first { calendar.isDate($0.snapshotDate, inSameDayAs: date) }
    }

    /// Devuelve el snapshot con la mayor rentabilidad porcentual histórica.
    /// Las mediciones sin aportación positiva no pueden producir un porcentaje válido.
    /// En caso de empate se conserva la fecha más antigua.
    static func maximumReturnSnapshot(
        from snapshots: [InvestmentSnapshot],
        calendar: Calendar = .current
    ) -> (snapshot: InvestmentSnapshot, percentage: Decimal)? {
        dailySnapshots(from: snapshots, calendar: calendar)
            .compactMap { snapshot in
                guard snapshot.investedAmount > 0 else { return nil }
                let profit = snapshot.marketValue - snapshot.investedAmount
                return (snapshot: snapshot, percentage: (profit / snapshot.investedAmount) * 100)
            }
            .max { lhs, rhs in
                if lhs.percentage != rhs.percentage {
                    return lhs.percentage < rhs.percentage
                }
                return lhs.snapshot.snapshotDate > rhs.snapshot.snapshotDate
            }
    }

    /// Construye totales diarios agregados por cuenta, arrastrando el último
    /// valor conocido de cada cuenta hasta la siguiente medición.
    static func aggregatedDailyTotals(
        from snapshots: [InvestmentSnapshot],
        calendar: Calendar = .current
    ) -> [InvestmentDailyTotal] {
        let groupedByAccount = Dictionary(grouping: snapshots.compactMap { snapshot -> (UUID, InvestmentSnapshot)? in
            guard let accountID = snapshot.account?.id else { return nil }
            return (accountID, snapshot)
        }) { pair in
            pair.0
        }

        let dailyByAccount = groupedByAccount.mapValues {
            dailySnapshots(from: $0.map(\.1), calendar: calendar)
        }
        let dates = Set(dailyByAccount.values.flatMap { accountSnapshots in
            accountSnapshots.map { calendar.startOfDay(for: $0.snapshotDate) }
        }).sorted()

        var indices = Dictionary(uniqueKeysWithValues: dailyByAccount.keys.map { ($0, -1) })
        var latestByAccount: [UUID: InvestmentSnapshot] = [:]

        return dates.compactMap { date in
            for (accountID, accountSnapshots) in dailyByAccount {
                var index = indices[accountID] ?? -1
                while index + 1 < accountSnapshots.count,
                      calendar.startOfDay(for: accountSnapshots[index + 1].snapshotDate) <= date {
                    index += 1
                }
                indices[accountID] = index

                if index >= 0 {
                    latestByAccount[accountID] = accountSnapshots[index]
                }
            }

            guard !latestByAccount.isEmpty else { return nil }
            return InvestmentDailyTotal(
                id: date,
                date: date,
                invested: latestByAccount.values.reduce(Decimal.zero) { $0 + $1.investedAmount },
                market: latestByAccount.values.reduce(Decimal.zero) { $0 + $1.marketValue }
            )
        }
    }

    private static func isEarlierMeasurement(
        _ lhs: InvestmentSnapshot,
        than rhs: InvestmentSnapshot
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct InvestmentDailyTotal: Identifiable {
    let id: Date
    let date: Date
    let invested: Decimal
    let market: Decimal

    var profit: Decimal {
        market - invested
    }

    var returnPercent: Decimal? {
        guard invested > 0 else { return nil }
        return (profit / invested) * 100
    }

    static func maximumReturnPercent(in totals: [InvestmentDailyTotal]) -> InvestmentPeakMetric? {
        totals
            .compactMap { total -> InvestmentPeakMetric? in
                guard let returnPercent = total.returnPercent else { return nil }
                return InvestmentPeakMetric(
                    value: returnPercent,
                    date: total.date,
                    monetaryValue: total.profit
                )
            }
            .max { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                return lhs.date > rhs.date
            }
    }
}

struct InvestmentPeakMetric {
    let value: Decimal
    let date: Date
    let monetaryValue: Decimal?

    init(value: Decimal, date: Date, monetaryValue: Decimal? = nil) {
        self.value = value
        self.date = date
        self.monetaryValue = monetaryValue
    }
}

nonisolated struct InvestmentSnapshotDTO: Codable, Sendable {
    let id: UUID
    let snapshotDate: Date
    let investedAmount: Decimal
    let marketValue: Decimal
    let createdAt: Date
    let updatedAt: Date
    let accountId: UUID?

    init(from snapshot: InvestmentSnapshot) {
        self.id = snapshot.id
        self.snapshotDate = snapshot.snapshotDate
        self.investedAmount = snapshot.investedAmount
        self.marketValue = snapshot.marketValue
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
        self.accountId = snapshot.account?.id
    }

    func toModel() -> InvestmentSnapshot {
        let snapshot = InvestmentSnapshot(
            snapshotDate: snapshotDate,
            investedAmount: investedAmount,
            marketValue: marketValue,
            account: nil
        )
        snapshot.id = id
        snapshot.createdAt = createdAt
        snapshot.updatedAt = updatedAt
        return snapshot
    }
}
