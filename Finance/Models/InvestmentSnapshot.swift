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

struct InvestmentSnapshotDTO: Codable {
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
