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

private struct InvestmentSeriesPoint: Identifiable {
    let id: Date
    let date: Date
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
    @State private var selectedInvestmentDate: Date?
    @State private var selectedPatrimonyDate: Date?
    @State private var showingWrappedHistory = false

    private let investedAreaColor = Color(red: 0.58, green: 0.86, blue: 0.89)
    private let marketLineColor = Color(red: 0.96, green: 0.26, blue: 0.50)

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

    private var filteredMovements: [Movement] {
        guard let activeInterval else { return movements }
        return movements.filter { activeInterval.contains($0.occurredAt) }
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
        // Fallback: no snapshots exist at all
        guard !filteredInvestmentSnapshots.isEmpty else {
            if selectedDateFilter == .all && !investmentAccounts.isEmpty {
                let today = calendar.startOfDay(for: Date())
                let invested = investmentAccounts.reduce(Decimal(0)) { $0 + $1.effectiveInvestedAmount }
                let market = investmentAccounts.reduce(Decimal(0)) { $0 + $1.effectiveMarketValue }
                return [InvestmentSeriesPoint(id: today, date: today, invested: invested, market: market)]
            }
            return []
        }

        // --- Pre-processing (O(S log S)) ---
        // Build a lookup: accountId → snapshots sorted ascending by (date, updatedAt).
        // This is done once and reused for every chart point.
        let allInvestmentSnapshots = snapshots.filter { $0.account?.accountType == .investment }

        // A lightweight value type to avoid repeated Date normalisation inside loops
        struct NormalizedSnapshot {
            let day: Date               // startOfDay of snapshotDate
            let updatedAt: Date
            let investedAmount: Decimal
            let marketValue: Decimal
        }

        var snapshotsByAccount: [UUID: [NormalizedSnapshot]] = [:]
        for snapshot in allInvestmentSnapshots {
            guard let accountId = snapshot.account?.id else { continue }
            let entry = NormalizedSnapshot(
                day: calendar.startOfDay(for: snapshot.snapshotDate),
                updatedAt: snapshot.updatedAt,
                investedAmount: snapshot.investedAmount,
                marketValue: snapshot.marketValue
            )
            snapshotsByAccount[accountId, default: []].append(entry)
        }
        // Sort each account's list once: primary = day ascending, secondary = updatedAt ascending
        for key in snapshotsByAccount.keys {
            snapshotsByAccount[key]!.sort {
                $0.day == $1.day ? $0.updatedAt < $1.updatedAt : $0.day < $1.day
            }
        }

        // --- Chart point generation (O(D × A × log S)) ---
        // Unique dates within the active filter, sorted ascending.
        let sortedDates = Set(filteredInvestmentSnapshots.map {
            calendar.startOfDay(for: $0.snapshotDate)
        }).sorted()

        let points: [InvestmentSeriesPoint] = sortedDates.compactMap { date in
            var totalInvested = Decimal(0)
            var totalMarket = Decimal(0)
            var hasAnyValue = false

            for account in investmentAccounts {
                let accountId = account.id
                guard let sorted = snapshotsByAccount[accountId],
                      !sorted.isEmpty
                else { continue }

                // Binary search: find the last snapshot whose day <= date.
                // Because the array is sorted by day (then updatedAt), the last element
                // with day <= date is also the latest-updated snapshot for that day.
                var lo = 0, hi = sorted.count - 1, bestIndex: Int? = nil
                while lo <= hi {
                    let mid = (lo + hi) / 2
                    if sorted[mid].day <= date {
                        bestIndex = mid
                        lo = mid + 1
                    } else {
                        hi = mid - 1
                    }
                }

                guard let idx = bestIndex else { continue }
                totalInvested += sorted[idx].investedAmount
                totalMarket += sorted[idx].marketValue
                hasAnyValue = true
            }

            guard hasAnyValue else { return nil }
            return InvestmentSeriesPoint(id: date, date: date, invested: totalInvested, market: totalMarket)
        }

        return points
    }

