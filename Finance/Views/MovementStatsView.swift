//
//  MovementStatsView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData
import Charts

private enum StatsDomain: String, CaseIterable, Identifiable {
    case movements
    case investments

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .movements:
            return "Movimientos"
        case .investments:
            return "Inversiones"
        }
    }
}

private typealias InvestmentSeriesPoint = InvestmentDailyTotal

private struct InvestmentAccountPerformance: Identifiable {
    let id: UUID
    let accountName: String
    let bankName: String
    let invested: Decimal
    let market: Decimal

    var profit: Decimal {
        market - invested
    }

    var returnPercent: Decimal? {
        guard invested > 0 else { return nil }
        return (profit / invested) * 100
    }
}

private struct MovementPeriodTotals {
    var income: Decimal = 0
    var expense: Decimal = 0
    var movementCount: Int = 0

    var net: Decimal {
        income - expense
    }

    var savingsRate: Decimal? {
        guard income > 0 else { return nil }
        return (net / income) * 100
    }
}

private struct MonthlyBalancePoint: Identifiable {
    let monthStart: Date
    let income: Decimal
    let expense: Decimal

    var id: Date { monthStart }

    var net: Decimal {
        income - expense
    }
}

private struct MovementStatsDerivedData {
    let currentTotals: MovementPeriodTotals
    let comparisonInterval: DateInterval?
    let comparisonTotals: MovementPeriodTotals
    let monthlyBalancePoints: [MonthlyBalancePoint]
    let patrimonyEvolutionPoints: [PatrimonySeriesPoint]
    let expenseByCategory: [CategoryAmountDatum]
    let incomeByCategory: [CategoryAmountDatum]

    var savingsRateDelta: Decimal? {
        guard let current = currentTotals.savingsRate,
              let previous = comparisonTotals.savingsRate else {
            return nil
        }
        return current - previous
    }
}

private struct PatrimonyMovementImpact {
    let date: Date
    let accountID: UUID
    let amount: Decimal
}

private struct PatrimonySnapshotValue {
    let date: Date
    let marketValue: Decimal
}

private struct PatrimonySeriesPoint: Identifiable {
    let date: Date
    let total: Decimal

    var id: Date { date }
}

private struct ComparisonVariation {
    let trend: ComparisonTrend
    let value: String?
    let color: Color
}

private enum ComparisonTrend {
    case up
    case down
    case neutral
    case unknown
}

private enum MovementDateFilter: String, CaseIterable, Identifiable {
    case all
    case currentMonth
    case previousMonth
    case last3Months
    case currentYear
    case previousYear
    case specificMonth
    case specificYear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return "Todo"
        case .currentMonth:
            return "Mes actual"
        case .previousMonth:
            return "Mes anterior"
        case .last3Months:
            return "Últimos 3 meses"
        case .currentYear:
            return "Año actual"
        case .previousYear:
            return "Año anterior"
        case .specificMonth:
            return "Mes concreto"
        case .specificYear:
            return "Año concreto"
        }
    }
}

