//
//  MovementQuickSelectorPill.swift
//  Finance
//
//  Created by OpenCode on 23/05/2026.
//

import SwiftUI

/// Label estable para menús desplegables de movimiento (cuenta, categoría, etc.).
struct MovementQuickSelectorPill: View, Equatable {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.08),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
        )
        .contentShape(Capsule())
    }
}

extension View {
    /// Área táctil completa del label de un `Menu` (evita que solo responda el chevron).
    func movementSelectorMenuLabel() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
}
