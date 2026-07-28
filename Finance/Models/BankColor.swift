//
//  BankColor.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Colores predefinidos que el usuario puede asignar a un banco.
/// Almacenamos el rawValue (String) en SwiftData y lo convertimos a Color al mostrar.
enum BankColor: String, CaseIterable, Identifiable, Codable {
    case blue = "blue"
    case darkBlue = "darkBlue"
    case green = "green"
    case teal = "teal"
    case orange = "orange"
    case red = "red"
    case purple = "purple"
    case pink = "pink"
    case black = "black"
    case gray = "gray"
    case brown = "brown"
    case indigo = "indigo"

    var id: String { rawValue }

    /// Nombre legible para mostrar en la UI.
    var displayName: String {
        switch self {
        case .blue: return "Azul"
        case .darkBlue: return "Azul oscuro"
        case .green: return "Verde"
        case .teal: return "Turquesa"
        case .orange: return "Naranja"
        case .red: return "Rojo"
        case .purple: return "Morado"
        case .pink: return "Rosa"
        case .black: return "Negro"
        case .gray: return "Gris"
        case .brown: return "Marrón"
        case .indigo: return "Índigo"
        }
    }

    /// Color de SwiftUI correspondiente.
    nonisolated var color: Color {
        switch self {
        case .blue: return .blue
        case .darkBlue: return Color(red: 0.0, green: 0.2, blue: 0.5)
        case .green: return .green
        case .teal: return .teal
        case .orange: return .orange
        case .red: return .red
        case .purple: return .purple
        case .pink: return .pink
        case .black: return .black
        case .gray: return .gray
        case .brown: return .brown
        case .indigo: return .indigo
        }
    }
}
