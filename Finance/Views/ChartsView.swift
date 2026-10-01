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

private struct ChartsDashboardData {
    let totalBalance: Decimal
    let activeAccountCount: Int
    let typeBalances: [TypeBalanceDatum]
    let pieTypeBalances: [TypeBalanceDatum]
    let bankBalances: [BankBalanceDatum]
    let topBank: BankBalanceDatum?
    let topType: TypeBalanceDatum?
    let latestWrappedMonth: WrappedMonth?
    let hasPendingWrapped: Bool
    let recoveredReimbursementAmountsByExpenseID: [UUID: Decimal]
    let pendingReimbursementMovements: [Movement]
    let totalPendingReimbursement: Decimal
}

/// Pestana de graficos y resumen del patrimonio.
struct ChartsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private var dashboardData: ChartsDashboardData? {
        let activeAccounts = accounts.filter(\.isActive)
        guard !activeAccounts.isEmpty else { return nil }

        let totalBalance = activeAccounts.reduce(Decimal(0)) { $0 + $1.balance }

        let groupedByType = Dictionary(grouping: activeAccounts) { $0.accountType }
        let typeBalances = AccountType.allCases.compactMap { type -> TypeBalanceDatum? in
            guard let typeAccounts = groupedByType[type], !typeAccounts.isEmpty else { return nil }
            let total = typeAccounts.reduce(Decimal(0)) { $0 + $1.balance }
            return TypeBalanceDatum(type: type, amount: total, count: typeAccounts.count)
        }

        let groupedByBank = Dictionary(grouping: activeAccounts) {
            $0.bank?.id.uuidString ?? "no-bank"
        }
        let bankBalances = groupedByBank.compactMap { key, groupedAccounts -> BankBalanceDatum? in
            guard let first = groupedAccounts.first else { return nil }
            let total = groupedAccounts.reduce(Decimal(0)) { $0 + $1.balance }
            return BankBalanceDatum(
                id: key,
                name: first.bank?.name ?? "Sin banco",
                color: first.bank?.color ?? .gray,
                iconName: first.bank?.iconName ?? "building.columns",
                amount: total,
                count: groupedAccounts.count
            )
        }
        .sorted { $0.amount > $1.amount }

        let recovered = reimbursementIncomes.reduce(into: [UUID: Decimal]()) { result, reimbursement in
            guard let expenseID = reimbursement.reimbursementForId else { return }
            result[expenseID, default: 0] += reimbursement.amount
        }

        var pendingWithAmount: [(movement: Movement, amount: Decimal)] = []
        pendingWithAmount.reserveCapacity(movements.count)
        for movement in movements {
            guard movement.type == .expense, movement.isSharedExpense else { continue }
            let amount = movement.pendingReimbursementAmount(recoveredAmount: recovered[movement.id] ?? 0)
            guard amount > 0 else { continue }
            pendingWithAmount.append((movement, amount))
        }
        pendingWithAmount.sort { lhs, rhs in
            lhs.amount == rhs.amount
                ? lhs.movement.occurredAt > rhs.movement.occurredAt
                : lhs.amount > rhs.amount
        }

        let latestWrappedMonth = MonthlyWrappedService.latestClosedMonth(from: movements)
        return ChartsDashboardData(
            totalBalance: totalBalance,
            activeAccountCount: activeAccounts.count,
            typeBalances: typeBalances,
            pieTypeBalances: typeBalances.filter { $0.amount > 0 },
            bankBalances: bankBalances,
            topBank: bankBalances.max { $0.amount < $1.amount },
            topType: typeBalances.max { $0.amount < $1.amount },
            latestWrappedMonth: latestWrappedMonth,
            hasPendingWrapped: latestWrappedMonth.map { !MonthlyWrappedService.hasSeen(month: $0) } ?? false,
            recoveredReimbursementAmountsByExpenseID: recovered,
            pendingReimbursementMovements: pendingWithAmount.map { $0.movement },
            totalPendingReimbursement: pendingWithAmount.reduce(Decimal(0)) { $0 + $1.amount }
        )
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

