//
//  BalanceByTypeCard.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Tarjeta que muestra el desglose del patrimonio por tipo de cuenta.
/// Solo muestra los tipos que tienen al menos una cuenta asociada.
struct BalanceByTypeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    let balancesByType: [(AccountType, Decimal, Int)]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Por tipo")
                        .font(.subheadline.weight(.semibold))
                    Text("Distribución del patrimonio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                FinanceGlassIconBadge(systemName: "square.grid.2x2.fill", tint: .indigo, size: 36)
            }

            if balancesByType.isEmpty {
                Text("Sin cuentas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(balancesByType, id: \.0) { type, balance, count in
                        HStack(spacing: 10) {
                            Image(systemName: type.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(type.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(type.displayName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                Text("\(count) \(count == 1 ? "cuenta" : "cuentas")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(balance.masked(hideBalances, code: currencyCode))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                        }
                        .padding(8)
                        .background(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.38), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .financeGlassColorCard(
            gradient: LinearGradient(
                colors: [
                    Color.indigo.opacity(colorScheme == .dark ? 0.28 : 0.18),
                    Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.11),
                    Color.purple.opacity(colorScheme == .dark ? 0.12 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            cornerRadius: FinanceGlassTokens.Radius.hero
        )
        .padding(.horizontal)
    }
}
