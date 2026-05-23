//
//  AccountDetailView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData
import Charts

/// Pantalla de detalle de una cuenta bancaria.
/// Muestra toda la información y permite editar o eliminar la cuenta.
struct AccountDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    @Query(sort: \InvestmentSnapshot.snapshotDate, order: .forward) private var snapshots: [InvestmentSnapshot]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]

    @Bindable var account: BankAccount

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDeleteError = false
    @State private var deleteErrorMessage = ""
    @State private var showingInvestedUpdateSheet = false
    @State private var showingMarketValueUpdateSheet = false

    private var accountSnapshots: [InvestmentSnapshot] {
        snapshots
            .filter { $0.account?.id == account.id }
            .sorted { $0.snapshotDate < $1.snapshotDate }
    }

    var body: some View {
        List {
            Section {
                AccountDetailHero(account: account, currencyCode: appCurrencyCode, hideBalances: hideBalances)
            }
            .financeGlassClearListRow()

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    FinanceGlassSectionHeader(title: "Detalles", systemImage: "info.circle.fill")

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        AccountMetricTile(title: "Banco", value: account.bankDisplayName, icon: account.bank?.iconName ?? "building.columns", tint: account.bank?.color ?? account.accountType.color)
                        AccountMetricTile(title: "Tipo", value: account.accountType.displayName, icon: account.accountType.icon, tint: account.accountType.color)
                        AccountMetricTile(title: "Moneda", value: appCurrencyCode, icon: "eurosign.circle", tint: .blue)
                        AccountMetricTile(title: "Actualizada", value: account.updatedAt.asSpanishDateTime(), icon: "clock", tint: .secondary)
                    }
                }
            }
            .financeGlassClearListRow()

            if account.isInvestmentAccount {
                Section {
                    if accountSnapshots.isEmpty {
                        FinanceEmptyStateContent(
                            "Sin histórico",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Actualiza inversión y valor de mercado para empezar la serie temporal")
                        )
                    } else {
                        InvestmentHistoryChartView(
                            snapshots: accountSnapshots,
                            currencyCode: appCurrencyCode,
                            hideBalances: hideBalances
                        )
                    }
                } header: {
                    FinanceGlassSectionHeader(title: "Evolución", systemImage: "chart.line.uptrend.xyaxis")
                }
                .financeGlassFormSection()

                Section {
                    AccountMetricTile(title: "Invertido", value: account.effectiveInvestedAmount.masked(hideBalances, code: appCurrencyCode), icon: "tray.and.arrow.down.fill", tint: .purple)
                    AccountMetricTile(title: "Mercado", value: account.effectiveMarketValue.masked(hideBalances, code: appCurrencyCode), icon: "chart.line.uptrend.xyaxis", tint: .blue)
                    AccountMetricTile(title: "Rentabilidad", value: account.investmentProfit.masked(hideBalances, code: appCurrencyCode), icon: "arrow.up.right", tint: account.investmentProfit.isNegative ? .red : .green)

                    if let returnPercent = account.investmentReturnPercent {
                        AccountMetricTile(title: "Rentabilidad %", value: returnPercent.asPercent(), icon: "percent", tint: returnPercent.isNegative ? .red : .green)
                    }

                    if let marketValueUpdatedAt = account.marketValueUpdatedAt {
                        AccountMetricTile(title: "Mercado actualizado", value: marketValueUpdatedAt.asSpanishDateTime(), icon: "calendar.badge.clock", tint: .secondary)
                    }
                } header: {
                    FinanceGlassSectionHeader(title: "Inversión", systemImage: "chart.pie.fill")
                }
                .financeGlassFormSection()

                if !account.isArchived {
                    Section {
                    Button {
                        showingInvestedUpdateSheet = true
                    } label: {
                        Label("Actualizar cantidad invertida", systemImage: "plus.circle")
                    }

                    Button {
                        showingMarketValueUpdateSheet = true
                    } label: {
                        Label("Actualizar valor de mercado", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    } header: {
                        FinanceGlassSectionHeader(title: "Actualización", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .financeGlassFormSection()
                }
            }

            // Notas
            if !account.notes.isEmpty {
                Section {
                    Text(account.notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } header: {
                    FinanceGlassSectionHeader(title: "Notas", systemImage: "note.text")
                }
                .financeGlassFormSection()
            }

            if account.isArchived {
                Section {
                    Label("Cuenta eliminada", systemImage: "archivebox.fill")
                        .foregroundStyle(.secondary)
                    Text("Esta cuenta está oculta de Mis cuentas. Sus movimientos se conservan como histórico y no se pueden modificar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .financeGlassFormSection()
            } else {
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
                .financeGlassFormSection()
            }
        }
        .financeGlassListContainer()
        .navigationTitle("Detalle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    hideBalances.toggle()
                } label: {
                    Image(systemName: hideBalances ? "eye.slash" : "eye")
                        .financeToolbarIconStyle()
                }
                .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddAccountView(existingAccount: account)
        }
        .sheet(isPresented: $showingInvestedUpdateSheet) {
            InvestmentValueUpdateSheet(
                title: "Cantidad invertida",
                initialValue: account.effectiveInvestedAmount,
                currencyCode: appCurrencyCode,
                onSave: { value, snapshotDate in
                    upsertInvestmentSnapshot(
                        on: snapshotDate,
                        investedAmount: value,
                        marketValue: nil
                    )

                    if isToday(snapshotDate) {
                        account.investedAmount = value
                        account.updatedAt = Date()
                    }
                }
            )
        }
        .sheet(isPresented: $showingMarketValueUpdateSheet) {
            InvestmentValueUpdateSheet(
                title: "Valor de mercado",
                initialValue: account.effectiveMarketValue,
                currencyCode: appCurrencyCode,
                onSave: { value, snapshotDate in
                    upsertInvestmentSnapshot(
                        on: snapshotDate,
                        investedAmount: nil,
                        marketValue: value
                    )

                    if shouldUpdateCurrentMarketValue(using: snapshotDate) {
                        account.marketValue = value
                        account.marketValueUpdatedAt = snapshotDate
                        account.balance = value
                        account.updatedAt = Date()
                    }
                }
            )
        }
        .confirmationDialog(
            "¿Eliminar cuenta?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                deleteAccount()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("La cuenta se ocultará permanentemente de Mis cuentas y dejará de aparecer en filtros y selectores. Sus movimientos se conservarán como histórico: seguirán visibles por mes y búsqueda, pero no podrás filtrarlos por cuenta ni editarlos o eliminarlos. Si hay reembolsos pendientes, podrás registrarlos en otra cuenta activa distinta. Esta acción es irreversible.")
        }
        .alert("No se pudo eliminar la cuenta", isPresented: $showingDeleteError) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage)
        }
    }

    private func deleteAccount() {
        CrashReportService.shared.recordBreadcrumb("Eliminando cuenta desde su detalle")

        do {
            try AccountDeletionService.delete(account, allMovements: movements, recurringMovements: recurringMovements, in: modelContext)
            showingEditSheet = false
            showingInvestedUpdateSheet = false
            showingMarketValueUpdateSheet = false
            dismiss()
        } catch {
            deleteErrorMessage = error.localizedDescription
            showingDeleteError = true
        }
    }

    private func upsertInvestmentSnapshot(on date: Date, investedAmount: Decimal?, marketValue: Decimal?) {
        let normalizedDate = Calendar.current.startOfDay(for: date)

        if let existing = accountSnapshots.first(where: { Calendar.current.isDate($0.snapshotDate, inSameDayAs: normalizedDate) }) {
            if let investedAmount {
                existing.investedAmount = investedAmount
            }
            if let marketValue {
                existing.marketValue = marketValue
            }
            existing.updatedAt = Date()
            return
        }

        let snapshot = InvestmentSnapshot(
            snapshotDate: normalizedDate,
            investedAmount: investedAmount ?? account.effectiveInvestedAmount,
            marketValue: marketValue ?? account.effectiveMarketValue,
            account: account
        )
        modelContext.insert(snapshot)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func shouldUpdateCurrentMarketValue(using snapshotDate: Date) -> Bool {
        guard let current = account.marketValueUpdatedAt else { return true }
        let selectedDay = Calendar.current.startOfDay(for: snapshotDate)
        let currentDay = Calendar.current.startOfDay(for: current)
        return selectedDay >= currentDay
    }
}

// MARK: - Componente auxiliar

private struct AccountDetailHero: View {
    let account: BankAccount
    let currencyCode: String
    let hideBalances: Bool

    private var accent: Color { account.bank?.color ?? account.accountType.color }
    private var iconName: String { account.bank?.iconName ?? account.accountType.icon }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(account.accountType.displayName)
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(accent)
                    Text(account.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    Text(account.bankDisplayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(LinearGradient(colors: [accent, account.accountType.color.opacity(0.76)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Saldo disponible")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(account.balance.masked(hideBalances, code: currencyCode))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .foregroundStyle(account.balance.isNegative ? .red : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeGlassColorCard(
            gradient: LinearGradient(colors: [accent.opacity(0.22), account.accountType.color.opacity(0.13), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
            cornerRadius: FinanceGlassTokens.Radius.hero
        )
    }
}

private struct AccountMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinanceGlassIconBadge(systemName: icon, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeInsetCard(cornerRadius: 18)
    }
}

/// Fila de detalle con etiqueta y valor.
private struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
        }
    }
}

private struct InvestmentValueUpdateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialValue: Decimal
    let currencyCode: String
    let onSave: (Decimal, Date) -> Void

    @State private var valueText = ""
    @State private var snapshotDate = Date()
    @State private var showingAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("0,00", text: $valueText)
                            .keyboardType(.decimalPad)
                        CurrencySymbolLabel(code: currencyCode, companion: .body)
                    }
                } header: {
                    FinanceGlassSectionHeader(title: title, systemImage: "eurosign.circle.fill")
                }
                .financeGlassFormSection()

                Section {
                    DatePicker("Fecha del dato", selection: $snapshotDate, displayedComponents: .date)
                } header: {
                    FinanceGlassSectionHeader(title: "Fecha", systemImage: "calendar")
                }
                .financeGlassFormSection()
            }
            .financeGlassListContainer()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                valueText = formatDecimal(initialValue)
            }
            .onChange(of: valueText) { _, newValue in
                let sanitized = sanitizeDecimalInput(newValue)
                if sanitized != newValue {
                    valueText = sanitized
                }
            }
            .alert("Importe inválido", isPresented: $showingAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text("Introduce un importe válido mayor o igual que cero.")
            }
        }
    }

    private func save() {
        let parsed = parseDecimal(valueText)
        guard parsed >= 0 else {
            showingAlert = true
            return
        }

        onSave(parsed, snapshotDate)
        dismiss()
    }

    private func parseDecimal(_ text: String) -> Decimal {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned) ?? -1
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private func sanitizeDecimalInput(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: ",")

        var output = ""
        var hasSeparator = false

        for character in normalized {
            if character.isWholeNumber {
                output.append(character)
                continue
            }

            if character == ",", !hasSeparator {
                hasSeparator = true
                output.append(character)
            }
        }

        if output.first == "," {
            output = "0" + output
        }

        return output
    }
}

