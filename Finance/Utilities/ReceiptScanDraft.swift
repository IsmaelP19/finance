//
//  ReceiptScanDraft.swift
//  Finance
//

import Foundation

enum ReceiptAmountStatus: String, Equatable, Sendable {
    case detected
    case missing
    case ambiguous
}

/// Temporary, non-persistent result of scanning a receipt before user confirmation.
struct ReceiptScanDraft: Equatable, Sendable {
    let amount: Decimal?
    let currencyCode: String?
    let merchant: String?
    let occurredAt: Date?
    let amountStatus: ReceiptAmountStatus
    let warnings: [String]

    nonisolated init(
        amount: Decimal? = nil,
        currencyCode: String? = nil,
        merchant: String? = nil,
        occurredAt: Date? = nil,
        amountStatus: ReceiptAmountStatus = .missing,
        warnings: [String] = []
    ) {
        self.amount = amount
        self.currencyCode = currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.merchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.occurredAt = occurredAt
        self.amountStatus = amountStatus
        self.warnings = warnings
    }
}
