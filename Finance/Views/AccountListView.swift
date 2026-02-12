//
//  AccountListView.swift
//  Finance
//
//  Created by Ismael Perez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Pantalla principal de la aplicacion.
/// Muestra el patrimonio total y la lista de cuentas agrupadas por tipo.
struct AccountListView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]

    @State private var showingAddAccount = false
    @State private var editingAccount: BankAccount?
    @State private var pendingAccountsDeletion: [BankAccount] = []
    @State private var showingDeleteConfirmation = false

    private var totalBalance: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    private var balancesByType: [(AccountType, Decimal, Int)] {
        let grouped = Dictionary(grouping: accounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let typeAccounts = grouped[type], !typeAccounts.isEmpty else { return nil }
            let total = typeAccounts.reduce(Decimal(0)) { $0 + $1.balance }
            return (type, total, typeAccounts.count)
        }
    }

    private var groupedAccounts: [(AccountType, [BankAccount])] {
        let grouped = Dictionary(grouping: accounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let typeAccounts = grouped[type], !typeAccounts.isEmpty else { return nil }
            return (type, typeAccounts)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TabView {
                        TotalBalanceCard(
                            totalBalance: totalBalance,
                            accountCount: accounts.count,
                            currencyCode: appCurrencyCode
                        )

                        BalanceByTypeCard(
                            balancesByType: balancesByType,
                            currencyCode: appCurrencyCode
                        )
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .frame(height: max(150, CGFloat(balancesByType.count) * 38 + 80))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if accounts.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Sin cuentas",
                            systemImage: "building.columns",
                            description: Text("Pulsa + para anadir tu primera cuenta bancaria")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groupedAccounts, id: \.0) { type, typeAccounts in
                        Section(header: Text(type.displayName)) {
                            ForEach(typeAccounts, id: \.id) { account in
                                NavigationLink(destination: AccountDetailView(account: account)) {
                                    AccountRowView(account: account)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        editingAccount = account
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .onDelete { offsets in
                                requestDeleteAccounts(from: typeAccounts, at: offsets)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Finance")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                AddAccountView()
            }
            .sheet(item: $editingAccount) { (account: BankAccount) in
                AddAccountView(existingAccount: account)
            }
            .confirmationDialog(
                "Eliminar cuenta",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancelar", role: .cancel) {
                    pendingAccountsDeletion = []
                }
                Button("Eliminar", role: .destructive) {
                    deletePendingAccounts()
                }
            } message: {
                if pendingAccountsDeletion.count == 1 {
                    if let name = pendingAccountsDeletion.first?.name {
                        Text("Se eliminará la cuenta \(name). Esta acción no se puede deshacer.")
                    } else {
                        Text("Se eliminará una cuenta. Esta acción no se puede deshacer.")
                    }
                } else {
                    Text("Se eliminarán \(pendingAccountsDeletion.count) cuentas. Esta acción no se puede deshacer.")
                }
            }
        }
    }

    private func requestDeleteAccounts(from typeAccounts: [BankAccount], at offsets: IndexSet) {
        pendingAccountsDeletion = offsets.map { typeAccounts[$0] }
        if !pendingAccountsDeletion.isEmpty {
            showingDeleteConfirmation = true
        }
    }

    private func deletePendingAccounts() {
        withAnimation {
            for account in pendingAccountsDeletion {
                modelContext.delete(account)
            }
        }
        pendingAccountsDeletion = []
    }
}

/// Wrapper de UIActivityViewController para compartir archivos desde SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

