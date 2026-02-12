//
//  BankIcon.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import Foundation

/// Iconos SF Symbol disponibles para asignar a un banco.
/// El usuario elige uno al crear o editar un banco.
enum BankIcon: String, CaseIterable, Identifiable, Codable {
    case buildingColumns = "building.columns.fill"
    case building2 = "building.2.fill"
    case buildingStorefront = "building.fill"
    case creditcard = "creditcard.fill"
    case banknote = "banknote.fill"
    case iphone = "iphone.gen3"
    case chartLine = "chart.line.uptrend.xyaxis"
    case chartPie = "chart.pie.fill"
    case dollarsign = "dollarsign.circle.fill"
    case euroSign = "eurosign.circle.fill"
    case wallet = "wallet.bifold.fill"
    case shieldCheck = "checkmark.shield.fill"
    case globe = "globe"
    case star = "star.fill"
    case leaf = "leaf.fill"
    case bolt = "bolt.fill"

    var id: String { rawValue }

    /// Nombre del SF Symbol para usar en Image(systemName:).
    var systemName: String { rawValue }
}
