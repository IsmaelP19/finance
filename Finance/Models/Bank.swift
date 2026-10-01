//
//  Bank.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Entidad que representa un banco o entidad financiera.
/// El usuario crea y gestiona bancos desde la propia aplicación.
/// Cada banco tiene un nombre, icono y color que lo identifican visualmente.
@Model
final class Bank {
    var id: UUID
    var name: String
    var iconRaw: String
    var colorRaw: String
    var createdAt: Date

    /// Relación inversa: cuentas asociadas a este banco.
    @Relationship(deleteRule: .nullify, inverse: \BankAccount.bank)
    var accounts: [BankAccount]?

    /// Icono del banco (wrapper tipado sobre iconRaw).
    var icon: BankIcon {
        get { BankIcon(rawValue: iconRaw) ?? .buildingColumns }
        set { iconRaw = newValue.rawValue }
    }

    /// Color del banco (wrapper tipado sobre colorRaw).
    var bankColor: BankColor {
        get { BankColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    /// Color de SwiftUI para usar directamente en las vistas.
    var color: Color {
        bankColor.color
    }

    /// Nombre del SF Symbol para usar en Image(systemName:).
    var iconName: String {
        icon.systemName
    }

    init(
        name: String,
        icon: BankIcon = .buildingColumns,
        bankColor: BankColor = .blue
    ) {
        self.id = UUID()
        self.name = name
        self.iconRaw = icon.rawValue
        self.colorRaw = bankColor.rawValue
        self.createdAt = Date()
    }
}

// MARK: - Codable DTO para Export/Import JSON

nonisolated struct BankDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let icon: String
    let color: String
    let createdAt: Date

    init(from bank: Bank) {
        self.id = bank.id
        self.name = bank.name
        self.icon = bank.iconRaw
        self.color = bank.colorRaw
        self.createdAt = bank.createdAt
    }

    func toModel() -> Bank {
        let bank = Bank(
            name: name,
            icon: BankIcon(rawValue: icon) ?? .buildingColumns,
            bankColor: BankColor(rawValue: color) ?? .blue
        )
        bank.id = id
        bank.createdAt = createdAt
        return bank
    }
}
