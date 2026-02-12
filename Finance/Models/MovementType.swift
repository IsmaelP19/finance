//
//  MovementType.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import Foundation

/// Tipo de movimiento financiero.
enum MovementType: String, CaseIterable, Codable, Identifiable {
    case expense = "expense"
    case income = "income"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expense:
            return "Gasto"
        case .income:
            return "Ingreso"
        }
    }

    var icon: String {
        switch self {
        case .expense:
            return "arrow.down.circle.fill"
        case .income:
            return "arrow.up.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .expense:
            return .red
        case .income:
            return .green
        }
    }

    /// Multiplicador para aplicar el signo del movimiento al saldo.
    var signMultiplier: Decimal {
        switch self {
        case .expense:
            return -1
        case .income:
            return 1
        }
    }
}
