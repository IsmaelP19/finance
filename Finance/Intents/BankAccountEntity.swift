//
//  BankAccountEntity.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import AppIntents
import SwiftData
import Foundation

/// AppEntity wrapper for BankAccount, used by AppIntents (Shortcuts / Siri).
struct BankAccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Cuenta bancaria")

    static let defaultQuery = BankAccountEntityQuery()

    var id: UUID
    var name: String
    var bankName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(bankName)",
            image: .init(systemName: "building.columns")
        )
    }

    init(id: UUID, name: String, bankName: String) {
        self.id = id
        self.name = name
        self.bankName = bankName
    }

    init(from account: BankAccount) {
        self.id = account.id
        self.name = account.name
        self.bankName = account.bankDisplayName
    }
}

struct BankAccountEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BankAccountEntity] {
        let container = FinanceModelContainerProvider.shared
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<BankAccount>(
            sortBy: [SortDescriptor(\.name)]
        )
        let accounts = try context.fetch(descriptor)

        let identifierSet = Set(identifiers)
        return accounts
            .filter { identifierSet.contains($0.id) && $0.isActive }
            .map { BankAccountEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [BankAccountEntity] {
        let container = FinanceModelContainerProvider.shared
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<BankAccount>(
            sortBy: [SortDescriptor(\.name)]
        )
        let accounts = try context.fetch(descriptor)

        return accounts
            .filter(\.isActive)
            .map { BankAccountEntity(from: $0) }
    }
}