private enum InvestmentChartRange: String, CaseIterable, Identifiable {
    case oneMonth
    case threeMonths
    case sixMonths
    case oneYear
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneMonth:
            return "1M"
        case .threeMonths:
            return "3M"
        case .sixMonths:
            return "6M"
        case .oneYear:
            return "1A"
        case .all:
            return "Todo"
        }
    }

    func startDate(relativeTo reference: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: reference)
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: reference)
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: reference)
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: reference)
        case .all:
            return nil
        }
    }
}

private struct InvestmentHistoryChartView: View {
    let snapshots: [InvestmentSnapshot]
    let currencyCode: String
    let hideBalances: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDate: Date?
    @State private var selectedRange: InvestmentChartRange = .sixMonths

    private let investedColor = Color(red: 0.58, green: 0.86, blue: 0.89)
    private let marketColor = Color(red: 0.96, green: 0.26, blue: 0.50)

    private var displayedSnapshots: [InvestmentSnapshot] {
        guard let latestDate = snapshots.last?.snapshotDate else { return snapshots }
        guard let startDate = selectedRange.startDate(relativeTo: latestDate) else { return snapshots }

        let filtered = snapshots.filter { $0.snapshotDate >= startDate }
        return filtered.isEmpty ? [snapshots.last].compactMap { $0 } : filtered
    }

