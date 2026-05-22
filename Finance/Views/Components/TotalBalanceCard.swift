//
//  TotalBalanceCard.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Tarjeta que muestra el patrimonio total (suma de todos los saldos).
struct TotalBalanceCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    let totalBalance: Decimal
    let accountCount: Int
    let currencyCode: String
    var title: String = "Patrimonio"
    var subtitle: String = "Vista global de tus cuentas"
    var systemImage: String = "building.columns"
    var tint: Color = .indigo
    var horizontalPadding: Bool = true

    private var accountCountText: String {
        "\(accountCount) \(accountCount == 1 ? "cuenta conectada" : "cuentas conectadas")"
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.indigo.opacity(colorScheme == .dark ? 0.30 : 0.18),
                Color.blue.opacity(colorScheme == .dark ? 0.20 : 0.12),
                Color.teal.opacity(colorScheme == .dark ? 0.14 : 0.09)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                FinanceGlassIconBadge(systemName: systemImage, tint: tint, size: 38)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(totalBalance.masked(hideBalances, code: currencyCode))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(.primary)

                Label(accountCountText, systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .financeGlassColorCard(
            gradient: cardGradient,
            cornerRadius: FinanceGlassTokens.Radius.hero
        )
        .padding(.horizontal, horizontalPadding ? 16 : 0)
    }
}
