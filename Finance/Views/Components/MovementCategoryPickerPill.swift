//
//  MovementCategoryPickerPill.swift
//  Finance
//
//  Created by OpenCode on 23/05/2026.
//

import SwiftUI

/// Pill de categoría sin chevron; abre el selector a pantalla completa al pulsar.
struct MovementCategoryPickerPill: View, Equatable {
    let title: String
    let iconName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint, in: Circle())

            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
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
