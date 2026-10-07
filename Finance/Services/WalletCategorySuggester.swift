//
//  WalletCategorySuggester.swift
//  Finance
//

import Foundation
import SwiftData

/// Suggests a category for a Wallet payment without loading anything at app launch.
enum WalletCategorySuggester {
    static let historyLimit = 400
    static let maximumModelCategories = 40

    @MainActor
    static func suggest(
        merchant: String?,
        in context: ModelContext,
        model: any WalletMerchantCategoryModeling = SystemWalletCategoryModel(),
        modelTimeout: Duration = .seconds(8)
    ) async -> MovementCategory? {
        guard let normalized = WalletCategoryMatcher.normalizedMerchant(merchant) else { return nil }
        let samples = (try? recentExpenseSamples(in: context)) ?? []
        if let categoryID = WalletCategoryMatcher.preferredCategoryID(
            forNormalizedMerchant: normalized,
            samples: samples
        ), let category = category(id: categoryID, in: context) {
            return category
        }

        let categories = (try? context.fetch(FetchDescriptor<MovementCategory>())) ?? []
        let allowed = allowedCategoryNames(from: categories)
        guard !allowed.isEmpty else { return nil }

        let displayMerchant = merchant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? normalized
        guard let suggestedName = await modelName(
            model: model,
            merchant: displayMerchant,
            allowedNames: allowed,
            timeout: modelTimeout
        ) else { return nil }

        let suggestedKey = WalletCategoryMatcher.normalizedMerchant(suggestedName)
        return categories.first {
            WalletCategoryMatcher.normalizedMerchant($0.name) == suggestedKey
        }
    }

    @MainActor
    private static func recentExpenseSamples(in context: ModelContext) throws -> [WalletExpenseCategorySample] {
        var descriptor = FetchDescriptor<Movement>(
            predicate: #Predicate { $0.typeRaw == "expense" },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = historyLimit
        return try context.fetch(descriptor).compactMap { movement in
            guard let category = movement.category else { return nil }
            return WalletExpenseCategorySample(
                concept: movement.concept,
                categoryID: category.id,
                occurredAt: movement.occurredAt
            )
        }
    }

    @MainActor
    private static func category(id: UUID, in context: ModelContext) -> MovementCategory? {
        var descriptor = FetchDescriptor<MovementCategory>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func allowedCategoryNames(from categories: [MovementCategory]) -> [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for category in categories {
            let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let key = WalletCategoryMatcher.normalizedMerchant(name), seen.insert(key).inserted else {
                continue
            }
            names.append(name)
            if names.count == maximumModelCategories { break }
        }
        return names
    }

    /// Leaves the main actor while the model runs and stops waiting after the timeout.
    private nonisolated static func modelName(
        model: any WalletMerchantCategoryModeling,
        merchant: String,
        allowedNames: [String],
        timeout: Duration
    ) async -> String? {
        await withTaskGroup(of: ModelRace.self) { group in
            group.addTask {
                let name = await model.categoryName(forMerchant: merchant, allowedNames: allowedNames)
                return .finished(name)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            if case .finished(let name) = first { return name }
            return nil
        }
    }

    private enum ModelRace: Sendable {
        case finished(String?)
        case timedOut
    }
}
