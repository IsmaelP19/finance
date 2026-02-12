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
    let balancesByType: [(AccountType, Decimal, Int)]

    var body: some View {
        VStack(spacing: 12) {
            Text("Patrimonio por tipo")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.bottom, 2)

            if balancesByType.isEmpty {
                Text("Sin cuentas")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
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
                                    .foregroundStyle(.white)
                                Text("\(count) \(count == 1 ? "cuenta" : "cuentas")")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }

                            Spacer()

                            Text(balance.asCurrency())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.15, blue: 0.25),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