struct MovementStatsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \InvestmentSnapshot.snapshotDate, order: .forward) private var snapshots: [InvestmentSnapshot]

    @State private var selectedDomain: StatsDomain = .movements
    @State private var selectedDateFilter: MovementDateFilter = .currentMonth
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingCustomPeriodSheet = false
    @State private var customPeriodMode: CustomPeriodMode = .month
    @State private var customMonthDraft: Int = Calendar.current.component(.month, from: Date())
    @State private var customYearDraft: Int = Calendar.current.component(.year, from: Date())
    @State private var showingWrappedHistory = false

    private var calendar: Calendar { .current }

    private var activeAccounts: [BankAccount] {
        accounts.filter(\.isActive)
    }

    private var availableYears: [Int] {
        let movementYears = Set(movements.map { calendar.component(.year, from: $0.occurredAt) })
        let snapshotYears = Set(snapshots.map { calendar.component(.year, from: $0.snapshotDate) })
        let currentYear = calendar.component(.year, from: Date())
        return (movementYears.union(snapshotYears).union([currentYear])).sorted(by: >)
    }

    private var monthOptions: [(Int, String)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        let symbols = formatter.monthSymbols ?? []
        return symbols.enumerated().map { index, symbol in
            let capitalized = symbol.prefix(1).uppercased() + symbol.dropFirst()
            return (index + 1, capitalized)
        }
    }

    private var quickFilterChips: [(MovementDateFilter, String)] {
        [
            (.all, "Todo"),
            (.currentMonth, "Mes actual"),
            (.previousMonth, "Último mes"),
            (.last3Months, "Últimos 3 meses"),
            (.currentYear, "Año actual"),
            (.previousYear, "Último año")
        ]
    }

    private var isCustomFilterActive: Bool {
        selectedDateFilter == .specificMonth || selectedDateFilter == .specificYear
    }

    private var activeInterval: DateInterval? {
        let now = Date()
        switch selectedDateFilter {
        case .all:
            return nil
        case .currentMonth:
            return monthInterval(for: now)
        case .previousMonth:
            guard let previous = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
            return monthInterval(for: previous)
        case .last3Months:
            guard let start = calendar.date(byAdding: .month, value: -3, to: now) else { return nil }
            return DateInterval(start: start, end: now)
        case .currentYear:
            return yearInterval(for: calendar.component(.year, from: now))
        case .previousYear:
            return yearInterval(for: calendar.component(.year, from: now) - 1)
        case .specificMonth:
            return monthInterval(month: selectedMonth, year: selectedYear)
        case .specificYear:
            return yearInterval(for: selectedYear)
        }
    }

    private var investmentAccounts: [BankAccount] {
        activeAccounts.filter { $0.accountType == .investment }
    }

    private var filteredInvestmentSnapshots: [InvestmentSnapshot] {
        let investmentSnapshots = snapshots.filter { $0.account?.accountType == .investment && $0.account?.isActive == true }
        guard let activeInterval else { return investmentSnapshots }
        return investmentSnapshots.filter { activeInterval.contains($0.snapshotDate) }
    }

    private var investmentSeries: [InvestmentSeriesPoint] {
        let investmentSnapshots = snapshots.filter {
            $0.account?.accountType == .investment && $0.account?.isActive == true
        }
        let allDailyTotals = InvestmentSnapshot.aggregatedDailyTotals(
            from: investmentSnapshots,
            calendar: calendar
        )
        let periodTotals = activeInterval.map { interval in
            allDailyTotals.filter { interval.contains($0.date) }
        } ?? allDailyTotals

        guard !periodTotals.isEmpty else {
            guard selectedDateFilter == .all && !investmentAccounts.isEmpty else { return [] }
            let today = calendar.startOfDay(for: Date())
            let invested = investmentAccounts.reduce(Decimal.zero) { $0 + $1.effectiveInvestedAmount }
            let market = investmentAccounts.reduce(Decimal.zero) { $0 + $1.effectiveMarketValue }
            return [InvestmentSeriesPoint(id: today, date: today, invested: invested, market: market)]
        }

        return periodTotals
    }

    private var investmentBreakdownByAccount: [InvestmentAccountPerformance] {
        let grouped = Dictionary(grouping: filteredInvestmentSnapshots.compactMap { snapshot -> (UUID, InvestmentSnapshot)? in
            guard let accountId = snapshot.account?.id else { return nil }
            return (accountId, snapshot)
        }) { pair in
            pair.0
        }

        let rowsFromSnapshots = grouped.values.compactMap { snapshots -> InvestmentAccountPerformance? in
            guard let latest = InvestmentSnapshot.dailySnapshots(
                from: snapshots.map { $0.1 },
                calendar: calendar
            ).last,
                  let account = latest.account else {
                return nil
            }

            return InvestmentAccountPerformance(
                id: account.id,
                accountName: account.name,
                bankName: account.bankDisplayName,
                invested: latest.investedAmount,
                market: latest.marketValue
            )
        }

        if !rowsFromSnapshots.isEmpty {
            return rowsFromSnapshots.sorted { $0.profit > $1.profit }
        }

        if selectedDateFilter == .all {
            return investmentAccounts.map { account in
                InvestmentAccountPerformance(
                    id: account.id,
                    accountName: account.name,
                    bankName: account.bankDisplayName,
                    invested: account.effectiveInvestedAmount,
                    market: account.effectiveMarketValue
                )
            }
            .sorted { $0.profit > $1.profit }
        }

        return []
    }

    private var comparisonPeriodLabel: String {
        switch selectedDateFilter {
        case .all:
            return "Sin comparación"
        case .currentMonth, .specificMonth:
            return "Mes anterior"
        case .previousMonth:
            return "Mes previo"
        case .last3Months:
            return "3 meses previos"
        case .currentYear, .specificYear:
            return "Año anterior"
        case .previousYear:
            return "Año previo"
        }
    }

    private func monthlyAnalysisInterval(at now: Date, activeInterval: DateInterval?) -> DateInterval {
        if let activeInterval {
            let end = activeInterval.end < now ? activeInterval.end : now
            return DateInterval(start: activeInterval.start, end: end)
        }

        let startOfCurrentMonth = startOfMonth(for: now)
        let start = calendar.date(byAdding: .month, value: -11, to: startOfCurrentMonth) ?? startOfCurrentMonth
        return DateInterval(start: start, end: now)
    }

    private var latestWrappedMonth: WrappedMonth? {
        MonthlyWrappedService.latestClosedMonth(from: movements)
    }

    private var hasPendingWrapped: Bool {
        guard let latestWrappedMonth else { return false }
        return !MonthlyWrappedService.hasSeen(month: latestWrappedMonth)
    }

    private var monthlyAnalysisLabel: String {
        selectedDateFilter == .all ? "Últimos 12 meses" : activePeriodLabel
    }

    private func monthlyBalancePoints(in interval: DateInterval) -> [MonthlyBalancePoint] {
        let movementsInWindow = movements.filter { interval.contains($0.occurredAt) }

        var groupedTotals: [Date: (income: Decimal, expense: Decimal)] = [:]

        for movement in movementsInWindow {
            let monthStart = startOfMonth(for: movement.occurredAt)
            var bucket = groupedTotals[monthStart] ?? (0, 0)

            switch movement.type {
            case .expense:
                bucket.expense += movement.statsExpenseAmount
            case .income:
                bucket.income += movement.statsIncomeAmount
            case .transfer:
                continue
            }

            groupedTotals[monthStart] = bucket
        }

        return monthStarts(in: interval).map { monthStart in
            let bucket = groupedTotals[monthStart] ?? (0, 0)
            return MonthlyBalancePoint(
                monthStart: monthStart,
                income: bucket.income,
                expense: bucket.expense
            )
        }
    }

    private func patrimonyEvolutionPoints(in interval: DateInterval, now: Date) -> [PatrimonySeriesPoint] {
        guard !accounts.isEmpty else { return [] }

        var pointDates = monthStarts(in: interval)

        let intervalEnd = interval.end < now ? interval.end : now

        if pointDates.isEmpty {
            pointDates = [intervalEnd]
        } else if !calendar.isDate(pointDates.last ?? intervalEnd, inSameDayAs: intervalEnd) {
            pointDates.append(intervalEnd)
        }

        let points = makePatrimonySeries(pointDates: pointDates)
        return points
    }

    private func makeMovementStatsDerivedData() -> MovementStatsDerivedData {
        let now = Date()
        let selectedInterval = activeInterval
        let selectedMovements = selectedInterval.map { interval in
            movements.filter { interval.contains($0.occurredAt) }
        } ?? movements
        let currentTotals = movementTotals(for: selectedMovements)
        let currentComparisonInterval = makeComparisonInterval(for: selectedInterval)
        let comparisonMovements = currentComparisonInterval.map { interval in
            movements.filter { interval.contains($0.occurredAt) }
        } ?? []
        let analysisInterval = monthlyAnalysisInterval(at: now, activeInterval: selectedInterval)

        return MovementStatsDerivedData(
            currentTotals: currentTotals,
            comparisonInterval: currentComparisonInterval,
            comparisonTotals: movementTotals(for: comparisonMovements),
            monthlyBalancePoints: monthlyBalancePoints(in: analysisInterval),
            patrimonyEvolutionPoints: patrimonyEvolutionPoints(in: analysisInterval, now: now),
            expenseByCategory: categoryData(for: .expense, movements: selectedMovements),
            incomeByCategory: categoryData(for: .income, movements: selectedMovements)
        )
    }

    private func makeComparisonInterval(for interval: DateInterval?) -> DateInterval? {
        guard let interval else { return nil }

        switch selectedDateFilter {
        case .all:
            return nil
        case .currentMonth, .previousMonth, .specificMonth:
            guard let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: interval.start) else { return nil }
            return monthInterval(for: previousMonthDate)
        case .last3Months:
            guard let start = calendar.date(byAdding: .month, value: -3, to: interval.start) else { return nil }
            return DateInterval(start: start, end: interval.start)
        case .currentYear, .previousYear, .specificYear:
            let comparisonYear = calendar.component(.year, from: interval.start) - 1
            return yearInterval(for: comparisonYear)
        }
    }

    private func makePatrimonySeries(pointDates: [Date]) -> [PatrimonySeriesPoint] {
        guard !pointDates.isEmpty else { return [] }

        var impacts: [PatrimonyMovementImpact] = []
        impacts.reserveCapacity(movements.count * 2)
        for movement in movements {
            switch movement.type {
            case .expense:
                if let accountID = movement.account?.id {
                    impacts.append(PatrimonyMovementImpact(date: movement.occurredAt, accountID: accountID, amount: -movement.amount))
                }
            case .income:
                if let accountID = movement.account?.id {
                    impacts.append(PatrimonyMovementImpact(date: movement.occurredAt, accountID: accountID, amount: movement.amount))
                }
            case .transfer:
                if let accountID = movement.account?.id {
                    impacts.append(PatrimonyMovementImpact(date: movement.occurredAt, accountID: accountID, amount: -movement.amount))
                }
                if let accountID = movement.destinationAccount?.id {
                    impacts.append(PatrimonyMovementImpact(date: movement.occurredAt, accountID: accountID, amount: movement.amount))
                }
            }
        }
        impacts.sort { $0.date > $1.date }

        var balances = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.balance) })

        var snapshotsByAccount: [UUID: [PatrimonySnapshotValue]] = [:]
        for snapshot in snapshots {
            guard let accountID = snapshot.account?.id else { continue }
            snapshotsByAccount[accountID, default: []].append(
                PatrimonySnapshotValue(date: snapshot.snapshotDate, marketValue: snapshot.marketValue)
            )
        }
        for accountID in snapshotsByAccount.keys {
            snapshotsByAccount[accountID]?.sort { $0.date > $1.date }
        }
        var snapshotIndices = Dictionary(uniqueKeysWithValues: snapshotsByAccount.keys.map { ($0, 0) })

        var result: [PatrimonySeriesPoint] = []
        result.reserveCapacity(pointDates.count)
        var impactIndex = 0

        for date in pointDates.reversed() {
            // `historicalBalance` used a strict `>` comparison. Keep that boundary
            // so a movement recorded exactly at a chart point remains included there.
            while impactIndex < impacts.count, impacts[impactIndex].date > date {
                let impact = impacts[impactIndex]
                balances[impact.accountID, default: 0] -= impact.amount
                impactIndex += 1
            }

            var total = Decimal.zero
            for account in accounts where account.isVisibleInPatrimony(at: date) {
                if account.isInvestmentAccount,
                   let accountSnapshots = snapshotsByAccount[account.id],
                   !accountSnapshots.isEmpty {
                    var index = snapshotIndices[account.id] ?? 0
                    while index < accountSnapshots.count, accountSnapshots[index].date > date {
                        index += 1
                    }
                    snapshotIndices[account.id] = index

                    if index < accountSnapshots.count {
                        total += accountSnapshots[index].marketValue
                    } else {
                        // Conservative fallback: preserve the original earliest-snapshot
                        // behavior when no snapshot is old enough for this date.
                        total += accountSnapshots[accountSnapshots.count - 1].marketValue
                    }
                } else {
                    total += balances[account.id, default: account.balance]
                }
            }
            result.append(PatrimonySeriesPoint(date: date, total: total))
        }

        return Array(result.reversed())
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
                    domainSection
                    periodSection

                    if selectedDomain == .movements {
                        movementsContent(data: makeMovementStatsDerivedData())
                    } else {
                        investmentsContent
                    }
                }
                .padding()
                .padding(.bottom, 24)
                .containerRelativeFrame(.horizontal)
            }
            .financeGlassPageBackground()
            .navigationTitle("Estadísticas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingWrappedHistory = true
                    } label: {
                        Label("Wrapped", systemImage: "sparkles.rectangle.stack")
                            .labelStyle(.iconOnly)
                            .financeToolbarIconStyle()
                    }
                    .disabled(latestWrappedMonth == nil)
                    .accessibilityLabel("Abrir resumen mensual")
                }
            }
            .onAppear {
                if !availableYears.contains(selectedYear), let first = availableYears.first {
                    selectedYear = first
                }
            }
            .sheet(isPresented: $showingCustomPeriodSheet) {
                CustomPeriodSheet(
                    monthOptions: monthOptions,
                    availableYears: availableYears,
                    mode: $customPeriodMode,
                    selectedMonth: $customMonthDraft,
                    selectedYear: $customYearDraft,
                    onApply: {
                        applyCustomFilter()
                    }
                )
            }
            .sheet(isPresented: $showingWrappedHistory) {
                MonthlyWrappedHistoryView(initialMonth: latestWrappedMonth)
            }
        }
    }

    private var domainSection: some View {
        Picker("Ámbito", selection: $selectedDomain) {
            ForEach(StatsDomain.allCases) { domain in
                Text(domain.displayName).tag(domain)
            }
        }
        .pickerStyle(.segmented)
        .padding(4)
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.row)
    }

    @ViewBuilder
    private func movementsContent(data: MovementStatsDerivedData) -> some View {
        if movements.isEmpty {
            FinanceEmptyStateContent(
                "Sin movimientos",
                systemImage: "arrow.left.arrow.right.circle",
                description: Text("Registra movimientos en la pestaña Movimientos para ver estadísticas")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else {
            wrappedBannerCard

            summaryCard(data: data)

            comparisonCard(data: data)

            monthlyBalanceCard(data: data)

            patrimonyEvolutionCard(data: data)

            CategoryPieChart(
                title: "Gastos por categoría",
                emptyTitle: "Sin gastos en este periodo",
                emptyDescription: "Cambia el filtro de fechas para ver otra ventana temporal.",
                data: data.expenseByCategory,
                currencyCode: appCurrencyCode
            )

            CategoryPieChart(
                title: "Ingresos por categoría",
                emptyTitle: "Sin ingresos en este periodo",
                emptyDescription: "Cambia el filtro de fechas para ver otra ventana temporal.",
                data: data.incomeByCategory,
                currencyCode: appCurrencyCode
            )
        }
    }

    @ViewBuilder
    private var wrappedBannerCard: some View {
        if let latestWrappedMonth {
            WrappedAccessBannerCard(
                title: hasPendingWrapped ? "Tu resumen de \(latestWrappedMonth.longLabel) está listo" : "Explora tus resúmenes",
                subtitle: hasPendingWrapped ? "Abre el resumen del mes y consulta sus estadísticas" : "Consulta meses anteriores cuando quieras",
                hasPendingWrapped: hasPendingWrapped
            ) {
                showingWrappedHistory = true
            }
        }
    }

    @ViewBuilder
    private var investmentsContent: some View {
        if investmentAccounts.isEmpty {
            FinanceEmptyStateContent(
                "Sin cuentas de inversión",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Crea una cuenta de tipo Inversión para visualizar evolución y rentabilidad")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else {
            let series = investmentSeries

            if series.isEmpty {
                VStack(spacing: 12) {
                    FinanceEmptyStateContent(
                        "Sin datos para este periodo",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Prueba otro periodo o registra snapshots de inversión para las fechas seleccionadas")
                    )

                    if selectedDateFilter != .all {
                        Button {
                            selectedDateFilter = .all
                        } label: {
                            Label("Ver todo", systemImage: "calendar")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 36)
            } else {
                investmentSummaryCard(for: series)
                InvestmentChartCardView(
                    series: series,
                    currencyCode: appCurrencyCode,
                    selectionResetID: "\(selectedDateFilter.rawValue)-\(selectedMonth)-\(selectedYear)"
                )
                investmentBreakdownCard(rows: investmentBreakdownByAccount)
            }
        }
    }

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceGlassSectionHeader(title: "Periodo", systemImage: "calendar", subtitle: "Filtra la ventana temporal")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(quickFilterChips, id: \.0) { filter, title in
                        periodChip(title: title, isSelected: selectedDateFilter == filter) {
                            selectedDateFilter = filter
                        }
                    }

                    periodChip(title: "Personalizado", isSelected: isCustomFilterActive) {
                        prepareCustomDrafts()
                        showingCustomPeriodSheet = true
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(activePeriodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if isCustomFilterActive {
                    Button("Editar") {
                        prepareCustomDrafts()
                        showingCustomPeriodSheet = true
                    }
                    .font(.caption)
                }
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var activePeriodLabel: String {
        switch selectedDateFilter {
        case .currentMonth:
            return "Mes actual"
        case .previousMonth:
            return "Último mes"
        case .last3Months:
            return "Últimos 3 meses"
        case .currentYear:
            return "Año actual"
        case .previousYear:
            return "Último año"
        case .specificMonth:
            return "\(monthName(for: selectedMonth)) \(selectedYear)"
        case .specificYear:
            return "Año \(selectedYear)"
        case .all:
            return "Todo"
        }
    }

    private func monthName(for month: Int) -> String {
        monthOptions.first(where: { $0.0 == month })?.1 ?? "Mes"
    }

    private func periodChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : (colorScheme == .dark ? .white : .primary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected
                    ? Color.accentColor
                    : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.7))
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.clear : (colorScheme == .dark ? Color.white.opacity(0.14) : Color.blue.opacity(0.10)),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func prepareCustomDrafts() {
        switch selectedDateFilter {
        case .specificMonth:
            customPeriodMode = .month
        case .specificYear:
            customPeriodMode = .year
        default:
            customPeriodMode = .month
        }

        customMonthDraft = selectedMonth
        customYearDraft = selectedYear
    }

    private func applyCustomFilter() {
        selectedMonth = customMonthDraft
        selectedYear = customYearDraft
        selectedDateFilter = customPeriodMode == .month ? .specificMonth : .specificYear
    }

    private func summaryCard(data: MovementStatsDerivedData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Resumen del periodo", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Ingresos", value: data.currentTotals.income.asCurrency(code: appCurrencyCode), tint: .green)
                StatTile(title: "Gastos", value: data.currentTotals.expense.asCurrency(code: appCurrencyCode), tint: .red)
                StatTile(title: "Balance", value: data.currentTotals.net.asCurrency(code: appCurrencyCode), tint: data.currentTotals.net >= 0 ? .green : .red)
                StatTile(title: "Tasa de ahorro", value: data.currentTotals.savingsRate.map(formatPercent) ?? "-", tint: (data.currentTotals.savingsRate ?? 0).isNegative ? .red : .green)
                StatTile(title: "Movimientos", value: "\(data.currentTotals.movementCount)", tint: .blue)
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    @ViewBuilder
    private func comparisonCard(data: MovementStatsDerivedData) -> some View {
        if selectedDateFilter == .all || data.comparisonInterval == nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("Comparativa entre periodos", systemImage: "rectangle.split.2x1")
                    .font(.headline)

                Text("Selecciona un periodo concreto para comparar contra su equivalente anterior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Comparativa entre periodos", systemImage: "rectangle.split.2x1")
                    .font(.headline)

                Text("\(activePeriodLabel) vs \(comparisonPeriodLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ComparisonMetricCard(
                        title: "Ingresos",
                        currentValue: data.currentTotals.income.asCurrency(code: appCurrencyCode),
                        previousValue: data.comparisonTotals.income.asCurrency(code: appCurrencyCode),
                        variation: comparisonVariation(
                            delta: data.currentTotals.income - data.comparisonTotals.income,
                            positiveIsGood: true,
                            formattedValue: formatSignedCurrency(data.currentTotals.income - data.comparisonTotals.income)
                        )
                    )

                    ComparisonMetricCard(
                        title: "Gastos",
                        currentValue: data.currentTotals.expense.asCurrency(code: appCurrencyCode),
                        previousValue: data.comparisonTotals.expense.asCurrency(code: appCurrencyCode),
                        variation: comparisonVariation(
                            delta: data.currentTotals.expense - data.comparisonTotals.expense,
                            positiveIsGood: false,
                            formattedValue: formatSignedCurrency(data.currentTotals.expense - data.comparisonTotals.expense)
                        )
                    )

                    ComparisonMetricCard(
                        title: "Balance",
                        currentValue: data.currentTotals.net.asCurrency(code: appCurrencyCode),
                        previousValue: data.comparisonTotals.net.asCurrency(code: appCurrencyCode),
                        variation: comparisonVariation(
                            delta: data.currentTotals.net - data.comparisonTotals.net,
                            positiveIsGood: true,
                            formattedValue: formatSignedCurrency(data.currentTotals.net - data.comparisonTotals.net)
                        )
                    )

                    ComparisonMetricCard(
                        title: "Tasa ahorro",
                        currentValue: data.currentTotals.savingsRate.map(formatPercent) ?? "-",
                        previousValue: data.comparisonTotals.savingsRate.map(formatPercent) ?? "-",
                        variation: comparisonVariation(
                            delta: data.savingsRateDelta,
                            positiveIsGood: true,
                            formattedValue: data.savingsRateDelta.map(formatSignedPercent)
                        )
                    )
                }
            }
            .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
        }
    }

    private func monthlyBalanceCard(data: MovementStatsDerivedData) -> some View {
        let points = data.monthlyBalancePoints

        return VStack(alignment: .leading, spacing: 12) {
            Label("Balance mensual", systemImage: "chart.bar.xaxis")
                .font(.headline)

            Text("Periodo: \(monthlyAnalysisLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if points.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                FinanceEmptyStateContent(
                    "Sin datos para este periodo",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Registra ingresos o gastos para visualizar el balance mensual.")
                )
            } else {
                Chart {
                    ForEach(points) { point in
                        BarMark(
                            x: .value("Mes", point.monthStart, unit: .month),
                            y: .value("Importe", decimalAsDouble(point.income))
                        )
                        .position(by: .value("Serie", "Ingresos"))
                        .foregroundStyle(by: .value("Serie", "Ingresos"))

                        BarMark(
                            x: .value("Mes", point.monthStart, unit: .month),
                            y: .value("Importe", decimalAsDouble(point.expense))
                        )
                        .position(by: .value("Serie", "Gastos"))
                        .foregroundStyle(by: .value("Serie", "Gastos"))

                        LineMark(
                            x: .value("Mes", point.monthStart, unit: .month),
                            y: .value("Balance", decimalAsDouble(point.net))
                        )
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                    }
                }
                .frame(height: 240)
                .chartForegroundStyleScale([
                    "Ingresos": Color.green,
                    "Gastos": Color.red
                ])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(0.2))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(formatAxisCurrency(amount))
                                    .font(.caption2)
                            }
                        }
                    }
                }

                HStack {
                    Text("Balance del periodo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(data.currentTotals.net.asCurrency(code: appCurrencyCode))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(data.currentTotals.net.isNegative ? .red : .green)
                }
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private func patrimonyEvolutionCard(data: MovementStatsDerivedData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Evolución de patrimonio", systemImage: "chart.xyaxis.line")
                .font(.headline)

            Text("Periodo: \(monthlyAnalysisLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            PatrimonyChartContentView(
                points: data.patrimonyEvolutionPoints,
                currencyCode: appCurrencyCode,
                selectionResetID: "\(selectedDateFilter.rawValue)-\(selectedMonth)-\(selectedYear)"
            )
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private func investmentSummaryCard(for series: [InvestmentSeriesPoint]) -> some View {
        let latestPoint = series.last
        let totalInvested = latestPoint?.invested ?? 0
        let totalMarket = latestPoint?.market ?? 0
        let totalProfit = totalMarket - totalInvested
        let totalReturnPercent: Decimal? = totalInvested > 0
            ? (totalProfit / totalInvested) * 100
            : nil
        let maximumReturn = InvestmentDailyTotal.maximumReturnPercent(in: series)

        return VStack(alignment: .leading, spacing: 12) {
            Label("Resumen de inversión", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatTile(title: "Invertido", value: totalInvested.asCurrency(code: appCurrencyCode), tint: .orange)
                    StatTile(title: "Mercado", value: totalMarket.asCurrency(code: appCurrencyCode), tint: .blue)
                }

                HStack(spacing: 12) {
                    StatTile(title: "Rentabilidad", value: totalProfit.asCurrency(code: appCurrencyCode), tint: totalProfit.isNegative ? .red : .green)
                    StatTile(
                        title: "Rentabilidad %",
                        value: totalReturnPercent.map(formatPercent) ?? "-",
                        tint: (totalReturnPercent ?? 0).isNegative ? .red : .green
                    )
                }

                StatTile(
                    title: "Máxima rentabilidad",
                    value: maximumReturn.map { formatPercent($0.value) } ?? "-",
                    tint: (maximumReturn?.value ?? 0).isNegative ? .red : .green,
                    secondarySubtitle: maximumReturn?.monetaryValue.map {
                        "Equivale a \($0.asCurrency(code: appCurrencyCode))"
                    },
                    subtitle: maximumReturn.map { "Registrada el \($0.date.asSpanishShortDate())" }
                )
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private func investmentBreakdownCard(rows: [InvestmentAccountPerformance]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Rentabilidad por cuenta", systemImage: "building.columns")
                .font(.headline)

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.accountName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text(row.profit.asCurrency(code: appCurrencyCode))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(row.profit.isNegative ? .red : .green)
                    }

                    HStack {
                        Text(row.bankName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(row.returnPercent.map(formatPercent) ?? "-")
                            .font(.caption)
                            .foregroundStyle(row.profit.isNegative ? .red : .green)
                    }
                }

                if row.id != rows.last?.id {
                    Divider()
                }
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private func formatAxisCurrency(_ value: Double) -> String {
        let absValue = abs(value)

        if absValue >= 1_000_000 {
            return "\(formatCompact(value / 1_000_000))M"
        }

        if absValue >= 1_000 {
            return "\(formatCompact(value / 1_000))k"
        }

        return Decimal(value).asCurrency(code: appCurrencyCode)
    }

    private func formatCompact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatPercent(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0,00"
        return "\(formatted)%"
    }

    private func decimalAsDouble(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    private func movementTotals(for movements: [Movement]) -> MovementPeriodTotals {
        var totals = MovementPeriodTotals()

        for movement in movements {
            switch movement.type {
            case .expense:
                totals.expense += movement.statsExpenseAmount
                totals.movementCount += 1
            case .income:
                totals.income += movement.statsIncomeAmount
                totals.movementCount += 1
            case .transfer:
                totals.movementCount += 1
            }
        }

        return totals
    }

    private func startOfMonth(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func monthStarts(in interval: DateInterval) -> [Date] {
        var months: [Date] = []
        var cursor = startOfMonth(for: interval.start)

        while cursor < interval.end {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }

        return months
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        if value > 0 {
            return "+\(value.asCurrency(code: appCurrencyCode))"
        }
        return value.asCurrency(code: appCurrencyCode)
    }

    private func formatSignedPercent(_ value: Decimal) -> String {
        if value > 0 {
            return "+\(formatPercent(value))"
        }
        return formatPercent(value)
    }

    private func comparisonVariation(
        delta: Decimal?,
        positiveIsGood: Bool,
        formattedValue: String?
    ) -> ComparisonVariation {
        guard let delta else {
            return ComparisonVariation(
                trend: .unknown,
                value: nil,
                color: .secondary
            )
        }

        if delta == 0 {
            return ComparisonVariation(
                trend: .neutral,
                value: nil,
                color: .secondary
            )
        }

        let isPositive = delta > 0
        let isGood = positiveIsGood ? isPositive : !isPositive

        return ComparisonVariation(
            trend: isPositive ? .up : .down,
            value: formattedValue,
            color: isGood ? .green : .red
        )
    }

    private func monthInterval(for date: Date) -> DateInterval? {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        guard let start else { return nil }
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func monthInterval(month: Int, year: Int) -> DateInterval? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let start = calendar.date(from: components) else { return nil }
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func yearInterval(for year: Int) -> DateInterval? {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1

        guard let start = calendar.date(from: components) else { return nil }
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func categoryData(for type: MovementType, movements: [Movement]) -> [CategoryAmountDatum] {
        let selectedMovements = movements.filter { movement in
            movement.type == type && (type != .income || !movement.isReimbursementIncome)
        }
        let grouped = Dictionary(grouping: selectedMovements) { movement in
            movement.category?.id.uuidString ?? "no-category"
        }

        return grouped.compactMap { key, groupedMovements in
            guard let first = groupedMovements.first else { return nil }
            let total = groupedMovements.reduce(Decimal(0)) { partial, movement in
                switch type {
                case .expense:
                    return partial + movement.statsExpenseAmount
                case .income:
                    return partial + movement.statsIncomeAmount
                case .transfer:
                    return partial
                }
            }
            return CategoryAmountDatum(
                id: key,
                name: first.category?.name ?? "Sin categoría",
                iconName: first.category?.iconName ?? "tag",
                color: first.category?.color ?? .gray,
                amount: total,
                movementCount: groupedMovements.count
            )
        }
        .sorted { $0.amount > $1.amount }
    }
}

private struct PatrimonyChartContentView: View {
    let points: [PatrimonySeriesPoint]
    let currencyCode: String
    let selectionResetID: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    private let xDomain: ClosedRange<Date>
    private let yDomain: ClosedRange<Double>

    init(points: [PatrimonySeriesPoint], currencyCode: String, selectionResetID: String) {
        self.points = points
        self.currencyCode = currencyCode
        self.selectionResetID = selectionResetID
        self.xDomain = Self.chartXDomain(for: points)
        self.yDomain = Self.chartYDomain(for: points)
    }

    var body: some View {
        let highlightedPoint = highlightedPoint(in: points)
        let delta = points.last.map { last in
            last.total - (points.first?.total ?? last.total)
        } ?? 0

        Group {
            if points.isEmpty {
                FinanceEmptyStateContent(
                    "Sin patrimonio para mostrar",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Crea al menos una cuenta para calcular la evolución del patrimonio.")
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Chart {
                        ForEach(points) { point in
                            AreaMark(
                                x: .value("Fecha", point.date),
                                yStart: .value("Base", yDomain.lowerBound),
                                yEnd: .value("Patrimonio", decimalAsDouble(point.total))
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.24), Color.blue.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                            LineMark(
                                x: .value("Fecha", point.date),
                                y: .value("Patrimonio", decimalAsDouble(point.total))
                            )
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.4))
                        }

                        if let highlightedPoint {
                            RuleMark(x: .value("Selección", highlightedPoint.date))
                                .foregroundStyle(.secondary.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            PointMark(
                                x: .value("Fecha", highlightedPoint.date),
                                y: .value("Patrimonio", decimalAsDouble(highlightedPoint.total))
                            )
                            .symbolSize(70)
                            .foregroundStyle(Color.blue)
                        }
                    }
                    .frame(height: 250)
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: yDomain)
                    .chartPlotStyle { plot in
                        plot.clipped()
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                                .foregroundStyle(.secondary.opacity(0.25))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                                .foregroundStyle(.secondary.opacity(0.2))
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(formatAxisCurrency(amount))
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            updateSelection(at: value.location, proxy: proxy, geometry: geometry)
                                        }
                                        .onEnded { _ in
                                            setSelectedDate(nil)
                                        }
                                )
                        }
                    }

                    if let highlightedPoint {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Patrimonio a \(highlightedPoint.date.asSpanishShortDate())")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(highlightedPoint.total.asCurrency(code: currencyCode))
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            HStack {
                                Text("Cambio en el periodo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatSignedCurrency(delta))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(delta.isNegative ? .red : .green)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if points.count <= 1, let firstPoint = points.first {
                        Label(
                            "Solo hay un registro (\(firstPoint.date.asSpanishShortDate())). Añade más histórico para ver tendencia.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: selectionResetID) { _, _ in
            setSelectedDate(nil)
        }
    }

    private static func chartXDomain(for points: [PatrimonySeriesPoint]) -> ClosedRange<Date> {
        guard let first = points.first?.date, let last = points.last?.date else {
            let now = Date()
            return now...now
        }

        if first == last {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -3, to: first) ?? first
            let end = calendar.date(byAdding: .day, value: 3, to: first) ?? first
            return start...end
        }

        return first...last
    }

    private static func chartYDomain(for points: [PatrimonySeriesPoint]) -> ClosedRange<Double> {
        guard let first = points.first else { return 0...1 }

        var minValue = (first.total as NSDecimalNumber).doubleValue
        var maxValue = minValue
        for point in points.dropFirst() {
            let value = (point.total as NSDecimalNumber).doubleValue
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
        }

        let span = maxValue - minValue
        let minPadding = max(abs(maxValue) * 0.05, 1)
        let padding = max(span * 0.12, minPadding)
        let lower = minValue - padding
        let upper = maxValue + padding

        if lower == upper {
            return (lower - 1)...(upper + 1)
        }
        return lower...upper
    }

    private func highlightedPoint(in points: [PatrimonySeriesPoint]) -> PatrimonySeriesPoint? {
        guard let selectedDate else { return points.last }
        return nearestPoint(to: selectedDate, in: points) ?? points.last
    }

    private func nearestPoint(to date: Date, in points: [PatrimonySeriesPoint]) -> PatrimonySeriesPoint? {
        guard !points.isEmpty else { return nil }

        var low = 0
        var high = points.count
        while low < high {
            let middle = (low + high) / 2
            if points[middle].date < date {
                low = middle + 1
            } else {
                high = middle
            }
        }

        if low == 0 { return points[0] }
        if low == points.count { return points[points.count - 1] }

        let previous = points[low - 1]
        let next = points[low]
        let previousDistance = date.timeIntervalSince(previous.date)
        let nextDistance = next.date.timeIntervalSince(date)
        return previousDistance <= nextDistance ? previous : next
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            setSelectedDate(nil)
            return
        }
        let plotFrame = geometry[plotFrameAnchor]
        let relativeX = location.x - plotFrame.origin.x
        guard relativeX >= 0, relativeX <= plotFrame.size.width else {
            setSelectedDate(nil)
            return
        }
        guard let date: Date = proxy.value(atX: relativeX),
              let nearestPoint = nearestPoint(to: date, in: points) else {
            setSelectedDate(nil)
            return
        }
        setSelectedDate(nearestPoint.date)
    }

    private func setSelectedDate(_ date: Date?) {
        guard selectedDate != date else { return }
        selectedDate = date
    }

    private func formatAxisCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return "\(formatCompact(value / 1_000_000))M"
        }
        if absValue >= 1_000 {
            return "\(formatCompact(value / 1_000))k"
        }
        return Decimal(value).asCurrency(code: currencyCode)
    }

    private func formatCompact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatSignedCurrency(_ value: Decimal) -> String {
        value > 0 ? "+\(value.asCurrency(code: currencyCode))" : value.asCurrency(code: currencyCode)
    }

    private func decimalAsDouble(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }
}

private struct InvestmentChartCardView: View {
    let series: [InvestmentSeriesPoint]
    let currencyCode: String
    let selectionResetID: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?

    private let investedAreaColor = Color(red: 0.58, green: 0.86, blue: 0.89)
    private let marketLineColor = Color(red: 0.96, green: 0.26, blue: 0.50)
    private let xDomain: ClosedRange<Date>
    private let yDomain: ClosedRange<Double>
    private let renderSeries: [InvestmentSeriesPoint]

    init(
        series: [InvestmentSeriesPoint],
        currencyCode: String,
        selectionResetID: String
    ) {
        self.series = series
        self.currencyCode = currencyCode
        self.selectionResetID = selectionResetID
        self.xDomain = Self.chartXDomain(for: series)
        self.yDomain = Self.chartYDomain(for: series)
        self.renderSeries = Self.visualSeries(for: series)
    }

    var body: some View {
        let highlightedPointForBody = highlightedPoint(in: series)
        let areaBaseline = yDomain.lowerBound

        VStack(alignment: .leading, spacing: 12) {
            Label("Evolución de inversión", systemImage: "chart.xyaxis.line")
                .font(.headline)

            Chart {
                ForEach(renderSeries) { point in
                    AreaMark(
                        x: .value("Fecha", point.date),
                        yStart: .value("Base", areaBaseline),
                        yEnd: .value("Aportación neta", Self.decimalAsDouble(point.invested))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [investedAreaColor.opacity(0.42), investedAreaColor.opacity(0.14)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Fecha", point.date),
                        y: .value("Valor de mercado", Self.decimalAsDouble(point.market))
                    )
                    .foregroundStyle(marketLineColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                if let highlightedPointForBody {
                    RuleMark(x: .value("Selección", highlightedPointForBody.date))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Fecha", highlightedPointForBody.date),
                        y: .value("Valor de mercado", Self.decimalAsDouble(highlightedPointForBody.market))
                    )
                    .symbolSize(70)
                    .foregroundStyle(marketLineColor)
                }
            }
            .frame(height: 250)
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartPlotStyle { plot in
                plot
                    .clipped()
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                        .foregroundStyle(.secondary.opacity(0.25))
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                        .foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(formatAxisCurrency(doubleValue))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    updateSelection(
                                        at: value.location,
                                        proxy: proxy,
                                        geometry: geometry,
                                        series: series
                                    )
                                }
                                .onEnded { _ in
                                    setSelectedDate(nil)
                                }
                        )
                }
            }

            if series.count <= 1, let onlyPoint = series.first {
                Label(
                    "Solo hay un registro (\(onlyPoint.date.asSpanishShortDate())). Añade más días para ver la tendencia.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let highlightedPointForBody {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Datos a \(highlightedPointForBody.date.asSpanishShortDate())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        selectionRow(
                            color: marketLineColor,
                            title: "Valor de mercado",
                            value: highlightedPointForBody.market.asCurrency(code: currencyCode)
                        )
                        Spacer()
                    }

                    HStack {
                        selectionRow(
                            color: investedAreaColor,
                            title: "Aportación neta",
                            value: highlightedPointForBody.invested.asCurrency(code: currencyCode)
                        )
                        Spacer()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
        .onChange(of: selectionResetID) { _, _ in
            setSelectedDate(nil)
        }
    }

    private static func chartXDomain(for series: [InvestmentSeriesPoint]) -> ClosedRange<Date> {
        guard let first = series.first?.date,
              let last = series.last?.date else {
            let now = Date()
            return now...now
        }

        if first == last {
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: -3, to: first) ?? first
            let end = calendar.date(byAdding: .day, value: 3, to: first) ?? first
            return start...end
        }

        return first...last
    }

    private static func visualSeries(for series: [InvestmentSeriesPoint]) -> [InvestmentSeriesPoint] {
        let maximumPointCount = 512
        guard series.count > maximumPointCount else { return series }

        // Keep the first/last samples and each bucket's extrema. This bounds the
        // number of marks while retaining sharp movements in either plotted line.
        let bucketCount = max(maximumPointCount / 4, 1)
        let bucketSize = Int(ceil(Double(series.count) / Double(bucketCount)))
        var selectedIndices = Set<Int>()

        for bucket in 0..<bucketCount {
            let start = bucket * bucketSize
            guard start < series.count else { break }
            let end = min(start + bucketSize, series.count)
            let indices = start..<end
            selectedIndices.insert(start)
            selectedIndices.insert(end - 1)
            selectedIndices.insert(indices.min { Self.decimalAsDouble(series[$0].invested) < Self.decimalAsDouble(series[$1].invested) } ?? start)
            selectedIndices.insert(indices.max { Self.decimalAsDouble(series[$0].invested) < Self.decimalAsDouble(series[$1].invested) } ?? start)
            selectedIndices.insert(indices.min { Self.decimalAsDouble(series[$0].market) < Self.decimalAsDouble(series[$1].market) } ?? start)
            selectedIndices.insert(indices.max { Self.decimalAsDouble(series[$0].market) < Self.decimalAsDouble(series[$1].market) } ?? start)
        }

        return selectedIndices.sorted().map { series[$0] }
    }

    private static func chartYDomain(for series: [InvestmentSeriesPoint]) -> ClosedRange<Double> {
        let values = series.flatMap { [Self.decimalAsDouble($0.invested), Self.decimalAsDouble($0.market)] }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
        }

        let span = maxValue - minValue
        let minPadding = max(abs(maxValue) * 0.05, 1)
        let padding = max(span * 0.12, minPadding)
        let lower = max(0, minValue - padding)
        let upper = maxValue + padding

        if lower == upper {
            return max(0, lower - 1)...(upper + 1)
        }

        return lower...upper
    }

    private static func decimalAsDouble(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    private func highlightedPoint(in series: [InvestmentSeriesPoint]) -> InvestmentSeriesPoint? {
        guard let selectedDate else { return series.last }
        return nearestPoint(to: selectedDate, in: series) ?? series.last
    }

    private func nearestPoint(to date: Date, in series: [InvestmentSeriesPoint]) -> InvestmentSeriesPoint? {
        guard !series.isEmpty else { return nil }

        var low = 0
        var high = series.count

        while low < high {
            let middle = (low + high) / 2
            if series[middle].date < date {
                low = middle + 1
            } else {
                high = middle
            }
        }

        if low == 0 {
            return series[0]
        }

        if low == series.count {
            return series[series.count - 1]
        }

        let previous = series[low - 1]
        let next = series[low]
        let previousDistance = date.timeIntervalSince(previous.date)
        let nextDistance = next.date.timeIntervalSince(date)
        return previousDistance <= nextDistance ? previous : next
    }

    private func updateSelection(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        series: [InvestmentSeriesPoint]
    ) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            setSelectedDate(nil)
            return
        }
        let plotFrame = geometry[plotFrameAnchor]

        let relativeX = location.x - plotFrame.origin.x

        guard relativeX >= 0, relativeX <= plotFrame.size.width else {
            setSelectedDate(nil)
            return
        }

        guard let date: Date = proxy.value(atX: relativeX),
              let nearestPoint = nearestPoint(to: date, in: series) else {
            setSelectedDate(nil)
            return
        }

        setSelectedDate(nearestPoint.date)
    }

    private func setSelectedDate(_ date: Date?) {
        guard selectedDate != date else { return }
        selectedDate = date
    }

    private func selectionRow(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    private func formatAxisCurrency(_ value: Double) -> String {
        let absValue = abs(value)

        if absValue >= 1_000_000 {
            return "\(formatCompact(value / 1_000_000))M"
        }

        if absValue >= 1_000 {
            return "\(formatCompact(value / 1_000))k"
        }

        return Decimal(value).asCurrency(code: currencyCode)
    }

    private func formatCompact(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

}

private enum CustomPeriodMode: String, CaseIterable, Identifiable {
    case month
    case year

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .month: return "Mes concreto"
        case .year: return "Año concreto"
        }
    }
}

private struct CustomPeriodSheet: View {
    @Environment(\.dismiss) private var dismiss

    let monthOptions: [(Int, String)]
    let availableYears: [Int]
    @Binding var mode: CustomPeriodMode
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int
    var onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $mode) {
                        ForEach(CustomPeriodMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    FinanceGlassSectionHeader(title: "Tipo", systemImage: "calendar.badge.clock")
                }
                .financeGlassFormSection()

                if mode == .month {
                    Section {
                        Picker("Mes", selection: $selectedMonth) {
                            ForEach(monthOptions, id: \.0) { month, name in
                                Text(name).tag(month)
                            }
                        }
                    } header: {
                        FinanceGlassSectionHeader(title: "Mes", systemImage: "calendar")
                    }
                    .financeGlassFormSection()
                }

                Section {
                    Picker("Año", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                } header: {
                    FinanceGlassSectionHeader(title: "Año", systemImage: "calendar.circle")
                }
                .financeGlassFormSection()
            }
            .financeGlassListContainer()
            .navigationTitle("Periodo personalizado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct ComparisonMetricCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let currentValue: String
    let previousValue: String
    let variation: ComparisonVariation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Actual: \(currentValue)")
                    .font(.caption2)
                    .foregroundStyle(.primary)
                Text("Anterior: \(previousValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                variationTrendView
                if let variationValue = variation.value {
                    Text(variationValue)
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
            .foregroundStyle(variation.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(cardBorderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var variationTrendView: some View {
        switch variation.trend {
        case .up:
            Image(systemName: "arrowtriangle.up.fill")
        case .down:
            Image(systemName: "arrowtriangle.down.fill")
        case .neutral:
            Text("=")
                .fontWeight(.bold)
        case .unknown:
            Image(systemName: "questionmark.circle")
        }
    }

    private var cardAccentColor: Color {
        switch variation.trend {
        case .up, .down:
            return variation.color
        case .neutral, .unknown:
            return .gray
        }
    }

    private var cardBackgroundColor: Color {
        switch variation.trend {
        case .up, .down:
            return cardAccentColor.opacity(colorScheme == .dark ? 0.16 : 0.12)
        case .neutral, .unknown:
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.10)
        }
    }

    private var cardBorderColor: Color {
        switch variation.trend {
        case .up, .down:
            return cardAccentColor.opacity(colorScheme == .dark ? 0.55 : 0.42)
        case .neutral, .unknown:
            return colorScheme == .dark ? Color.white.opacity(0.10) : Color.gray.opacity(0.25)
        }
    }
}

private struct StatTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let tint: Color
    let secondarySubtitle: String?
    let subtitle: String?

    init(
        title: String,
        value: String,
        tint: Color,
        secondarySubtitle: String? = nil,
        subtitle: String? = nil
    ) {
        self.title = title
        self.value = value
        self.tint = tint
        self.secondarySubtitle = secondarySubtitle
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(tint)

            if let secondarySubtitle {
                Text(secondarySubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(colorScheme == .dark ? 0.45 : 0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
