//
//  AccountDetailView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Pantalla de detalle de una cuenta bancaria.
/// Muestra toda la información y permite editar o eliminar la cuenta.
struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @Bindable var account: BankAccount

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            // Cabecera con icono del tipo de cuenta y saldo
            Section {
                VStack(spacing: 12) {
                    Image(systemName: account.accountType.icon)
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(account.accountType.color)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    Text(account.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(account.bankDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(account.balance.asCurrency())
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(account.balance.isNegative ? .red : .primary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }

            // Información detallada
            Section("Detalles") {
                DetailRow(label: "Banco", value: account.bankDisplayName)
                DetailRow(label: "Tipo", value: account.accountType.displayName)
                DetailRow(label: "Moneda", value: appCurrencyCode)
                DetailRow(
                    label: "Creada",
                    value: account.createdAt.asSpanishDateTime()
                )
                DetailRow(
                    label: "Última actualización",
                    value: account.updatedAt.asSpanishDateTime()
                )
            }

            // Notas
            if !account.notes.isEmpty {
                Section("Notas") {
                    Text(account.notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            // Acciones
            Section {
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Editar cuenta", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Eliminar cuenta", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditSheet) {
            AddAccountView(existingAccount: account)
        }
        .confirmationDialog(
            "¿Eliminar cuenta?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                modelContext.delete(account)
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminará la cuenta \"\(account.name)\" permanentemente. Esta acción no se puede deshacer.")
        }
    }
}

// MARK: - Componente auxiliar

/// Fila de detalle con etiqueta y valor.
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}