    private var bestAvailableRange: InvestmentChartRange {
        let preferredOrder: [InvestmentChartRange] = [.sixMonths, .threeMonths, .oneMonth, .oneYear, .all]
        return preferredOrder.first(where: isRangeAvailable) ?? .all
    }

    private var hasUnavailableRanges: Bool {
        InvestmentChartRange.allCases.contains { !isRangeAvailable($0) }
    }

    private var hasTrend: Bool {
        displayedSnapshots.count > 1
    }

    private var highlightedSnapshot: InvestmentSnapshot? {
        guard let selectedDate else { return displayedSnapshots.last }
        return displayedSnapshots.min { lhs, rhs in
            abs(lhs.snapshotDate.timeIntervalSince(selectedDate)) < abs(rhs.snapshotDate.timeIntervalSince(selectedDate))
        }
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = displayedSnapshots.first?.snapshotDate,
              let last = displayedSnapshots.last?.snapshotDate else {
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

    private var yDomain: ClosedRange<Double> {
        let values = displayedSnapshots.flatMap { [$0.investedAmount.asDouble, $0.marketValue.asDouble] }
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

    private var areaBaseline: Double {
        yDomain.lowerBound
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Evolución del fondo")
                .font(.headline)

            rangeSelector

            if hasUnavailableRanges {
                Text("Los rangos se habilitan según el histórico disponible.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Chart {
                ForEach(displayedSnapshots) { snapshot in
                    AreaMark(
                        x: .value("Fecha", snapshot.snapshotDate),
                        yStart: .value("Base", areaBaseline),
                        yEnd: .value("Aportación neta", snapshot.investedAmount.asDouble)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [investedColor.opacity(0.45), investedColor.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Fecha", snapshot.snapshotDate),
                        y: .value("Valor de mercado", snapshot.marketValue.asDouble)
                    )
                    .foregroundStyle(marketColor)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                }

                if let highlightedSnapshot {
                    RuleMark(x: .value("Selección", highlightedSnapshot.snapshotDate))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Fecha", highlightedSnapshot.snapshotDate),
                        y: .value("Mercado", highlightedSnapshot.marketValue.asDouble)
                    )
                    .symbolSize(70)
                    .foregroundStyle(marketColor)
                }
            }
            .id(hideBalances)
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
                            Text(Decimal(doubleValue).asCurrency(code: currencyCode))
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
                                    selectedDate = nil
                                }
                        )
                }
            }

            if let highlightedSnapshot {
                selectionCard(for: highlightedSnapshot)
            }

            if !hasTrend, let onlySnapshot = displayedSnapshots.first {
                Label(
                    "Solo hay un registro (\(onlySnapshot.snapshotDate.asSpanishShortDate())). Añade más días para ver la tendencia.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if !isRangeAvailable(selectedRange) {
                selectedRange = bestAvailableRange
            }
        }
        .onChange(of: snapshots.count) { _, _ in
            if !isRangeAvailable(selectedRange) {
                selectedRange = bestAvailableRange
            }
        }
        .onChange(of: hideBalances) { _, _ in
            selectedDate = nil
        }
    }

