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

    private let investedAreaColor = Color(red: 0.58, green: 0.86, blue: 0.89)
    private let marketLineColor = Color(red: 0.96, green: 0.26, blue: 0.50)

    private var calendar: Calendar { .current }

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
        accounts.filter { $0.accountType == .investment }
    }

    private var filteredInvestmentSnapshots: [InvestmentSnapshot] {
        let investmentSnapshots = snapshots.filter { $0.account?.accountType == .investment }
        guard let activeInterval else { return investmentSnapshots }
        return investmentSnapshots.filter { activeInterval.contains($0.snapshotDate) }
    }

    private var investmentSeries: [InvestmentSeriesPoint] {
        let groupedByDate = Dictionary(grouping: filteredInvestmentSnapshots) {
            calendar.startOfDay(for: $0.snapshotDate)
        }

        let points = groupedByDate.compactMap { date, dailySnapshots -> InvestmentSeriesPoint? in
            let groupedByAccount = Dictionary(grouping: dailySnapshots.compactMap { snapshot -> (UUID, InvestmentSnapshot)? in
                guard let accountId = snapshot.account?.id else { return nil }
                return (accountId, snapshot)
            }) { pair in
                pair.0
            }

            let latestPerAccount = groupedByAccount.values.compactMap { accountSnapshots in
                accountSnapshots
                    .map { $0.1 }
                    .max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
            }

            guard !latestPerAccount.isEmpty else { return nil }

            let totalInvested = latestPerAccount.reduce(Decimal(0)) { $0 + $1.investedAmount }
            let totalMarket = latestPerAccount.reduce(Decimal(0)) { $0 + $1.marketValue }

            return InvestmentSeriesPoint(
                id: date,
                date: date,
                invested: totalInvested,
                market: totalMarket
            )
        }
        .sorted { $0.date < $1.date }

        if !points.isEmpty {
            return points
        }

        if selectedDateFilter == .all && !investmentAccounts.isEmpty {
            let today = calendar.startOfDay(for: Date())
            let invested = investmentAccounts.reduce(Decimal(0)) { $0 + $1.effectiveInvestedAmount }
            let market = investmentAccounts.reduce(Decimal(0)) { $0 + $1.effectiveMarketValue }
            return [InvestmentSeriesPoint(id: today, date: today, invested: invested, market: market)]
        }

        return []
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

    private var incomeTotal: Decimal {
        filteredMovements
            .filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var expenseTotal: Decimal {
        filteredMovements
            .filter { $0.type == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var netTotal: Decimal {
        incomeTotal - expenseTotal
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
            .background(pageBackground)
            .navigationTitle("Estadísticas")
            .onAppear {
                if !availableYears.contains(selectedYear), let first = availableYears.first {
                    selectedYear = first
                }
            }
            .onChange(of: selectedDateFilter) { _, _ in
                selectedInvestmentDate = nil
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
        }
    }

    private var domainSection: some View {
        Picker("Ámbito", selection: $selectedDomain) {
            ForEach(StatsDomain.allCases) { domain in
                Text(domain.displayName).tag(domain)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var movementsContent: some View {
        if movements.isEmpty {
            ContentUnavailableView(
                "Sin movimientos",
                systemImage: "arrow.left.arrow.right.circle",
                description: Text("Registra movimientos en la pestaña Movimientos para ver estadísticas")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else {
            summaryCard

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
    private var investmentsContent: some View {
        if investmentAccounts.isEmpty {
            ContentUnavailableView(
                "Sin cuentas de inversión",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("Crea una cuenta de tipo Inversión para visualizar evolución y rentabilidad")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 36)
        } else if investmentSeries.isEmpty {
            VStack(spacing: 12) {
                ContentUnavailableView(
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
            Label("Periodo", systemImage: "calendar")
                .font(.headline)

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
                StatTile(title: "Movimientos", value: "\(filteredMovements.count)", tint: .blue)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12), lineWidth: 1)
        )
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
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12), lineWidth: 1)
        )
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
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12), lineWidth: 1)
        )
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
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12), lineWidth: 1)
        )
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
        let selectedMovements = filteredMovements.filter { $0.type == type }
        let grouped = Dictionary(grouping: selectedMovements) { movement in
            movement.category?.id.uuidString ?? "no-category"
        }

        return grouped.compactMap { key, groupedMovements in
            guard let first = groupedMovements.first else { return nil }
            let total = groupedMovements.reduce(Decimal(0)) { $0 + $1.amount }
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
                Section("Tipo") {
                    Picker("Tipo", selection: $mode) {
                        ForEach(CustomPeriodMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .month {
                    Section("Mes") {
                        Picker("Mes", selection: $selectedMonth) {
                            ForEach(monthOptions, id: \.0) { month, name in
                                Text(name).tag(month)
                            }
                        }
                    }
                }

                Section("Año") {
                    Picker("Año", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                }
            }
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
    }
}
