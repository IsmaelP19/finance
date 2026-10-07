//
//  SystemWalletCategoryModel.swift
//  Finance
//

import Foundation
import FoundationModels

/// One-shot classifier that uses the on-device system model.
/// A session is created only for a new merchant and is not retained.
struct SystemWalletCategoryModel: WalletMerchantCategoryModeling {
    func categoryName(forMerchant merchant: String, allowedNames: [String]) async -> String? {
        guard !allowedNames.isEmpty else { return nil }
        let systemModel = SystemLanguageModel.default
        guard case .available = systemModel.availability else { return nil }

        let session = LanguageModelSession(instructions: """
        Clasificas un pago en una categoría que ya existe. \
        Respondes con un nombre de la lista o con un nombre vacío si ninguna encaja.
        """)
        let list = allowedNames.joined(separator: "\n")
        let prompt = """
        Comercio: \(merchant)
        Categorías permitidas:
        \(list)
        """

        do {
            let response = try await session.respond(
                to: prompt,
                generating: WalletCategoryChoice.self
            )
            let name = response.content.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : name
        } catch {
            return nil
        }
    }
}

@Generable
struct WalletCategoryChoice {
    @Guide(description: "Nombre exacto de una categoría permitida, o vacío si ninguna encaja")
    var name: String
}
