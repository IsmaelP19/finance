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
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]

    @State private var showingAddAccount = false
    @State private var editingAccount: BankAccount?
    @State private var pendingAccountsDeletion: [BankAccount] = []
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var navigationPath = NavigationPath()

    private var totalBalance: Decimal {
        activeAccounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    private var activeAccounts: [BankAccount] {
        accounts.filter(\.isActive)
    }

    private var balancesByType: [(AccountType, Decimal, Int)] {
        let grouped = Dictionary(grouping: activeAccounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let typeAccounts = grouped[type], !typeAccounts.isEmpty else { return nil }
            let total = typeAccounts.reduce(Decimal(0)) { $0 + $1.balance }
            return (type, total, typeAccounts.count)
        }
    }

    private var groupedAccounts: [(AccountType, [BankAccount])] {
        let grouped = Dictionary(grouping: activeAccounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let typeAccounts = grouped[type], !typeAccounts.isEmpty else { return nil }
            return (type, typeAccounts)
        }
    }

    private var investmentAccounts: [BankAccount] {
        activeAccounts.filter { $0.accountType == .investment }
    }

    private var totalInvestedInInvestments: Decimal {
        investmentAccounts.reduce(Decimal(0)) { $0 + $1.effectiveInvestedAmount }
    }

    private var totalMarketValueInInvestments: Decimal {
        investmentAccounts.reduce(Decimal(0)) { $0 + $1.effectiveMarketValue }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section {
                    VStack(spacing: 14) {
                        TotalBalanceCard(
                            totalBalance: totalBalance,
                            accountCount: activeAccounts.count,
                            currencyCode: appCurrencyCode
                        )

                        AccountTypeStrip(balancesByType: balancesByType, currencyCode: appCurrencyCode)

                        if !investmentAccounts.isEmpty {
                            InvestmentPerformanceCard(
                                totalInvested: totalInvestedInInvestments,
                                totalMarketValue: totalMarketValueInInvestments,
                                currencyCode: appCurrencyCode
                            )
                        }
                    }
                    .financeGlassHeroListRow(insets: EdgeInsets(top: 10, leading: 0, bottom: 8, trailing: 0))
                }

                if activeAccounts.isEmpty {
                    Section {
                        FinanceEmptyStateContent(
                            "Sin cuentas",
                            systemImage: "building.columns",
                            description: Text("Pulsa + para anadir tu primera cuenta bancaria")
                        )
                        .financeGlassCenteredEmptyListRow(minHeight: 420)
                    }
                } else {
                    ForEach(groupedAccounts, id: \.0) { type, typeAccounts in
                        FinanceGlassSectionHeader(
                            title: type.displayName,
                            systemImage: type.icon,
                            subtitle: typeAccounts.count == 1 ? "1 cuenta" : "\(typeAccounts.count) cuentas",
                            tint: type.color
                        )
                        .financeGlassClearListRow(insets: EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16))
                        .accessibilityElement(children: .combine)

                        ForEach(typeAccounts, id: \.id) { account in
                            Button {
                                navigationPath.append(account.id)
                            } label: {
                                AccountRowView(account: account)
                            }
                            .buttonStyle(.plain)
                            .financeGlassClearListRow(insets: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    editingAccount = account
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.financeAccent)
                            }
                        }
                        .onDelete { offsets in
                            requestDeleteAccounts(from: typeAccounts, at: offsets)
                        }
                    }
                }
            }
            .financeGlassListContainer()
            .navigationTitle("Cuentas")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        hideBalances.toggle()
                    } label: {
                        Image(systemName: hideBalances ? "eye.slash" : "eye")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Añadir cuenta")
                }
            }
            .navigationDestination(for: UUID.self) { accountID in
                if let account = accounts.first(where: { $0.id == accountID }) {
                    AccountDetailView(account: account)
                } else {
                    FinanceEmptyStateContent(
                        "Cuenta no disponible",
                        systemImage: "building.columns",
                        description: Text("La cuenta seleccionada ya no está disponible")
                    )
                    .financeGlassPageBackground()
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
                    Text("La cuenta se ocultará permanentemente de Mis cuentas y dejará de aparecer en filtros y selectores. Sus movimientos se conservarán como histórico: seguirán visibles por mes y búsqueda, pero no podrás filtrarlos por cuenta ni editarlos o eliminarlos. Si hay reembolsos pendientes, podrás registrarlos en otra cuenta activa distinta. Esta acción es irreversible.")
                } else {
                    Text("Las cuentas se ocultarán permanentemente de Mis cuentas y dejarán de aparecer en filtros y selectores. Sus movimientos se conservarán como histórico: seguirán visibles por mes y búsqueda, pero no podrás filtrarlos por cuenta ni editarlos o eliminarlos. Si hay reembolsos pendientes, podrás registrarlos en otra cuenta activa distinta. Esta acción es irreversible.")
                }
            }
            .alert("No se pudo eliminar la cuenta", isPresented: $showingDeleteError) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage)
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
        CrashReportService.shared.recordBreadcrumb("Eliminando cuenta desde el listado")

        do {
            try AccountDeletionService.delete(pendingAccountsDeletion, allMovements: movements, recurringMovements: recurringMovements, in: modelContext)
            pendingAccountsDeletion = []
        } catch {
            deleteErrorMessage = error.localizedDescription
            showingDeleteError = true
        }
    }
}

private struct AccountTypeStrip: View {
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    let balancesByType: [(AccountType, Decimal, Int)]
    let currencyCode: String

    var body: some View {
        if !balancesByType.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(balancesByType, id: \.0) { type, balance, count in
                        HStack(spacing: 10) {
                            FinanceGlassIconBadge(systemName: type.icon, tint: type.color, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(balance.masked(hideBalances, code: currencyCode))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(type.color)
                                    .lineLimit(1)
                            }
                            Text("\(count)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .padding(10)
                        .financeInsetCard(cornerRadius: 18)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
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
