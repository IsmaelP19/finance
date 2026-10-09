//
//  MovementCategory.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

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

    var emoji: String? {
        get { CategoryIcon.emoji(from: iconRaw) }
        set {
            if let newValue, CategoryIcon.isValidEmoji(newValue) {
                iconRaw = CategoryIcon.emojiPrefix + newValue
            } else {
                iconRaw = CategoryIcon.tag.rawValue
            }
        }
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
    nonisolated static let emojiPrefix = "emoji:"

    case tag
    case cart
    case forkKnife
    case car
    case house
    case bolt
    case tv
    case phone
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
    case wifi
    case headphones
    case desktopComputer
    case laptopComputer
    case camera
    case book
    case bag
    case bicycle
    case bus
    case train
    case fuelpump
    case pawprint
    case leaf
    case cup
    case birthdayCake
    case musicNote
    case paintbrush
    case scissors
    case stethoscope
    case building
    case shippingbox
    case ticket
    case dumbbell

    var id: String { rawValue }

    nonisolated var systemName: String {
        switch self {
        case .tag: return "tag"
        case .cart: return "cart"
        case .forkKnife: return "fork.knife"
        case .car: return "car"
        case .house: return "house"
        case .bolt: return "bolt"
        case .tv: return "tv"
        case .heart: return "heart"
        case .cross: return "cross.case"
        case .gameController: return "gamecontroller"
        case .gift: return "gift"
        case .plane: return "airplane"
        case .briefcase: return "briefcase"
        case .graduationCap: return "graduationcap"
        case .chartBar: return "chart.bar"
        case .banknote: return "banknote"
        case .creditcard: return "creditcard"
        case .wrench: return "wrench.and.screwdriver"
        case .phone: return "iphone"
        case .wifi: return "wifi"
        case .headphones: return "headphones"
        case .desktopComputer: return "desktopcomputer"
        case .laptopComputer: return "laptopcomputer"
        case .camera: return "camera"
        case .book: return "book"
        case .bag: return "bag"
        case .bicycle: return "bicycle"
        case .bus: return "bus"
        case .train: return "tram"
        case .fuelpump: return "fuelpump"
        case .pawprint: return "pawprint"
        case .leaf: return "leaf"
        case .cup: return "cup.and.saucer"
        case .birthdayCake: return "birthday.cake"
        case .musicNote: return "music.note"
        case .paintbrush: return "paintbrush"
        case .scissors: return "scissors"
        case .stethoscope: return "stethoscope"
        case .building: return "building.2"
        case .shippingbox: return "shippingbox"
        case .ticket: return "ticket"
        case .dumbbell: return "dumbbell"
        }
    }

    nonisolated static func emoji(from raw: String?) -> String? {
        guard let raw, raw.hasPrefix(emojiPrefix) else { return nil }
        let value = String(raw.dropFirst(emojiPrefix.count))
        return isValidEmoji(value) ? value : nil
    }

    nonisolated static func isValidEmoji(_ value: String) -> Bool {
        guard value.count == 1 else { return false }
        return value.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0xFE0F
        }
    }
}

/// Muestra el glifo de una categoría con el mismo dato persistido para toda la app.
struct CategoryIconView: View {
    let iconRaw: String?
    let color: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let emoji = CategoryIcon.emoji(from: iconRaw) {
                Text(emoji)
                    .font(.system(size: size * 0.55))
            } else {
                Image(systemName: CategoryIcon(rawValue: iconRaw ?? "")?.systemName ?? CategoryIcon.tag.systemName)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(color, in: RoundedRectangle(cornerRadius: size * 0.24))
        .accessibilityHidden(true)
    }
}

extension Color {
    /// Aclara el acento cuando se usa como trazo o texto sobre una superficie oscura.
    func categoryForegroundColor(in colorScheme: ColorScheme) -> Color {
        guard colorScheme == .dark else { return self }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return self }
        let whiteBlend: CGFloat = 0.4
        return Color(
            red: Double(red * (1 - whiteBlend) + whiteBlend),
            green: Double(green * (1 - whiteBlend) + whiteBlend),
            blue: Double(blue * (1 - whiteBlend) + whiteBlend)
        )
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
    case purple
    case magenta
    case rose
    case coral
    case amber
    case lime
    case olive
    case forest
    case navy
    case sky
    case slate
    case plum

    var id: String { rawValue }

    nonisolated var color: Color {
        switch self {
        case .red: return Color(red: 0.76, green: 0.18, blue: 0.23)
        case .orange: return Color(red: 0.68, green: 0.31, blue: 0.05)
        case .yellow: return Color(red: 0.50, green: 0.38, blue: 0.00)
        case .green: return Color(red: 0.13, green: 0.45, blue: 0.23)
        case .mint: return Color(red: 0.00, green: 0.45, blue: 0.38)
        case .teal: return Color(red: 0.00, green: 0.39, blue: 0.43)
        case .cyan: return Color(red: 0.00, green: 0.42, blue: 0.55)
        case .blue: return Color(red: 0.08, green: 0.37, blue: 0.67)
        case .indigo: return Color(red: 0.29, green: 0.30, blue: 0.65)
        case .pink: return Color(red: 0.68, green: 0.15, blue: 0.36)
        case .brown: return Color(red: 0.45, green: 0.30, blue: 0.22)
        case .gray: return Color(red: 0.36, green: 0.39, blue: 0.43)
        case .purple: return Color(red: 0.41, green: 0.25, blue: 0.61)
        case .magenta: return Color(red: 0.57, green: 0.18, blue: 0.49)
        case .rose: return Color(red: 0.61, green: 0.23, blue: 0.33)
        case .coral: return Color(red: 0.64, green: 0.25, blue: 0.20)
        case .amber: return Color(red: 0.56, green: 0.34, blue: 0.00)
        case .lime: return Color(red: 0.33, green: 0.43, blue: 0.06)
        case .olive: return Color(red: 0.35, green: 0.39, blue: 0.13)
        case .forest: return Color(red: 0.05, green: 0.38, blue: 0.28)
        case .navy: return Color(red: 0.18, green: 0.29, blue: 0.51)
        case .sky: return Color(red: 0.18, green: 0.39, blue: 0.57)
        case .slate: return Color(red: 0.26, green: 0.35, blue: 0.43)
        case .plum: return Color(red: 0.42, green: 0.22, blue: 0.43)
        }
    }
}

// MARK: - Codable DTO para Export/Import JSON

nonisolated struct MovementCategoryDTO: Codable, Sendable {
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
        if CategoryIcon.emoji(from: icon) != nil {
            category.iconRaw = icon
        }
        category.createdAt = createdAt
        return category
    }
}