    private var rangeSelector: some View {
        HStack(spacing: 8) {
            ForEach(InvestmentChartRange.allCases) { range in
                Button {
                    guard isRangeAvailable(range) else { return }
                    selectedRange = range
                    selectedDate = nil
                } label: {
                    Text(range.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedRange == range ? .white : (isRangeAvailable(range) ? .secondary : .secondary.opacity(0.6)))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedRange == range
                                ? Color.black
                                : (isRangeAvailable(range) ? Color.gray.opacity(0.14) : Color.gray.opacity(0.22))
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isRangeAvailable(range))
                .opacity(isRangeAvailable(range) ? 1 : 0.55)
            }
        }
    }

    private func selectionCard(for snapshot: InvestmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Datos a \(snapshot.snapshotDate.asSpanishShortDate())")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                legendItem(
                    color: marketColor,
                    text: "Valor de mercado",
                    value: snapshot.marketValue.masked(hideBalances, code: currencyCode)
                )
                Spacer()
            }

            HStack {
                legendItem(
                    color: investedColor,
                    text: "Aportación neta",
                    value: snapshot.investedAmount.masked(hideBalances, code: currencyCode)
                )
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func legendItem(color: Color, text: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    private func isRangeAvailable(_ range: InvestmentChartRange) -> Bool {
        guard range != .all else { return true }
        guard let latestDate = snapshots.last?.snapshotDate else { return false }
        guard let firstDate = snapshots.first?.snapshotDate else { return false }
        guard let startDate = range.startDate(relativeTo: latestDate) else { return false }
        return firstDate <= startDate
    }

    private func updateSelection(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            selectedDate = nil
            return
        }

        let frame = geometry[plotFrame]
        let relativeX = location.x - frame.origin.x

        guard relativeX >= 0, relativeX <= frame.size.width else {
            selectedDate = nil
            return
        }

        guard let date: Date = proxy.value(atX: relativeX) else {
            selectedDate = nil
            return
        }

        selectedDate = date
    }
}

private extension Decimal {
    var asDouble: Double {
        (self as NSDecimalNumber).doubleValue
    }

    func asPercent() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        let formatted = formatter.string(from: self as NSDecimalNumber) ?? "0,00"
        return "\(formatted)%"
    }
}
