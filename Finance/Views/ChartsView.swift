//
//  ChartsView.swift
//  Finance
//
//  Created by Ismael Perez on 11/02/2026.
//

import SwiftUI
import SwiftData

struct TypeBalanceDatum: Identifiable {
    var id: String { type.rawValue }
    let type: AccountType
    let amount: Decimal
    let count: Int

    var amountDouble: Double {
        (amount as NSDecimalNumber).doubleValue
    }
}

struct BankBalanceDatum: Identifiable {
    let id: String
    let name: String
    let color: Color
    let iconName: String
    let amount: Decimal
    let count: Int

    var amountDouble: Double {
        (amount as NSDecimalNumber).doubleValue
    }
}

/// Pestana de graficos y resumen del patrimonio.
struct ChartsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(filter: #Predicate<Movement> { $0.typeRaw == "income" && $0.reimbursementForId != nil })
    private var reimbursementIncomes: [Movement]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]
    @State private var showingDetailedStats = false
    @State private var showingPendingReimbursements = false
    @State private var showingWrappedHistory = false

    private var totalBalance: Decimal {
        accounts.reduce(Decimal(0)) { $0 + $1.balance }
    }

    private var typeBalances: [TypeBalanceDatum] {
        let grouped = Dictionary(grouping: accounts) { $0.accountType }
        return AccountType.allCases.compactMap { type in
            guard let typeAccounts = grouped[type], !typeAccounts.isEmpty else { return nil }
            let total = typeAccounts.reduce(Decimal(0)) { $0 + $1.balance }
            return TypeBalanceDatum(type: type, amount: total, count: typeAccounts.count)
        }
    }

    private var pieTypeBalances: [TypeBalanceDatum] {
        typeBalances.filter { $0.amount > 0 }
    }

    private var bankBalances: [BankBalanceDatum] {
        let grouped = Dictionary(grouping: accounts) {
            $0.bank?.id.uuidString ?? "no-bank"
        }

        return grouped.compactMap { key, groupedAccounts in
            guard let first = groupedAccounts.first else { return nil }
            let total = groupedAccounts.reduce(Decimal(0)) { $0 + $1.balance }
            let bankName = first.bank?.name ?? "Sin banco"
            let color = first.bank?.color ?? .gray
            let icon = first.bank?.iconName ?? "building.columns"

            return BankBalanceDatum(
                id: key,
                name: bankName,
                color: color,
                iconName: icon,
                amount: total,
                count: groupedAccounts.count
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var topBank: BankBalanceDatum? {
        bankBalances.max { $0.amount < $1.amount }
    }

    private var topType: TypeBalanceDatum? {
        typeBalances.max { $0.amount < $1.amount }
    }

    private var latestWrappedMonth: WrappedMonth? {
        MonthlyWrappedService.latestClosedMonth(from: movements)
    }

    private var hasPendingWrapped: Bool {
        guard let latestWrappedMonth else { return false }
        return !MonthlyWrappedService.hasSeen(month: latestWrappedMonth)
    }

    private var recoveredReimbursementAmountsByExpenseID: [UUID: Decimal] {
        reimbursementIncomes.reduce(into: [:]) { partialResult, reimbursement in
            guard let expenseID = reimbursement.reimbursementForId else { return }
            partialResult[expenseID, default: 0] += reimbursement.amount
        }
    }

    private var pendingReimbursementMovements: [Movement] {
        movements
            .filter { movement in
                guard movement.type == .expense, movement.isSharedExpense else { return false }
                let recoveredAmount = recoveredReimbursementAmountsByExpenseID[movement.id] ?? 0
                return movement.pendingReimbursementAmount(recoveredAmount: recoveredAmount) > 0
            }
            .sorted { lhs, rhs in
                let lhsPending = lhs.pendingReimbursementAmount(
                    recoveredAmount: recoveredReimbursementAmountsByExpenseID[lhs.id] ?? 0
                )
                let rhsPending = rhs.pendingReimbursementAmount(
                    recoveredAmount: recoveredReimbursementAmountsByExpenseID[rhs.id] ?? 0
                )

                if lhsPending == rhsPending {
                    return lhs.occurredAt > rhs.occurredAt
                }

                return lhsPending > rhsPending
            }
    }

    private var totalPendingReimbursement: Decimal {
        pendingReimbursementMovements.reduce(Decimal(0)) { partialResult, movement in
            partialResult + movement.pendingReimbursementAmount(
                recoveredAmount: recoveredReimbursementAmountsByExpenseID[movement.id] ?? 0
            )
        }
    }

    private var pageBackground: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.09, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.92, green: 0.95, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if accounts.isEmpty {
                        ContentUnavailableView(
                            "Sin datos para gráficos",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Añade cuentas en Cuentas para ver la evolucion de tu patrimonio")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                    } else {
                        patrimonyHeroCard

                        pendingReimbursementsCard

                        wrappedAccessCard

                        PatrimonyPieChart(data: pieTypeBalances, currencyCode: appCurrencyCode)

                        BalanceByBankBarChart(data: bankBalances, currencyCode: appCurrencyCode)

                        summarySection

                        BudgetsSection(
                            budgets: budgets,
                            movements: movements,
                            currencyCode: appCurrencyCode
                        )
                    }
                }
                .padding()
                .padding(.bottom, 24)
            }
            .financeGlassPageBackground()
            .navigationTitle("Finance")
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
                        showingWrappedHistory = true
                    } label: {
                        Label("Wrapped", systemImage: "sparkles.rectangle.stack")
                    }
                    .accessibilityLabel("Abrir wrapped mensual")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingDetailedStats = true
                    } label: {
                        Label("Estadísticas", systemImage: "chart.bar.xaxis")
                    }
                    .accessibilityLabel("Abrir estadísticas detalladas")
                }
            }
            .sheet(isPresented: $showingDetailedStats) {
                MovementStatsView()
            }
            .sheet(isPresented: $showingPendingReimbursements) {
                PendingReimbursementsListView(
                    movements: pendingReimbursementMovements,
                    recoveredReimbursementAmountsByExpenseID: recoveredReimbursementAmountsByExpenseID,
                    currencyCode: appCurrencyCode
                )
            }
            .sheet(isPresented: $showingWrappedHistory) {
                MonthlyWrappedHistoryView(initialMonth: latestWrappedMonth)
            }
        }
    }

    @ViewBuilder
    private var pendingReimbursementsCard: some View {
        if !pendingReimbursementMovements.isEmpty {
            PendingReimbursementsCard(
                totalPending: totalPendingReimbursement,
                movementCount: pendingReimbursementMovements.count,
                currencyCode: appCurrencyCode,
                hideBalances: hideBalances
            ) {
                showingPendingReimbursements = true
            }
        }
    }

    @ViewBuilder
    private var wrappedAccessCard: some View {
        if hasPendingWrapped, let latestWrappedMonth {
            WrappedAccessBannerCard(
                title: "Tu resumen de \(latestWrappedMonth.longLabel) está listo",
                subtitle: "Abre el resumen del mes y consulta sus estadísticas",
                hasPendingWrapped: true
            ) {
                showingWrappedHistory = true
            }
        }
    }

    private var patrimonyHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Patrimonio actual", systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("\(accounts.count) cuentas")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            Text(totalBalance.masked(hideBalances, code: appCurrencyCode))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Vista global de la distribucion por tipo y banco")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.37, blue: 0.85),
                    Color(red: 0.18, green: 0.56, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Resumen rapido", systemImage: "square.grid.2x2")
                .font(.headline)
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SummaryMetricCard(title: "Patrimonio total", value: totalBalance.masked(hideBalances, code: appCurrencyCode), icon: "creditcard")
                SummaryMetricCard(title: "Cuentas", value: "\(accounts.count)", icon: "building.columns")
                SummaryMetricCard(title: "Bancos", value: "\(bankBalances.count)", icon: "building.2")
                SummaryMetricCard(
                    title: "Saldo medio/cuenta",
                    value: accounts.isEmpty ? Decimal(0).masked(hideBalances, code: appCurrencyCode) : (totalBalance / Decimal(accounts.count)).masked(hideBalances, code: appCurrencyCode),
                    icon: "divide.circle"
                )
                SummaryMetricCard(
                    title: "Banco principal",
                    value: topBank?.name ?? "-",
                    icon: topBank?.iconName ?? "building.columns"
                )
                SummaryMetricCard(
                    title: "Tipo principal",
                    value: topType?.type.displayName ?? "-",
                    icon: topType?.type.icon ?? "chart.bar"
                )
            }
        }
    }
}

private struct SummaryMetricCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.blue.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 5)
    }
}
