//
//  MovementAccountPickerPill.swift
//  Finance
//
//  Created by OpenCode on 23/05/2026.
//

import SwiftUI

/// Pill de cuenta sin chevron; muestra nombre de cuenta y banco.
struct MovementAccountPickerPill: View, Equatable {
    let accountName: String
    let bankName: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(accountName)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(bankName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
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
