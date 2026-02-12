//
//  TotalBalanceCard.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Tarjeta que muestra el patrimonio total (suma de todos los saldos).
struct TotalBalanceCard: View {
    let totalBalance: Decimal
    let accountCount: Int

    var body: some View {
        VStack(spacing: 8) {
            Text("Patrimonio total")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            Text(totalBalance.asCurrency())
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("\(accountCount) \(accountCount == 1 ? "cuenta" : "cuentas")")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                colors: [.blue, .blue.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
