//
//  MovementCategoryEntity.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import AppIntents
import SwiftData
import Foundation

/// AppEntity wrapper for MovementCategory, used by AppIntents (Shortcuts / Siri).
struct MovementCategoryEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Categoría")

    static let defaultQuery = MovementCategoryEntityQuery()

    var id: UUID
    var name: String
    var iconName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            image: .init(systemName: iconName)
        )
    }

    init(id: UUID, name: String, iconName: String) {
        self.id = id
        self.name = name
        self.iconName = iconName
    }

    init(from category: MovementCategory) {
        self.id = category.id
        self.name = category.name
        self.iconName = category.iconName
    }
}

struct MovementCategoryEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [MovementCategoryEntity] {
        guard !identifiers.isEmpty else { return [] }

        let container = FinanceModelContainerProvider.shared
        let context = ModelContext(container)
        let identifierValues = identifiers

        let descriptor = FetchDescriptor<MovementCategory>(
            predicate: #Predicate<MovementCategory> { category in
                identifierValues.contains(category.id)
            },
            sortBy: [SortDescriptor(\.name), SortDescriptor(\.id)]
        )
        let categories = try context.fetch(descriptor)

        return categories.map { MovementCategoryEntity(from: $0) }
    }

    func suggestedEntities() async throws -> [MovementCategoryEntity] {
        let container = FinanceModelContainerProvider.shared
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<MovementCategory>(
            sortBy: [SortDescriptor(\.name), SortDescriptor(\.id)]
        )
        let categories = try context.fetch(descriptor)

        return categories.map { MovementCategoryEntity(from: $0) }
    }
}