    private var summaryColumns: [GridItem] {
        if dynamicTypeSize >= .accessibility1 {
            return [GridItem(.flexible(), spacing: 10, alignment: .top)]
        }

        return [
            GridItem(.adaptive(minimum: 158, maximum: 240), spacing: 10, alignment: .top)
        ]
    }

    var body: some View {
        let data = dashboardData

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let data {
                        homeSubtitle

                        patrimonyHeroCard(data: data)

                        VStack(spacing: 12) {
                            pendingReimbursementsCard(data: data)
                            wrappedAccessCard(data: data)
                        }

                        BudgetsSection(
                            budgets: budgets,
                            movements: movements,
                            currencyCode: appCurrencyCode
                        )

                        PatrimonyPieChart(data: data.pieTypeBalances, currencyCode: appCurrencyCode)

                        BalanceByBankBarChart(data: data.bankBalances, currencyCode: appCurrencyCode)

                        summarySection(data: data)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .financeGlassPageBackground()
            .navigationTitle("Finance")
            .navigationBarTitleDisplayMode(.large)
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
                            .labelStyle(.iconOnly)
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Abrir wrapped mensual")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingDetailedStats = true
                    } label: {
                        Label("Estadísticas", systemImage: "chart.bar.xaxis")
                            .labelStyle(.iconOnly)
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Abrir estadísticas detalladas")
                }
            }
            .sheet(isPresented: $showingDetailedStats) {
                MovementStatsView()
            }
            .sheet(isPresented: $showingPendingReimbursements) {
                if let data {
                    PendingReimbursementsListView(
                        movements: data.pendingReimbursementMovements,
                        recoveredReimbursementAmountsByExpenseID: data.recoveredReimbursementAmountsByExpenseID,
                        currencyCode: appCurrencyCode
                    )
                }
            }
            .sheet(isPresented: $showingWrappedHistory) {
                MonthlyWrappedHistoryView(initialMonth: data?.latestWrappedMonth)
            }
        }
    }

    @ViewBuilder
    private func pendingReimbursementsCard(data: ChartsDashboardData) -> some View {
        if !data.pendingReimbursementMovements.isEmpty {
            let reimbursementsSubtitle = data.pendingReimbursementMovements.count == 1 ? "1 movimiento pendiente de reembolso" : "\(data.pendingReimbursementMovements.count) movimientos pendientes de reembolso"

            FinanceHomeActionBanner(
                title: "Saldo pendiente",
                value: data.totalPendingReimbursement.masked(hideBalances, code: appCurrencyCode),
                subtitle: reimbursementsSubtitle,
                systemImage: "arrow.uturn.left.circle.fill",
                pillText: "\(data.pendingReimbursementMovements.count)",
                tint: Color(red: 0.00, green: 0.66, blue: 0.49),
                showsChevron: true
            ) {
                showingPendingReimbursements = true
            }
            .accessibilityLabel(
                "Saldo pendiente, \(data.totalPendingReimbursement.masked(hideBalances, code: appCurrencyCode)), \(reimbursementsSubtitle)"
            )
        }
    }

    @ViewBuilder
    private func wrappedAccessCard(data: ChartsDashboardData) -> some View {
        if data.hasPendingWrapped, let latestWrappedMonth = data.latestWrappedMonth {
            FinanceHomeActionBanner(
                title: "Tu resumen de \(latestWrappedMonth.longLabel) está listo",
                value: nil,
                subtitle: "Abre el resumen del mes y consulta sus estadísticas",
                systemImage: "sparkles.rectangle.stack.fill",
                pillText: "NUEVO",
                tint: .financeAccent,
                showsChevron: false
            ) {
                showingWrappedHistory = true
            }
        }
    }

    private func patrimonyHeroCard(data: ChartsDashboardData) -> some View {
        FinanceHomeHeroCard(
            totalBalance: data.totalBalance,
            accountCount: data.activeAccountCount,
            currencyCode: appCurrencyCode,
            hideBalances: hideBalances
        )
    }

    private var homeSubtitle: some View {
        Text("Consulta de un vistazo todo sobre tu patrimonio")
            .financeDisplaySubtitle(size: FinanceGlassTokens.Typography.bodySize, tracking: FinanceGlassTokens.Typography.bodyTracking)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.financeHomeDark)
                .frame(width: 64, height: 64)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Sin datos para gráficos")
                    .financeDisplayTitle()
                    .foregroundStyle(.white)

                Text("Añade cuentas para ver la evolucion de tu patrimonio")
                    .financeDisplaySubtitle(size: FinanceGlassTokens.Typography.bodySize, tracking: FinanceGlassTokens.Typography.bodyTracking)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.financeHomeDark, in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.top, 36)
        .accessibilityElement(children: .combine)
    }

    private func summarySection(data: ChartsDashboardData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Resumen rapido", systemImage: "square.grid.2x2")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(.primary.opacity(0.78))

                    Text("Indicadores clave de tu inicio")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            LazyVGrid(columns: summaryColumns, spacing: 10) {
                SummaryMetricCard(title: "Patrimonio total", value: data.totalBalance.masked(hideBalances, code: appCurrencyCode), icon: "creditcard")
                SummaryMetricCard(title: "Cuentas", value: "\(data.activeAccountCount)", icon: "building.columns")
                SummaryMetricCard(title: "Bancos", value: "\(data.bankBalances.count)", icon: "building.2")
                SummaryMetricCard(
                    title: "Saldo medio/cuenta",
                    value: data.activeAccountCount == 0 ? Decimal(0).masked(hideBalances, code: appCurrencyCode) : (data.totalBalance / Decimal(data.activeAccountCount)).masked(hideBalances, code: appCurrencyCode),
                    icon: "divide.circle"
                )
                SummaryMetricCard(
                    title: "Banco principal",
                    value: data.topBank?.name ?? "-",
                    icon: data.topBank?.iconName ?? "building.columns"
                )
                SummaryMetricCard(
                    title: "Tipo principal",
                    value: data.topType?.type.displayName ?? "-",
                    icon: data.topType?.type.icon ?? "chart.bar"
                )
            }
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .padding(.bottom, 6)
        .background(Color.financeHomeSurface, in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                .strokeBorder(Color.financeHomeStroke, lineWidth: 1)
        )
    }
}

