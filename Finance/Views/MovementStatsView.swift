//
//  MovementStatsView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData

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

    @State private var selectedDateFilter: MovementDateFilter = .currentMonth
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingCustomPeriodSheet = false
    @State private var customPeriodMode: CustomPeriodMode = .month
    @State private var customMonthDraft: Int = Calendar.current.component(.month, from: Date())
    @State private var customYearDraft: Int = Calendar.current.component(.year, from: Date())

    private var calendar: Calendar { .current }

    private var availableYears: [Int] {
        let years = Set(movements.map { calendar.component(.year, from: $0.occurredAt) })
        let currentYear = calendar.component(.year, from: Date())
        return (years.union([currentYear])).sorted(by: >)
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
                    periodSection

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
