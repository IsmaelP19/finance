//
//  AccountRowView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI

/// Fila que muestra un resumen de una cuenta bancaria en la lista principal.
/// El icono y color se toman del tipo de cuenta (corriente, ahorro, inversión, etc.).
struct AccountRowView: View {
    let account: BankAccount

    var body: some View {
        HStack(spacing: 12) {
            // Icono del tipo de cuenta
            Image(systemName: account.accountType.icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(account.accountType.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Nombre de la cuenta y banco
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(account.bankDisplayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Saldo
            Text(account.balance.asCurrency(code: account.currency))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(account.balance.isNegative ? .red : .primary)
        }
        .padding(.vertical, 4)
    }
}