private struct FinanceHomeHeroCard: View {
    let totalBalance: Decimal
    let accountCount: Int
    let currencyCode: String
    let hideBalances: Bool

    private var accountCountText: String {
        "\(accountCount) \(accountCount == 1 ? "cuenta conectada" : "cuentas conectadas")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Patrimonio actual")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.74))
                    Text("Incluye saldos de todas tus cuentas")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Spacer(minLength: 12)

                Image(systemName: "chart.pie")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.financeHomeDark)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(totalBalance.masked(hideBalances, code: currencyCode))
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)

                Label(accountCountText, systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.11), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.financeHomeDark, in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.financeAccent.opacity(0.55))
                .frame(width: 160, height: 160)
                .offset(x: 58, y: 58)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct FinanceHomeActionBanner: View {
    let title: String
    let value: String?
    let subtitle: String
    let systemImage: String
    let pillText: String
    let tint: Color
    let showsChevron: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    if let value {
                        Text(value)
                            .font(.title3.weight(.medium))
                            .tracking(-0.25)
                            .foregroundStyle(.primary)
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 10) {
                    Text(pillText)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(tint, in: Capsule())

                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.financeHomeSurface, in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                    .strokeBorder(Color.financeHomeStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SummaryMetricCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? .white : Color.financeHomeDark)
                .frame(width: 34, height: 34)
                .background(Color.financeHomeDark.opacity(colorScheme == .dark ? 0.95 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.68) : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.medium))
                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                .lineLimit(2)
                .minimumScaleFactor(0.84)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 106, alignment: .topLeading)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    static let financeHomeDark = Color(red: 0.098, green: 0.110, blue: 0.122)
    static let financeHomeSurface = Color.primary.opacity(0.055)
    static let financeHomeStroke = Color.primary.opacity(0.08)
}
