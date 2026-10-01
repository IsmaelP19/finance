//
//  WalletExpenseDraft.swift
//  Finance
//
//  Created by OpenAI Codex on 11/08/2026.
//

import Foundation

/// Draft produced by a Wallet transaction automation before the user confirms a movement.
struct WalletExpenseDraft: Codable, Identifiable {
    let id: UUID
    let amount: Decimal?
    let currencyCode: String?
    let merchant: String?
    let cardName: String?
    let transactionDate: Date
    let createdAt: Date

    init(
        id: UUID = UUID(),
        amount: Decimal? = nil,
        currencyCode: String? = nil,
        merchant: String? = nil,
        cardName: String? = nil,
        transactionDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount.flatMap { $0 > 0 ? $0 : nil }
        self.currencyCode = Self.normalizedText(currencyCode)?.uppercased()
        self.merchant = Self.normalizedText(merchant)
        self.cardName = Self.normalizedText(cardName)
        self.transactionDate = transactionDate ?? createdAt
        self.createdAt = createdAt
    }

    var suggestedConcept: String {
        merchant ?? "Pago con Wallet"
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Small persistent queue shared by the App Intent and the main application process.
enum WalletExpenseDraftStore {
    static let storageKey = "walletExpenseDrafts.pending"

    private static let lock = NSLock()

    static func enqueue(_ draft: WalletExpenseDraft, in defaults: UserDefaults = .standard) throws {
        lock.lock()
        defer { lock.unlock() }

        var drafts = decodedDrafts(from: defaults)
        drafts.append(draft)

        let data = try JSONEncoder().encode(drafts)
        defaults.set(data, forKey: storageKey)
    }

    static func nextPending(from defaults: UserDefaults = .standard) -> WalletExpenseDraft? {
        lock.lock()
        defer { lock.unlock() }

        return decodedDrafts(from: defaults).first
    }

    static func acknowledge(_ draftID: UUID, in defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }

        var drafts = decodedDrafts(from: defaults)
        drafts.removeAll { $0.id == draftID }
        if drafts.isEmpty {
            defaults.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(drafts) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func pendingDrafts(in defaults: UserDefaults = .standard) -> [WalletExpenseDraft] {
        lock.lock()
        defer { lock.unlock() }
        return decodedDrafts(from: defaults)
    }

    static func removeAll(from defaults: UserDefaults = .standard) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey)
    }

    private static func decodedDrafts(from defaults: UserDefaults) -> [WalletExpenseDraft] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        guard let drafts = try? JSONDecoder().decode([WalletExpenseDraft].self, from: data) else {
            defaults.removeObject(forKey: storageKey)
            return []
        }
        return drafts
    }
}
