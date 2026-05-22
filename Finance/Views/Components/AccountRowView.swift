//
//  AccountRowView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Fila que muestra un resumen de una cuenta bancaria en la lista principal.
/// El icono combina banco y tipo para evitar filas monótonas.
struct AccountRowView: View {
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    let account: BankAccount

    private var accent: Color { account.bank?.color ?? account.accountType.color }
    private var iconName: String { account.bank?.iconName ?? account.accountType.icon }

    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        LinearGradient(
                            colors: [accent, account.accountType.color.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                Image(systemName: account.accountType.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(account.accountType.color)
                    .frame(width: 18, height: 18)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(account.bankDisplayName)
                        .lineLimit(1)
                    Text("•")
                    Text(account.accountType.displayName)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(account.balance.masked(hideBalances))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(account.balance.isNegative ? .red : .primary)
                Text("Saldo")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .financeElevatedRow(cornerRadius: 18)
        .padding(.vertical, 2)
    }
}
