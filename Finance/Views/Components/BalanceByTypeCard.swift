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
        VStack(spacing: 12) {
            Text("Patrimonio por tipo")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            if balancesByType.isEmpty {
                Text("Sin cuentas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(balancesByType, id: \.0) { type, balance, count in
                        HStack(spacing: 10) {
                            Image(systemName: type.icon)
                                .font(.body)
                                .foregroundStyle(type.color)
                                .frame(width: 24)

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
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .financeGlassColorCard(
            gradient: LinearGradient(
                colors: [
                    Color.indigo.opacity(colorScheme == .dark ? 0.22 : 0.15),
                    Color.blue.opacity(colorScheme == .dark ? 0.14 : 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            cornerRadius: 20
        )
        .padding(.horizontal)
    }
}
