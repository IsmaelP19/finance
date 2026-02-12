//
//  AccountType.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Tipos de cuenta bancaria soportados por la aplicación.
enum AccountType: String, CaseIterable, Codable, Identifiable {
    case checking = "checking"
    case savings = "savings"
    case investment = "investment"
    case creditCard = "creditCard"
    case cash = "cash"

    var id: String { rawValue }

    /// Nombre localizado para mostrar en la UI.
    var displayName: String {
        switch self {
        case .checking:
            return "Cuenta corriente"
        case .savings:
            return "Cuenta de ahorro"
        case .investment:
            return "Inversión"
        case .creditCard:
            return "Tarjeta de crédito"
        case .cash:
            return "Efectivo"
        }
    }

    /// Icono SF Symbol asociado al tipo de cuenta.
    var icon: String {
        switch self {
        case .checking:
            return "building.columns"
        case .savings:
            return "banknote"
        case .investment:
            return "chart.line.uptrend.xyaxis"
        case .creditCard:
            return "creditcard"
        case .cash:
            return "dollarsign.circle"
        }
    }

    /// Color asociado al tipo de cuenta.
    var color: Color {
        switch self {
        case .checking:
            return .blue
        case .savings:
            return .green
        case .investment:
            return .purple
        case .creditCard:
            return .orange
        case .cash:
            return .teal
        }
    }
}
