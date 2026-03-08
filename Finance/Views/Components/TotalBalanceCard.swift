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

    var body: some View {
        VStack(spacing: 8) {
            Text("Patrimonio total")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(totalBalance.masked(hideBalances, code: currencyCode))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("\(accountCount) \(accountCount == 1 ? "cuenta" : "cuentas")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .financeGlassColorCard(
            gradient: LinearGradient(
                colors: [
                    Color.blue.opacity(colorScheme == .dark ? 0.28 : 0.18),
                    Color.indigo.opacity(colorScheme == .dark ? 0.20 : 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            cornerRadius: 20
        )
        .padding(.horizontal)
    }
}
