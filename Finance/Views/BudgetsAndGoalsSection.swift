//
//  BudgetsAndGoalsSection.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Budgets Section

/// Sección del presupuesto mensual único para ChartsView.
/// Solo puede existir un presupuesto a la vez.
struct BudgetsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let budgets: [Budget]
    let movements: [Movement]
    let currencyCode: String
    let onSelectCategoryMovements: (UUID) -> Void

    @State private var showingAddBudget = false
    @State private var showingDetail = false
    @State private var showingDeleteConfirm = false

    private var budget: Budget? { budgets.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Presupuesto mensual", systemImage: "chart.bar.fill")
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(.primary.opacity(0.78))

                    Text("Controla tus gastos por categoría")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let budget {
                    Menu {
                        Button {
                            showingAddBudget = true
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label {
                                Text("Eliminar")
                                    .foregroundStyle(.red)
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                        }
                        .tint(.red)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Opciones del presupuesto")
                    let _ = budget
                } else {
                    Button {
                        showingAddBudget = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .accessibilityLabel("Crear presupuesto mensual")
                }
            }

            if let budget {
                BudgetSummaryCard(budget: budget, movements: movements, currencyCode: currencyCode)
                    .contentShape(Rectangle())
                    .onTapGesture { showingDetail = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Abre el detalle del presupuesto")
            } else {
                emptyState
            }
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .sheet(isPresented: $showingAddBudget) {
            AddBudgetView(budgetToEdit: budget)
        }
        .sheet(isPresented: $showingDetail) {
            if let budget {
                BudgetDetailView(
                    budget: budget,
                    movements: movements,
                    currencyCode: currencyCode,
                    onSelectCategoryMovements: { categoryID in
                        showingDetail = false
                        onSelectCategoryMovements(categoryID)
                    }
                )
            }
        }
        .confirmationDialog(
            "Eliminar presupuesto",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let budget {
                    BudgetService.cancelAllNotifications(for: budget)
                    modelContext.delete(budget)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
    }

    private var emptyState: some View {
        Button {
            showingAddBudget = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crea tu presupuesto mensual")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("Define cuánto puedes gastar y repártelo por categorías.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private func currentCategorySpending(
    movements: [Movement],
    categoryIDs: Set<UUID>,
    asOf date: Date = Date(),
    calendar: Calendar = .current
) -> [UUID: Decimal] {
    guard !categoryIDs.isEmpty else { return [:] }

    var totals: [UUID: Decimal] = [:]
    for movement in movements {
        guard movement.type == .expense,
              let categoryID = movement.category?.id,
              categoryIDs.contains(categoryID),
              movement.occurredAt <= date,
              calendar.isDate(movement.occurredAt, equalTo: date, toGranularity: .month) else {
            continue
        }
        totals[categoryID, default: 0] += movement.statsExpenseAmount
    }
    return totals
}

// MARK: - Budget Summary Card (en ChartsView)

private struct BudgetSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let budget: Budget
    let movements: [Movement]
    let currencyCode: String

    var body: some View {
        let forecast = MonthlyBudgetForecast(budget: budget, movements: movements)
        let spent = forecast.spent
        let progress: Double = budget.totalAmount > 0
            ? min((spent as NSDecimalNumber).doubleValue / (budget.totalAmount as NSDecimalNumber).doubleValue, 1)
            : 0
        let progressColor = BudgetColorPalette.progress(for: progress, colorScheme: colorScheme)
        let remaining = budget.totalAmount - spent
        let isAlerting = budget.isActive && progress >= 0.8
        let isOverBudget = progress >= 1
        let statusTint = BudgetColorPalette.status(for: forecast.status, colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 16) {
            forecastStatusPill(forecast)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Gastado este mes")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(spent.masked(hideBalances, code: currencyCode))
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .tracking(-0.6)
                        .foregroundStyle(progress >= 1 ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Text(budget.totalAmount.masked(hideBalances, code: currencyCode))
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .tracking(-0.2)
                        .foregroundStyle(.primary.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .frame(minWidth: 92, maxWidth: 124, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 14) {
                MonthlyBudgetMiniChart(forecast: forecast, tint: statusTint)
                    .frame(minWidth: 96, idealWidth: 128, maxWidth: 150)
                    .frame(height: 54)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Previsión final")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(forecast.projectedFinalSpend.masked(hideBalances, code: currencyCode))
                        .font(.system(.headline, design: .rounded).weight(.medium))
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(forecast.shortMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            BudgetProgressBar(progress: progress, tint: progressColor, height: 10)

            HStack(spacing: 10) {
                consumedLabel(progress: progress)
                Spacer(minLength: 8)
                remainingLabel(remaining: remaining)
                    .layoutPriority(1)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isOverBudget
                        ? Color.red.opacity(0.4)
                        : (isAlerting
                            ? Color.orange.opacity(colorScheme == .dark ? 0.4 : 0.28)
                            : Color.primary.opacity(0.07)),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(forecast.accessibilitySummary(currencyCode: currencyCode, hidesAmounts: hideBalances))
    }

    private func forecastStatusPill(_ forecast: MonthlyBudgetForecast) -> some View {
        let tint = BudgetColorPalette.status(for: forecast.status, colorScheme: colorScheme)

        return HStack(spacing: 8) {
            forecastStatusTitle(forecast, tint: tint)
                .layoutPriority(1)
            Spacer(minLength: 6)
            forecastReliabilityLabel(forecast)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            tint.opacity(colorScheme == .dark ? 0.16 : 0.11),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func consumedLabel(progress: Double) -> some View {
        Text("\(Int(progress * 100)) % consumido")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private func remainingLabel(remaining: Decimal) -> some View {
        if remaining > 0 {
            Text("Quedan \(remaining.masked(hideBalances, code: currencyCode))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if remaining < 0 {
            Text("Superado \((-remaining).masked(hideBalances, code: currencyCode))")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text("Presupuesto agotado")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func forecastStatusTitle(
        _ forecast: MonthlyBudgetForecast,
        tint: Color
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: forecast.status.systemImage)
                .font(.caption)
                .foregroundStyle(tint)
            Text(forecast.status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func forecastReliabilityLabel(
        _ forecast: MonthlyBudgetForecast
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            reliabilityText(forecast.reliabilityLabel)
            reliabilityText(forecast.compactReliabilityLabel)
        }
    }

    private func reliabilityText(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.primary.opacity(0.72))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

// MARK: - Budget Detail View

/// Vista de detalle del presupuesto: barra global + desglose por categoría.
struct BudgetDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let budget: Budget
    let movements: [Movement]
    let currencyCode: String
    let onSelectCategoryMovements: (UUID) -> Void

    private var sortedItems: [BudgetItem] {
        budget.items
            .filter { $0.category != nil }
            .sorted { ($0.category?.name ?? "") < ($1.category?.name ?? "") }
    }

    var body: some View {
        let forecast = MonthlyBudgetForecast(budget: budget, movements: movements)
        let totalSpent = forecast.spent
        let globalProgress: Double = budget.totalAmount > 0
            ? min((totalSpent as NSDecimalNumber).doubleValue / (budget.totalAmount as NSDecimalNumber).doubleValue, 1)
            : 0
        let remaining = budget.totalAmount - totalSpent
        let items = sortedItems
        let spentByCategory = currentCategorySpending(
            movements: movements,
            categoryIDs: Set(items.compactMap { $0.category?.id })
        )

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    globalCard(totalSpent: totalSpent, globalProgress: globalProgress, remaining: remaining)
                    MonthlyBudgetForecastDetailSection(
                        forecast: forecast,
                        currencyCode: currencyCode,
                        hideBalances: hideBalances
                    )
                    categoryBreakdown(items: items, spentByCategory: spentByCategory)
                }
                .padding()
                .padding(.bottom, 24)
            }
            .navigationTitle("Presupuesto mensual")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        hideBalances.toggle()
                    } label: {
                        Image(systemName: hideBalances ? "eye.slash" : "eye")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")
                }
            }
        }
    }

    // MARK: Global card

    private func globalCard(totalSpent: Decimal, globalProgress: Double, remaining: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gastado")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                    Text(totalSpent.masked(hideBalances, code: currencyCode))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                    Text(budget.totalAmount.masked(hideBalances, code: currencyCode))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.25))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: max(0, geo.size.width * globalProgress))
                        .animation(.easeInOut(duration: 0.5), value: globalProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(Int(globalProgress * 100)) % del presupuesto consumido")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                if remaining > 0 {
                    Text("Quedan \(remaining.masked(hideBalances, code: currencyCode))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                } else if remaining < 0 {
                    Text("Superado \((-remaining).masked(hideBalances, code: currencyCode))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                } else {
                    Text("Presupuesto agotado")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: globalProgress >= 1
                    ? [Color(red: 0.8, green: 0.2, blue: 0.2), Color(red: 0.6, green: 0.1, blue: 0.1)]
                    : [Color(red: 0.14, green: 0.37, blue: 0.85), Color(red: 0.18, green: 0.56, blue: 0.91)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 14, x: 0, y: 8)
    }

    // MARK: Category breakdown

    @ViewBuilder
    private func categoryBreakdown(items: [BudgetItem], spentByCategory: [UUID: Decimal]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Por categoría", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundStyle(.primary)

            if items.isEmpty {
                Text("No hay categorías definidas en este presupuesto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { item in
                        BudgetItemRow(
                            item: item,
                            spent: item.category.map { spentByCategory[$0.id, default: 0] } ?? 0,
                            currencyCode: currencyCode,
                            onTap: item.category.map { category in
                                { onSelectCategoryMovements(category.id) }
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Monthly Forecast Presentation

private struct MonthlyBudgetForecast {
    enum Status {
        case noBudget
        case noSpending
        case good
        case tight
        case warning(day: Int)
        case exceeded

        var title: String {
            switch self {
            case .noBudget: return "Sin presupuesto"
            case .noSpending: return "Sin gastos"
            case .good: return "Vas bien"
            case .tight: return "Vas justo"
            case .warning: return "Cuidado"
            case .exceeded: return "Presupuesto excedido"
            }
        }

        var systemImage: String {
            switch self {
            case .noBudget: return "slash.circle.fill"
            case .noSpending: return "calendar.badge.clock"
            case .good: return "checkmark.seal.fill"
            case .tight: return "gauge.medium"
            case .warning: return "exclamationmark.triangle.fill"
            case .exceeded: return "exclamationmark.octagon.fill"
            }
        }

        var baseTint: Color {
            switch self {
            case .noBudget: return .secondary
            case .noSpending: return .blue
            case .good: return .green
            case .tight: return .yellow
            case .warning: return .orange
            case .exceeded: return .red
            }
        }
    }

    let spent: Decimal
    let budgetAmount: Decimal
    let projectedFinalSpend: Decimal
    let dailyRecommendation: Decimal
    let dayOfMonth: Int
    let daysInMonth: Int
    let expenseCount: Int
    let reliability: SpendingForecastReliability
    let forecastBasis: SpendingForecastBasis
    let historicalMonthsUsed: Int
    let status: Status
    let cumulativePoints: [Double]
    let idealPoints: [Double]
    let projectedPoints: [Double]

    init(budget: Budget, movements: [Movement], calendar: Calendar = .current, now: Date = Date()) {
        let serviceForecast = BudgetService.forecast(for: budget, movements: movements, asOf: now)
        let daysRange = calendar.range(of: .day, in: .month, for: now) ?? 1..<31
        let daysInMonth = daysRange.count
        let dayOfMonth = min(max(calendar.component(.day, from: now), 1), daysInMonth)
        let categoryIDs = Set(budget.items.compactMap { $0.category?.id })
        let monthExpenses = movements.filter { movement in
            guard movement.type == .expense else { return false }
            guard let categoryID = movement.category?.id, categoryIDs.contains(categoryID) else { return false }
            guard movement.occurredAt <= now else { return false }
            return calendar.isDate(movement.occurredAt, equalTo: now, toGranularity: .month)
        }

        let spent = serviceForecast.spentSoFar
        let projectedFinalSpend = serviceForecast.projectedMonthEndSpend
        let dailyRecommendation = serviceForecast.recommendedDailySpend ?? 0

        self.spent = spent
        self.budgetAmount = budget.totalAmount
        self.projectedFinalSpend = max(projectedFinalSpend, spent)
        self.dailyRecommendation = dailyRecommendation
        self.dayOfMonth = dayOfMonth
        self.daysInMonth = daysInMonth
        self.expenseCount = monthExpenses.count
        self.reliability = serviceForecast.reliability
        self.forecastBasis = serviceForecast.basis
        self.historicalMonthsUsed = serviceForecast.historicalMonthsUsed

        switch serviceForecast.status {
        case .noBudget:
            self.status = .noBudget
        case .noSpending:
            self.status = .noSpending
        case .exceeded:
            self.status = .exceeded
        case .risk:
            let depletionDay = serviceForecast.estimatedDepletionDate.map { calendar.component(.day, from: $0) } ?? dayOfMonth
            self.status = .warning(day: min(max(depletionDay, dayOfMonth), daysInMonth))
        case .tight:
            self.status = .tight
        case .good:
            self.status = .good
        }

        var dailyTotals = Array(repeating: Decimal(0), count: daysInMonth)
        for movement in monthExpenses {
            let day = min(max(calendar.component(.day, from: movement.occurredAt), 1), daysInMonth)
            dailyTotals[day - 1] += movement.statsExpenseAmount
        }

        var running = Decimal(0)
        var cumulative = [Double]()
        for index in 0..<daysInMonth {
            if index < dayOfMonth {
                running += dailyTotals[index]
                cumulative.append((running as NSDecimalNumber).doubleValue)
            } else {
                cumulative.append(.nan)
            }
        }
        self.cumulativePoints = cumulative

        self.idealPoints = (1...daysInMonth).map { day in
            ((budget.totalAmount * Decimal(day) / Decimal(daysInMonth)) as NSDecimalNumber).doubleValue
        }

        let spentDouble = (spent as NSDecimalNumber).doubleValue
        let projectedDouble = (max(projectedFinalSpend, spent) as NSDecimalNumber).doubleValue
        self.projectedPoints = (1...daysInMonth).map { day in
            if day <= dayOfMonth { return cumulative[max(day - 1, 0)] }
            let remainingSpan = max(daysInMonth - dayOfMonth, 1)
            let progress = Double(day - dayOfMonth) / Double(remainingSpan)
            return spentDouble + ((projectedDouble - spentDouble) * progress)
        }

    }

    var shortMessage: String {
        switch status {
        case .noBudget:
            return "Configura un presupuesto para activar la previsión."
        case .noSpending:
            return "Aún no hay gastos este mes."
        case .good:
            return "Tu ritmo encaja con el presupuesto."
        case .tight:
            return "Vas justo, conviene moderar el gasto diario."
        case .warning(let day):
            return "A este ritmo se agotará alrededor del día \(day)."
        case .exceeded:
            return "El presupuesto mensual ya está superado."
        }
    }

    var fullMessage: String {
        let suffix = reliability == .low
            ? " Es una estimación inicial porque el mes acaba de empezar."
            : ""

        switch status {
        case .noBudget:
            return "Sin presupuesto: define una cantidad mensual para calcular previsiones."
        case .noSpending:
            return "Sin gastos: todavía no hay datos de gasto este mes para proyectar el cierre."
        case .good:
            return "Vas bien: la previsión se mantiene dentro del presupuesto mensual." + suffix
        case .tight:
            return "Vas justo: la previsión queda muy cerca del presupuesto mensual." + suffix
        case .warning(let day):
            return "Cuidado, a este ritmo agotarás el presupuesto alrededor del día \(day)." + suffix
        case .exceeded:
            return "Ya has superado el presupuesto mensual. Revisa gastos y categorías."
        }
    }

    var reliabilityLabel: String {
        switch status {
        case .noBudget:
            return "Sin datos"
        case .noSpending:
            return "Sin gastos aún"
        default:
            if forecastBasis == .historicalAverage {
                return "Media de \(historicalMonthsUsed) meses"
            }

            switch reliability {
            case .low:
                return "Estimación inicial"
            case .medium, .high:
                return "Ritmo actual"
            }
        }
    }

    var compactReliabilityLabel: String {
        switch status {
        case .noBudget:
            return "Sin datos"
        case .noSpending:
            return "Sin gastos"
        default:
            if forecastBasis == .historicalAverage {
                return "\(historicalMonthsUsed) meses"
            }

            switch reliability {
            case .low:
                return "Inicial"
            case .medium, .high:
                return "Ritmo actual"
            }
        }
    }

    func accessibilitySummary(currencyCode: String, hidesAmounts: Bool) -> String {
        "Previsión mensual. \(fullMessage) Gastado \(spent.masked(hidesAmounts, code: currencyCode)) de \(budgetAmount.masked(hidesAmounts, code: currencyCode)). Previsión final \(projectedFinalSpend.masked(hidesAmounts, code: currencyCode))."
    }
}

private enum BudgetColorPalette {
    static func progress(for progress: Double, colorScheme: ColorScheme) -> Color {
        switch progress {
        case ..<0.6:
            return readableGreen(for: colorScheme)
        case ..<0.8:
            return readableWarning(for: colorScheme)
        case ..<1.0:
            return .orange
        default:
            return .red
        }
    }

    static func status(
        for status: MonthlyBudgetForecast.Status,
        colorScheme: ColorScheme
    ) -> Color {
        switch status {
        case .good:
            return readableGreen(for: colorScheme)
        case .tight:
            return readableWarning(for: colorScheme)
        case .warning:
            return readableWarning(for: colorScheme)
        default:
            return status.baseTint
        }
    }

    private static func readableGreen(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .green
            : Color(red: 0.031, green: 0.498, blue: 0.357)
    }

    private static func readableWarning(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.925, green: 0.494, blue: 0.0) // --rui-color-warning: #EC7E00
            : Color(red: 0.776, green: 0.353, blue: 0.0) // #C65A00, vivid light-mode variant
    }
}

private struct BudgetProgressBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * min(progress, 1)))
                    .animation(.easeInOut(duration: 0.4), value: progress)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

private struct MonthlyBudgetMiniChart: View {
    let forecast: MonthlyBudgetForecast
    let tint: Color
    var maxValueOverride: Double?

    var body: some View {
        GeometryReader { _ in
            let maxValue = maxValueOverride ?? max(
                (forecast.budgetAmount as NSDecimalNumber).doubleValue,
                forecast.projectedPoints.compactMap { $0.isNaN ? nil : $0 }.max() ?? 1,
                1
            )
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                drawLine(points: forecast.idealPoints, in: rect, maxValue: maxValue, context: &context, color: .secondary.opacity(0.42), dashed: true)
                drawLine(points: forecast.projectedPoints, in: rect, maxValue: maxValue, context: &context, color: tint.opacity(0.72), dashed: true)
                drawLine(points: forecast.cumulativePoints, in: rect, maxValue: maxValue, context: &context, color: tint, dashed: false)
            }
            .overlay(alignment: .bottomLeading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mini gráfica de previsión mensual")
        .accessibilityValue(forecast.fullMessage)
    }

    private func drawLine(
        points: [Double],
        in rect: CGRect,
        maxValue: Double,
        context: inout GraphicsContext,
        color: Color,
        dashed: Bool
    ) {
        guard points.count > 1 else { return }
        var path = Path()
        var didMove = false
        for (index, value) in points.enumerated() where !value.isNaN {
            let x = rect.minX + (CGFloat(index) / CGFloat(max(points.count - 1, 1)) * rect.width)
            let normalized = min(max(value / maxValue, 0), 1)
            let y = rect.maxY - (CGFloat(normalized) * rect.height)
            let point = CGPoint(x: x, y: y)
            if didMove {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                didMove = true
            }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: dashed ? 1.5 : 2.4, lineCap: .round, lineJoin: .round, dash: dashed ? [4, 4] : []))
    }
}

private struct MonthlyBudgetForecastDetailSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let forecast: MonthlyBudgetForecast
    let currencyCode: String
    let hideBalances: Bool

    var body: some View {
        let statusTint = BudgetColorPalette.status(for: forecast.status, colorScheme: colorScheme)

        return VStack(alignment: .leading, spacing: 14) {
            Label("Previsión mensual", systemImage: forecast.status.systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: forecast.status.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .frame(width: 42, height: 42)
                        .background(statusTint.opacity(colorScheme == .dark ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(forecast.status.title)
                            .font(.title3.weight(.medium))
                            .tracking(-0.2)
                        Text(forecast.fullMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                MonthlyBudgetLargeChart(
                    forecast: forecast,
                    currencyCode: currencyCode,
                    hideBalances: hideBalances
                )
                .frame(height: 210)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForecastMetricTile(title: "Gastado", value: forecast.spent.masked(hideBalances, code: currencyCode), tint: .primary)
                    ForecastMetricTile(title: "Presupuesto", value: forecast.budgetAmount.masked(hideBalances, code: currencyCode), tint: .primary)
                    ForecastMetricTile(title: "Previsión final", value: forecast.projectedFinalSpend.masked(hideBalances, code: currencyCode), tint: statusTint)
                    ForecastMetricTile(title: "Recomendación diaria", value: forecast.dailyRecommendation.masked(hideBalances, code: currencyCode), tint: .financeAccent)
                }
            }
            .padding(16)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(forecast.accessibilitySummary(currencyCode: currencyCode, hidesAmounts: hideBalances))

            categoryForecastNotice
        }
    }

    private var categoryForecastNotice: some View {
        Label(
            "La previsión se calcula sobre el presupuesto total. Por categoría mostramos solo gasto real para no extrapolar gastos puntuales.",
            systemImage: "info.circle.fill"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MonthlyBudgetLargeChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let forecast: MonthlyBudgetForecast
    let currencyCode: String
    let hideBalances: Bool
    private let chartMaxValueDouble: Double

    init(forecast: MonthlyBudgetForecast, currencyCode: String, hideBalances: Bool) {
        self.forecast = forecast
        self.currencyCode = currencyCode
        self.hideBalances = hideBalances
        self.chartMaxValueDouble = Self.makeChartMaxValueDouble(for: forecast)
    }

    private var statusTint: Color {
        BudgetColorPalette.status(for: forecast.status, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                MonthlyBudgetMiniChart(
                    forecast: forecast,
                    tint: statusTint,
                    maxValueOverride: chartMaxValueDouble
                )
                    .padding(.top, 4)

                chartScaleLabels
                    .frame(width: 72, alignment: .trailing)
            }

            HStack(spacing: 12) {
                ForecastLegendItem(label: "Ideal", tint: .secondary, dashed: true)
                ForecastLegendItem(label: "Real", tint: statusTint, dashed: false)
                ForecastLegendItem(label: "Proyección", tint: statusTint, dashed: true)
            }
            .font(.caption2.weight(.medium))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gráfica acumulada de gasto mensual")
        .accessibilityValue("\(forecast.fullMessage) Escala de 0 a \(chartMaxValue.masked(hideBalances, code: currencyCode)).")
    }

    private var chartMaxValue: Decimal {
        Decimal(chartMaxValueDouble)
    }

    private static func makeChartMaxValueDouble(for forecast: MonthlyBudgetForecast) -> Double {
        let projectedMax = forecast.projectedPoints
            .filter { !$0.isNaN && $0.isFinite }
            .max() ?? 0
        let rawMax = max(
            (forecast.budgetAmount as NSDecimalNumber).doubleValue,
            projectedMax,
            1
        )
        return NSDecimalNumber(decimal: Decimal(rawMax).roundedUpToNiceChartStep()).doubleValue
    }

    private var chartScaleLabels: some View {
        VStack(alignment: .trailing) {
            Text(chartMaxValue.masked(hideBalances, code: currencyCode))
            Spacer()
            Text((chartMaxValue / 2).masked(hideBalances, code: currencyCode))
            Spacer()
            Text(Decimal(0).masked(hideBalances, code: currencyCode))
        }
        .font(.caption2.weight(.medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.55)
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

private struct ForecastLegendItem: View {
    let label: String
    let tint: Color
    let dashed: Bool

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: dashed ? 14 : 18, height: dashed ? 3 : 4)
                .opacity(dashed ? 0.72 : 1)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

private extension Decimal {
    func roundedUpToNiceChartStep() -> Decimal {
        let value = NSDecimalNumber(decimal: self).doubleValue
        guard value.isFinite, value > 0 else { return 1 }

        let magnitude = pow(10, floor(log10(value)))
        let normalized = value / magnitude
        let niceNormalized: Double

        switch normalized {
        case ...1:
            niceNormalized = 1
        case ...2:
            niceNormalized = 2
        case ...5:
            niceNormalized = 5
        default:
            niceNormalized = 10
        }

        return Decimal(niceNormalized * magnitude)
    }
}

private struct ForecastMetricTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Budget Item Row

private struct BudgetItemRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let item: BudgetItem
    let spent: Decimal
    let currencyCode: String
    let onTap: (() -> Void)?

    private var progress: Double {
        guard item.allocatedAmount > 0 else { return 0 }
        let p = (spent as NSDecimalNumber).doubleValue /
                (item.allocatedAmount as NSDecimalNumber).doubleValue
        return min(p, 1)
    }

    private var progressColor: Color {
        BudgetColorPalette.progress(for: progress, colorScheme: colorScheme)
    }

    private var remaining: Decimal { item.allocatedAmount - spent }

    @ViewBuilder
    var body: some View {
        if let onTap {
            Button(action: onTap) {
                cardContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Muestra los gastos de esta categoría del mes actual")
        } else {
            cardContent
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let cat = item.category {
                    if let emoji = cat.emoji {
                        Text(emoji)
                            .font(.subheadline)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: cat.iconName)
                            .font(.subheadline)
                            .foregroundStyle(cat.color.categoryForegroundColor(in: colorScheme))
                            .frame(width: 22)
                    }
                }

                Text(item.category?.name ?? "Sin categoría")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Text(spent.masked(hideBalances, code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(progress >= 1 ? .red : .primary)

                Text("/ \(item.allocatedAmount.masked(hideBalances, code: currencyCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(progress * 100)) % consumido")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if remaining > 0 {
                    Text("Quedan \(remaining.masked(hideBalances, code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if remaining < 0 {
                    Text("Superado \((-remaining).masked(hideBalances, code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Asignación agotada")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    progress >= 1
                        ? Color.red.opacity(0.4)
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12)),
                    lineWidth: 1
                )
        )
    }
}
