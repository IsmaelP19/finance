//
//  CategoryChipView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI

/// Chip visual para mostrar categorías con icono y color.
struct CategoryChipView: View {
    let name: String
    let iconName: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.caption)
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
    }
}
