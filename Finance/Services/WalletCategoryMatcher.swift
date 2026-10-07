//
//  WalletCategoryMatcher.swift
//  Finance
//

import Foundation

/// A past expense used to reuse a category for the same merchant.
struct WalletExpenseCategorySample: Equatable, Sendable {
    var concept: String
    var categoryID: UUID
    var occurredAt: Date
}

/// Matches a Wallet merchant to a category the user already chose.
enum WalletCategoryMatcher {
    /// Folds case, accents and punctuation so repeated Wallet names compare equal.
    static func normalizedMerchant(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let folded = raw.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "es")
        )
        let separated = String(folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        })
        let collapsed = separated.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Uses the newest categorized expense for this merchant.
    static func preferredCategoryID(
        forNormalizedMerchant merchant: String,
        samples: [WalletExpenseCategorySample]
    ) -> UUID? {
        samples
            .filter { normalizedMerchant($0.concept) == merchant }
            .max { $0.occurredAt < $1.occurredAt }?
            .categoryID
    }
}

/// Picks one of the user's category names. Implementations must not run at app launch.
protocol WalletMerchantCategoryModeling: Sendable {
    func categoryName(forMerchant merchant: String, allowedNames: [String]) async -> String?
}
