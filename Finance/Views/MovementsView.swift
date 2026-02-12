//
//  MovementsView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData

/// Pantalla principal de movimientos (gastos e ingresos).
struct MovementsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]

    @State private var showingAddMovement = false
    @State private var showingEditMovement = false
    @State private var movementToEdit: Movement?
    @State private var selectedAccountFilterID: UUID?

    private var filteredMovements: [Movement] {
        guard let selectedAccountFilterID else { return movements }
        return movements.filter { $0.account?.id == selectedAccountFilterID }
    }

    private var totalIncome: Decimal {
        filteredMovements
            .filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var totalExpense: Decimal {
        filteredMovements
            .filter { $0.type == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var netBalance: Decimal {
        totalIncome - totalExpense
    }

    private var movementCount: Int {
        filteredMovements.count
    }

    var body: some View {
        NavigationStack {
            List {
                if !accounts.isEmpty {
                    Section {
                        Picker("Cuenta", selection: $selectedAccountFilterID) {
                            Text("Todas las cuentas")
                                .tag(nil as UUID?)

                            ForEach(accounts, id: \.id) { account in
                                Text("\(account.name) · \(account.bankDisplayName)")
                                    .tag(Optional(account.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if !movements.isEmpty {
                    Section {
                        MovementSummaryView(
                            totalIncome: totalIncome,
                            totalExpense: totalExpense,
                            netBalance: netBalance,
                            movementCount: movementCount,
                            currencyCode: appCurrencyCode
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                if movements.isEmpty {
                    ContentUnavailableView(
                        accounts.isEmpty ? "Sin cuentas" : "Sin movimientos",
                        systemImage: accounts.isEmpty ? "building.columns" : "arrow.left.arrow.right.circle",
                        description: Text(accounts.isEmpty
                                          ? "Crea al menos una cuenta en Inicio para registrar movimientos"
                                          : "Pulsa + para registrar tu primer gasto o ingreso")
                    )
                    .listRowBackground(Color.clear)
                } else if filteredMovements.isEmpty {
                    ContentUnavailableView(
                        "Sin movimientos en esta cuenta",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Cambia el filtro para ver movimientos de otras cuentas")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredMovements, id: \.id) { movement in
                        MovementRowView(movement: movement, currencyCode: appCurrencyCode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                movementToEdit = movement
                                showingEditMovement = true
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    movementToEdit = movement
                                    showingEditMovement = true
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                    .onDelete(perform: deleteMovements)
                }
            }
            .navigationTitle("Movimientos")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddMovement = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddMovement) {
                AddMovementView()
            }
            .sheet(isPresented: $showingEditMovement, onDismiss: {
                movementToEdit = nil
            }) {
                if let movementToEdit {
                    AddMovementView(movementToEdit: movementToEdit)
                }
            }
        }
    }

    private func deleteMovements(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let movement = filteredMovements[index]
                if let account = movement.account {
                    account.balance -= movement.signedAmount
                    account.updatedAt = Date()
                }
                modelContext.delete(movement)
            }
        }
    }
}

private struct MovementSummaryView: View {
    let totalIncome: Decimal
    let totalExpense: Decimal
    let netBalance: Decimal
    let movementCount: Int
    let currencyCode: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SummaryPill(title: "Ingresos", value: totalIncome.asCurrency(code: currencyCode), color: .green)
                SummaryPill(title: "Gastos", value: totalExpense.asCurrency(code: currencyCode), color: .red)
            }

            HStack {
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(netBalance.asCurrency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(netBalance >= 0 ? .green : .red)
            }

            HStack {
                Text("Movimientos")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(movementCount)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct MovementRowView: View {
    let movement: Movement
    let currencyCode: String

    private var accountAndBankText: String {
        let accountName = movement.account?.name ?? "Sin cuenta"
        let bankName = movement.account?.bankDisplayName ?? "Sin banco"
        return "\(accountName) · \(bankName)"
    }

    private var balanceAfterText: String? {
        guard let resultingBalance = movement.resultingBalance else { return nil }
        return "Saldo: \(resultingBalance.asCurrency(code: currencyCode))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: movement.type.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(movement.type.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(movement.concept)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                CategoryChipView(
                    name: movement.category?.name ?? "Sin categoría",
                    iconName: movement.category?.iconName ?? "tag",
                    color: movement.category?.color ?? .secondary
                )

                Text(accountAndBankText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let balanceAfterText {
                    Text(balanceAfterText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(movement.signedAmount.asCurrency(code: currencyCode))
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(movement.type.color)

                Text(movement.occurredAt.asSpanishShortDate())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
