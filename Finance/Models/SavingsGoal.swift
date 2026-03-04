//
//  SavingsGoal.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import Foundation
import SwiftUI
import SwiftData

/// Objetivo de ahorro vinculado a una cuenta bancaria.
/// El progreso es automático: se calcula como el saldo actual de `account`
/// dividido entre `targetAmount`.
@Model
final class SavingsGoal {
    var id: UUID
    var name: String
    /// Importe objetivo a alcanzar.
    var targetAmount: Decimal
    /// Fecha límite opcional.
    var targetDate: Date?
    /// SF Symbol name para el icono.
    var iconName: String
    /// Raw value de `SavingsGoalColor`.
    var colorRaw: String
    /// Marcado manualmente como completado aunque el saldo no haya llegado.
    var isCompleted: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Cuenta cuyo saldo representa el progreso.
    @Relationship(deleteRule: .nullify)
    var account: BankAccount?

    var color: Color {
        SavingsGoalColor(rawValue: colorRaw)?.color ?? .blue
    }

    init(
        name: String,
        targetAmount: Decimal,
        targetDate: Date? = nil,
        iconName: String = "star.fill",
        colorRaw: String = SavingsGoalColor.blue.rawValue,
        account: BankAccount? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.iconName = iconName
        self.colorRaw = colorRaw
        self.account = account
        self.isCompleted = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - SavingsGoalColor

enum SavingsGoalColor: String, CaseIterable, Identifiable {
    case blue, green, orange, purple, pink, teal, red, yellow

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink:   return .pink
        case .teal:   return .teal
        case .red:    return .red
        case .yellow: return .yellow
        }
    }

    var displayName: String {
        switch self {
        case .blue:   return "Azul"
        case .green:  return "Verde"
        case .orange: return "Naranja"
        case .purple: return "Morado"
        case .pink:   return "Rosa"
        case .teal:   return "Verde azulado"
        case .red:    return "Rojo"
        case .yellow: return "Amarillo"
        }
    }
}
