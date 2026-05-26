//
//  AccountRowView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Fila que muestra un resumen de una cuenta bancaria en la lista principal.
/// Mantiene el lenguaje visual de las opciones de Ajustes.
struct AccountRowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    let account: BankAccount

    private var accent: Color { account.bank?.color ?? account.accountType.color }
    private var iconName: String { account.bank?.iconName ?? account.accountType.icon }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(account.bankDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                Text(account.balance.masked(hideBalances))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(account.balance.isNegative ? .red : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Saldo")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var rowBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }
}
