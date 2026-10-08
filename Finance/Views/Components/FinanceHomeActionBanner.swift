//
//  FinanceHomeActionBanner.swift
//  Finance
//

import SwiftUI

struct FinanceHomeActionBanner: View {
    let title: String
    let value: String?
    let subtitle: String?
    let systemImage: String
    let pillText: String
    let tint: Color
    let showsChevron: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let value {
                        Text(value)
                            .font(.title3.weight(.medium))
                            .tracking(-0.25)
                            .foregroundStyle(.primary)
                    }

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    Text(pillText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tint, in: Capsule())

                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.financeHomeSurface, in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                    .strokeBorder(Color.financeHomeStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