    private var latestInvestmentPoint: InvestmentSeriesPoint? {
        investmentSeries.last
    }

    private var selectedInvestmentPoint: InvestmentSeriesPoint? {
        guard let selectedInvestmentDate else { return nil }
        return nearestInvestmentPoint(to: selectedInvestmentDate)
    }

    private var highlightedInvestmentPoint: InvestmentSeriesPoint? {
        selectedInvestmentPoint ?? latestInvestmentPoint
    }

    private var hasInvestmentTrend: Bool {
        investmentSeries.count > 1
    }

    private var investmentChartXDomain: ClosedRange<Date> {
        guard let first = investmentSeries.first?.date,
              let last = investmentSeries.last?.date else {
            let now = Date()
            return now...now
        }

        if first == last {
            let start = calendar.date(byAdding: .day, value: -3, to: first) ?? first
            let end = calendar.date(byAdding: .day, value: 3, to: first) ?? first
            return start...end
        }

        return first...last
    }

    private var investmentChartYDomain: ClosedRange<Double> {
        let values = investmentSeries.flatMap { [decimalAsDouble($0.invested), decimalAsDouble($0.market)] }
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

    private var investmentAreaBaseline: Double {
        investmentChartYDomain.lowerBound
    }

    private var investmentTotalInvested: Decimal {
        latestInvestmentPoint?.invested ?? 0
    }

    private var investmentTotalMarket: Decimal {
        latestInvestmentPoint?.market ?? 0
    }

    private var investmentTotalProfit: Decimal {
        investmentTotalMarket - investmentTotalInvested
    }

    private var investmentTotalReturnPercent: Decimal? {
        guard investmentTotalInvested > 0 else { return nil }
        return (investmentTotalProfit / investmentTotalInvested) * 100
    }

    private var investmentBreakdownByAccount: [InvestmentAccountPerformance] {
        let grouped = Dictionary(grouping: filteredInvestmentSnapshots.compactMap { snapshot -> (UUID, InvestmentSnapshot)? in
            guard let accountId = snapshot.account?.id else { return nil }
            return (accountId, snapshot)
        }) { pair in
            pair.0
        }

        let rowsFromSnapshots = grouped.values.compactMap { snapshots -> InvestmentAccountPerformance? in
            guard let latest = snapshots.map({ $0.1 }).max(by: { $0.snapshotDate < $1.snapshotDate }),
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

    private var currentPeriodTotals: MovementPeriodTotals {
        movementTotals(for: filteredMovements)
    }

    private var incomeTotal: Decimal {
        currentPeriodTotals.income
    }

    private var expenseTotal: Decimal {
        currentPeriodTotals.expense
    }

    private var netTotal: Decimal {
        currentPeriodTotals.net
    }

    private var movementCount: Int {
        currentPeriodTotals.movementCount
    }

    private var savingsRate: Decimal? {
        currentPeriodTotals.savingsRate
    }

    private var comparisonInterval: DateInterval? {
        guard let activeInterval else { return nil }

        switch selectedDateFilter {
        case .all:
            return nil
        case .currentMonth, .previousMonth, .specificMonth:
            guard let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: activeInterval.start) else { return nil }
            return monthInterval(for: previousMonthDate)
        case .last3Months:
            guard let start = calendar.date(byAdding: .month, value: -3, to: activeInterval.start) else { return nil }
            return DateInterval(start: start, end: activeInterval.start)
        case .currentYear, .previousYear, .specificYear:
            let comparisonYear = calendar.component(.year, from: activeInterval.start) - 1
            return yearInterval(for: comparisonYear)
        }
    }

    private var comparisonPeriodMovements: [Movement] {
        guard let comparisonInterval else { return [] }
        return movements.filter { comparisonInterval.contains($0.occurredAt) }
    }

    private var comparisonPeriodTotals: MovementPeriodTotals {
        movementTotals(for: comparisonPeriodMovements)
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

    private var savingsRateDelta: Decimal? {
        guard let current = savingsRate, let previous = comparisonPeriodTotals.savingsRate else {
            return nil
        }

        return current - previous
    }

    private var monthlyAnalysisInterval: DateInterval {
        if let activeInterval {
            let now = Date()
            let end = activeInterval.end < now ? activeInterval.end : now
            return DateInterval(start: activeInterval.start, end: end)
        }

        let now = Date()
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

    private var monthlyBalancePoints: [MonthlyBalancePoint] {
        let interval = monthlyAnalysisInterval
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

    private var patrimonyEvolutionPoints: [PatrimonySeriesPoint] {
        guard !activeAccounts.isEmpty else { return [] }

        let interval = monthlyAnalysisInterval
        var pointDates = monthStarts(in: interval)

        let now = Date()
        let intervalEnd = interval.end < now ? interval.end : now

        if pointDates.isEmpty {
            pointDates = [intervalEnd]
        } else if !calendar.isDate(pointDates.last ?? intervalEnd, inSameDayAs: intervalEnd) {
            pointDates.append(intervalEnd)
        }

        return pointDates.map { date in
            PatrimonySeriesPoint(date: date, total: patrimonyTotal(at: date))
        }
    }

    private var selectedPatrimonyPoint: PatrimonySeriesPoint? {
        guard let selectedPatrimonyDate else { return nil }
        return nearestPatrimonyPoint(to: selectedPatrimonyDate)
    }

    private var highlightedPatrimonyPoint: PatrimonySeriesPoint? {
        selectedPatrimonyPoint ?? patrimonyEvolutionPoints.last
    }

    private var patrimonyDelta: Decimal {
        guard let first = patrimonyEvolutionPoints.first,
              let last = patrimonyEvolutionPoints.last else {
            return 0
        }
        return last.total - first.total
    }

    private var hasPatrimonyTrend: Bool {
        patrimonyEvolutionPoints.count > 1
    }

    private var patrimonyChartXDomain: ClosedRange<Date> {
        guard let first = patrimonyEvolutionPoints.first?.date,
              let last = patrimonyEvolutionPoints.last?.date else {
            let now = Date()
            return now...now
        }

        if first == last {
            let start = calendar.date(byAdding: .day, value: -3, to: first) ?? first
            let end = calendar.date(byAdding: .day, value: 3, to: first) ?? first
            return start...end
        }

        return first...last
    }

    private var patrimonyChartYDomain: ClosedRange<Double> {
        let values = patrimonyEvolutionPoints.map { decimalAsDouble($0.total) }
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0...1
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

    private var patrimonyAreaBaseline: Double {
        patrimonyChartYDomain.lowerBound
    }

    private var expenseByCategory: [CategoryAmountDatum] {
        categoryData(for: .expense)
    }

    private var incomeByCategory: [CategoryAmountDatum] {
        categoryData(for: .income)
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
                        movementsContent
                    } else {
                        investmentsContent
                    }
                }
                .padding()
                .padding(.bottom, 24)
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
            .onChange(of: selectedDateFilter) { _, _ in
                selectedInvestmentDate = nil
                selectedPatrimonyDate = nil
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
    private var movementsContent: some View {
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

            summaryCard

            comparisonCard

            monthlyBalanceCard

            patrimonyEvolutionCard

            CategoryPieChart(
                title: "Gastos por categoría",
                emptyTitle: "Sin gastos en este periodo",
                emptyDescription: "Cambia el filtro de fechas para ver otra ventana temporal.",
                data: expenseByCategory,
                currencyCode: appCurrencyCode
            )

            CategoryPieChart(
                title: "Ingresos por categoría",
                emptyTitle: "Sin ingresos en este periodo",
                emptyDescription: "Cambia el filtro de fechas para ver otra ventana temporal.",
                data: incomeByCategory,
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
        } else if investmentSeries.isEmpty {
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
            investmentSummaryCard
            investmentChartCard
            investmentBreakdownCard
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

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Resumen del periodo", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Ingresos", value: incomeTotal.asCurrency(code: appCurrencyCode), tint: .green)
                StatTile(title: "Gastos", value: expenseTotal.asCurrency(code: appCurrencyCode), tint: .red)
                StatTile(title: "Balance", value: netTotal.asCurrency(code: appCurrencyCode), tint: netTotal >= 0 ? .green : .red)
                StatTile(title: "Tasa de ahorro", value: savingsRate.map(formatPercent) ?? "-", tint: (savingsRate ?? 0).isNegative ? .red : .green)
                StatTile(title: "Movimientos", value: "\(movementCount)", tint: .blue)
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    @ViewBuilder
    private var comparisonCard: some View {
        if selectedDateFilter == .all || comparisonInterval == nil {
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
                        currentValue: incomeTotal.asCurrency(code: appCurrencyCode),
                        previousValue: comparisonPeriodTotals.income.asCurrency(code: appCurrencyCode),
                        variation: comparisonVariation(
                            delta: incomeTotal - comparisonPeriodTotals.income,
                            positiveIsGood: true,
                            formattedValue: formatSignedCurrency(incomeTotal - comparisonPeriodTotals.income)
                        )
                    )

                    ComparisonMetricCard(
                        title: "Gastos",
                        currentValue: expenseTotal.asCurrency(code: appCurrencyCode),
                        previousValue: comparisonPeriodTotals.expense.asCurrency(code: appCurrencyCode),
                        variation: comparisonVariation(
                            delta: expenseTotal - comparisonPeriodTotals.expense,
                            positiveIsGood: false,
                            formattedValue: formatSignedCurrency(expenseTotal - comparisonPeriodTotals.expense)
                        )
                    )

                    ComparisonMetricCard(
                        title: "Balance",
                        currentValue: netTotal.asCurrency(code: appCurrencyCode),
                        previousValue: comparisonPeriodTotals.net.asCurrency(code: appCurrencyCode),
                        variation: comparisonVariation(
                            delta: netTotal - comparisonPeriodTotals.net,
                            positiveIsGood: true,
                            formattedValue: formatSignedCurrency(netTotal - comparisonPeriodTotals.net)
                        )
                    )

                    ComparisonMetricCard(
                        title: "Tasa ahorro",
                        currentValue: savingsRate.map(formatPercent) ?? "-",
                        previousValue: comparisonPeriodTotals.savingsRate.map(formatPercent) ?? "-",
                        variation: comparisonVariation(
                            delta: savingsRateDelta,
                            positiveIsGood: true,
                            formattedValue: savingsRateDelta.map(formatSignedPercent)
                        )
                    )
                }
            }
            .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
        }
    }

    private var monthlyBalanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Balance mensual", systemImage: "chart.bar.xaxis")
                .font(.headline)

            Text("Periodo: \(monthlyAnalysisLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if monthlyBalancePoints.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                FinanceEmptyStateContent(
                    "Sin datos para este periodo",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Registra ingresos o gastos para visualizar el balance mensual.")
                )
            } else {
                Chart {
                    ForEach(monthlyBalancePoints) { point in
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
                    Text(netTotal.asCurrency(code: appCurrencyCode))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(netTotal.isNegative ? .red : .green)
                }
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var patrimonyEvolutionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Evolución de patrimonio", systemImage: "chart.xyaxis.line")
                .font(.headline)

            Text("Periodo: \(monthlyAnalysisLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if patrimonyEvolutionPoints.isEmpty {
                FinanceEmptyStateContent(
                    "Sin patrimonio para mostrar",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Crea al menos una cuenta para calcular la evolución del patrimonio.")
                )
            } else {
                Chart {
                    ForEach(patrimonyEvolutionPoints) { point in
                        AreaMark(
                            x: .value("Fecha", point.date),
                            yStart: .value("Base", patrimonyAreaBaseline),
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

                    if let highlightedPatrimonyPoint {
                        RuleMark(x: .value("Selección", highlightedPatrimonyPoint.date))
                            .foregroundStyle(.secondary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                        PointMark(
                            x: .value("Fecha", highlightedPatrimonyPoint.date),
                            y: .value("Patrimonio", decimalAsDouble(highlightedPatrimonyPoint.total))
                        )
                        .symbolSize(70)
                        .foregroundStyle(Color.blue)
                    }
                }
                .frame(height: 250)
                .chartXScale(domain: patrimonyChartXDomain)
                .chartYScale(domain: patrimonyChartYDomain)
                .chartPlotStyle { plot in
                    plot
                        .clipped()
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
                                        updatePatrimonySelection(at: value.location, proxy: proxy, geometry: geometry)
                                    }
                                    .onEnded { _ in
                                        selectedPatrimonyDate = nil
                                    }
                            )
                    }
                }

                if let highlightedPatrimonyPoint {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Patrimonio a \(highlightedPatrimonyPoint.date.asSpanishShortDate())")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(highlightedPatrimonyPoint.total.asCurrency(code: appCurrencyCode))
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        HStack {
                            Text("Cambio en el periodo")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatSignedCurrency(patrimonyDelta))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(patrimonyDelta.isNegative ? .red : .green)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                if !hasPatrimonyTrend, let firstPoint = patrimonyEvolutionPoints.first {
                    Label(
                        "Solo hay un registro (\(firstPoint.date.asSpanishShortDate())). Añade más histórico para ver tendencia.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var investmentSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Resumen de inversión", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Invertido", value: investmentTotalInvested.asCurrency(code: appCurrencyCode), tint: .orange)
                StatTile(title: "Mercado", value: investmentTotalMarket.asCurrency(code: appCurrencyCode), tint: .blue)
                StatTile(title: "Rentabilidad", value: investmentTotalProfit.asCurrency(code: appCurrencyCode), tint: investmentTotalProfit.isNegative ? .red : .green)
                StatTile(
                    title: "Rentabilidad %",
                    value: investmentTotalReturnPercent.map(formatPercent) ?? "-",
                    tint: (investmentTotalReturnPercent ?? 0).isNegative ? .red : .green
                )
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private var investmentChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Evolución de inversión", systemImage: "chart.xyaxis.line")
                .font(.headline)

            Chart {
                ForEach(investmentSeries) { point in
                    AreaMark(
                        x: .value("Fecha", point.date),
                        yStart: .value("Base", investmentAreaBaseline),
                        yEnd: .value("Aportación neta", decimalAsDouble(point.invested))
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
                        y: .value("Valor de mercado", decimalAsDouble(point.market))
                    )
                    .foregroundStyle(marketLineColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                if let highlightedInvestmentPoint {
                    RuleMark(x: .value("Selección", highlightedInvestmentPoint.date))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Fecha", highlightedInvestmentPoint.date),
                        y: .value("Valor de mercado", decimalAsDouble(highlightedInvestmentPoint.market))
                    )
                    .symbolSize(70)
                    .foregroundStyle(marketLineColor)
                }
            }
            .frame(height: 250)
            .chartXScale(domain: investmentChartXDomain)
            .chartYScale(domain: investmentChartYDomain)
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
                                    updateInvestmentSelection(at: value.location, proxy: proxy, geometry: geometry)
                                }
                                .onEnded { _ in
                                    selectedInvestmentDate = nil
                                }
                        )
                }
            }

            if !hasInvestmentTrend, let onlyPoint = investmentSeries.first {
                Label(
                    "Solo hay un registro (\(onlyPoint.date.asSpanishShortDate())). Añade más días para ver la tendencia.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let highlightedInvestmentPoint {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Datos a \(highlightedInvestmentPoint.date.asSpanishShortDate())")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        investmentSelectionRow(
                            color: marketLineColor,
                            title: "Valor de mercado",
                            value: highlightedInvestmentPoint.market.asCurrency(code: appCurrencyCode)
                        )
                        Spacer()
                    }

                    HStack {
                        investmentSelectionRow(
                            color: investedAreaColor,
                            title: "Aportación neta",
                            value: highlightedInvestmentPoint.invested.asCurrency(code: appCurrencyCode)
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
    }

    private var investmentBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Rentabilidad por cuenta", systemImage: "building.columns")
                .font(.headline)

            ForEach(investmentBreakdownByAccount) { row in
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

                if row.id != investmentBreakdownByAccount.last?.id {
                    Divider()
                }
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private func investmentSelectionRow(color: Color, title: String, value: String) -> some View {
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

    private func nearestInvestmentPoint(to date: Date) -> InvestmentSeriesPoint? {
        investmentSeries.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func updateInvestmentSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            selectedInvestmentDate = nil
            return
        }
        let plotFrame = geometry[plotFrameAnchor]

        let relativeX = location.x - plotFrame.origin.x

        guard relativeX >= 0, relativeX <= plotFrame.size.width else {
            selectedInvestmentDate = nil
            return
        }

        guard let date: Date = proxy.value(atX: relativeX) else {
            selectedInvestmentDate = nil
            return
        }

        selectedInvestmentDate = date
    }

    private func nearestPatrimonyPoint(to date: Date) -> PatrimonySeriesPoint? {
        patrimonyEvolutionPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }

    private func updatePatrimonySelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else {
            selectedPatrimonyDate = nil
            return
        }
        let plotFrame = geometry[plotFrameAnchor]

        let relativeX = location.x - plotFrame.origin.x

        guard relativeX >= 0, relativeX <= plotFrame.size.width else {
            selectedPatrimonyDate = nil
            return
        }

        guard let date: Date = proxy.value(atX: relativeX) else {
            selectedPatrimonyDate = nil
            return
        }

        selectedPatrimonyDate = date
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

    private func patrimonyTotal(at date: Date) -> Decimal {
        activeAccounts.reduce(Decimal(0)) { partial, account in
            partial + historicalBalance(of: account, at: date)
        }
    }

    private func historicalBalance(of account: BankAccount, at date: Date) -> Decimal {
        guard date >= account.createdAt else {
            return 0
        }

        if account.isInvestmentAccount {
            if let snapshotMarketValue = latestSnapshotMarketValue(for: account.id, at: date) {
                return snapshotMarketValue
            }

            if let earliestSnapshotMarketValue = earliestSnapshotMarketValue(for: account.id) {
                return earliestSnapshotMarketValue
            }
        }

        var balance = account.balance

        for movement in movements where movement.occurredAt > date {
            let impact = movementImpact(of: movement, for: account.id)
            if impact != 0 {
                balance -= impact
            }
        }

        return balance
    }

    private func latestSnapshotMarketValue(for accountID: UUID, at date: Date) -> Decimal? {
        snapshots
            .filter { snapshot in
                snapshot.account?.id == accountID && snapshot.snapshotDate <= date
            }
            .max { lhs, rhs in
                lhs.snapshotDate < rhs.snapshotDate
            }?
            .marketValue
    }

    private func earliestSnapshotMarketValue(for accountID: UUID) -> Decimal? {
        snapshots
            .filter { snapshot in
                snapshot.account?.id == accountID
            }
            .min { lhs, rhs in
                lhs.snapshotDate < rhs.snapshotDate
            }?
            .marketValue
    }

    private func movementImpact(of movement: Movement, for accountID: UUID) -> Decimal {
        switch movement.type {
        case .expense:
            return movement.account?.id == accountID ? -movement.amount : 0
        case .income:
            return movement.account?.id == accountID ? movement.amount : 0
        case .transfer:
            var impact: Decimal = 0
            if movement.account?.id == accountID {
                impact -= movement.amount
            }
            if movement.destinationAccount?.id == accountID {
                impact += movement.amount
            }
            return impact
        }
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

    private func categoryData(for type: MovementType) -> [CategoryAmountDatum] {
        let selectedMovements = filteredMovements.filter { movement in
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(colorScheme == .dark ? 0.45 : 0.30), lineWidth: 1)
        )
    }
}
