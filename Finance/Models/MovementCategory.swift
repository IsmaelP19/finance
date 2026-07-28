//
//  MovementCategory.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import Foundation
import SwiftUI
import SwiftData

/// Categoría de movimientos (ej: Alimentación, Nómina, Transporte).
@Model
final class MovementCategory {
    var id: UUID
    var name: String
    var iconRaw: String?
    var colorRaw: String?
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Movement.category)
    var movements: [Movement]?

    var icon: CategoryIcon {
        get { CategoryIcon(rawValue: iconRaw ?? "") ?? .tag }
        set { iconRaw = newValue.rawValue }
    }

    var iconName: String {
        icon.systemName
    }

    var categoryColor: CategoryColor {
        get { CategoryColor(rawValue: colorRaw ?? "") ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    var color: Color {
        categoryColor.color
    }

    init(
        name: String,
        icon: CategoryIcon = .tag,
        color: CategoryColor = .blue
    ) {
        self.id = UUID()
        self.name = name
        self.iconRaw = icon.rawValue
        self.colorRaw = color.rawValue
        self.createdAt = Date()
    }
}

enum CategoryIcon: String, CaseIterable, Identifiable, Codable {
    case tag
    case cart
    case forkKnife
    case car
    case house
    case bolt
    case tv
    case heart
    case cross
    case gameController
    case gift
    case plane
    case briefcase
    case graduationCap
    case chartBar
    case banknote
    case creditcard
    case wrench

    var id: String { rawValue }

    nonisolated var systemName: String {
        switch self {
        case .tag: return "tag.fill"
        case .cart: return "cart.fill"
        case .forkKnife: return "fork.knife"
        case .car: return "car.fill"
        case .house: return "house.fill"
        case .bolt: return "bolt.fill"
        case .tv: return "tv.fill"
        case .heart: return "heart.fill"
        case .cross: return "cross.case.fill"
        case .gameController: return "gamecontroller.fill"
        case .gift: return "gift.fill"
        case .plane: return "airplane"
        case .briefcase: return "briefcase.fill"
        case .graduationCap: return "graduationcap.fill"
        case .chartBar: return "chart.bar.fill"
        case .banknote: return "banknote.fill"
        case .creditcard: return "creditcard.fill"
        case .wrench: return "wrench.and.screwdriver.fill"
        }
    }
}

enum CategoryColor: String, CaseIterable, Identifiable, Codable {
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case pink
    case brown
    case gray

    var id: String { rawValue }

    nonisolated var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .pink: return .pink
        case .brown: return .brown
        case .gray: return .gray
        }
    }
}

// MARK: - Codable DTO para Export/Import JSON

struct MovementCategoryDTO: Codable {
    let id: UUID
    let name: String
    let icon: String
    let color: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case color
        case createdAt
    }

    init(from category: MovementCategory) {
        self.id = category.id
        self.name = category.name
        self.icon = category.iconRaw ?? CategoryIcon.tag.rawValue
        self.color = category.colorRaw ?? CategoryColor.blue.rawValue
        self.createdAt = category.createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? CategoryIcon.tag.rawValue
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? CategoryColor.blue.rawValue
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func toModel() -> MovementCategory {
        let category = MovementCategory(
            name: name,
            icon: CategoryIcon(rawValue: icon) ?? .tag,
            color: CategoryColor(rawValue: color) ?? .blue
        )
        category.id = id
        category.createdAt = createdAt
        return category
    }
}
