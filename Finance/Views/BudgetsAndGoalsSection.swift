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

                    Text("Controla tus gastos por categoria")
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
                BudgetDetailView(budget: budget, movements: movements, currencyCode: currencyCode)
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

// MARK: - Budget Summary Card (en ChartsView)

private struct BudgetSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let budget: Budget
    let movements: [Movement]
    let currencyCode: String

    private var spent: Decimal {
        BudgetService.totalSpent(for: budget, movements: movements)
    }

    private var progress: Double {
        guard budget.totalAmount > 0 else { return 0 }
        let p = (spent as NSDecimalNumber).doubleValue /
                (budget.totalAmount as NSDecimalNumber).doubleValue
        return min(p, 1)
    }

    private var progressColor: Color {
        switch progress {
        case ..<0.6:  return .green
        case ..<0.8:  return .yellow
        case ..<1.0:  return .orange
        default:      return .red
        }
    }

    private var remaining: Decimal { budget.totalAmount - spent }

    private var isAlerting: Bool {
        BudgetService.isAlerting(budget: budget, movements: movements)
    }

    private var isOverBudget: Bool {
        progress >= 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isAlerting {
                HStack(spacing: 8) {
                    Image(systemName: isOverBudget ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(isOverBudget ? "Presupuesto superado" : "Alerta de presupuesto")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(isOverBudget ? "Revisa tus categorias" : "Has alcanzado el 80 %")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(isOverBudget ? Color.red : Color.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background((isOverBudget ? Color.red : Color.orange).opacity(colorScheme == .dark ? 0.16 : 0.12))
                .clipShape(Capsule())
            }

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

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(progressColor)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                Text("\(Int(progress * 100)) % consumido")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if remaining > 0 {
                    Text("Quedan \(remaining.masked(hideBalances, code: currencyCode))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else if remaining < 0 {
                    Text("Superado \((-remaining).masked(hideBalances, code: currencyCode))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                } else {
                    Text("Presupuesto agotado")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }

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

    private var totalSpent: Decimal {
        BudgetService.totalSpent(for: budget, movements: movements)
    }

    private var globalProgress: Double {
        guard budget.totalAmount > 0 else { return 0 }
        let p = (totalSpent as NSDecimalNumber).doubleValue /
                (budget.totalAmount as NSDecimalNumber).doubleValue
        return min(p, 1)
    }

    private var remaining: Decimal { budget.totalAmount - totalSpent }

    private var sortedItems: [BudgetItem] {
        budget.items
            .filter { $0.category != nil }
            .sorted { ($0.category?.name ?? "") < ($1.category?.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    globalCard
                    categoryBreakdown
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

    private var globalCard: some View {
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
    private var categoryBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Por categoría", systemImage: "list.bullet.rectangle")
                .font(.headline)
                .foregroundStyle(.primary)

            if sortedItems.isEmpty {
                Text("No hay categorías definidas en este presupuesto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(sortedItems) { item in
                        BudgetItemRow(item: item, movements: movements, currencyCode: currencyCode)
                    }
                }
            }
        }
    }
}

// MARK: - Budget Item Row

private struct BudgetItemRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let item: BudgetItem
    let movements: [Movement]
    let currencyCode: String

    private var spent: Decimal {
        guard let cat = item.category else { return 0 }
        return BudgetService.spentAmount(for: cat, movements: movements)
    }

    private var progress: Double {
        guard item.allocatedAmount > 0 else { return 0 }
        let p = (spent as NSDecimalNumber).doubleValue /
                (item.allocatedAmount as NSDecimalNumber).doubleValue
        return min(p, 1)
    }

    private var progressColor: Color {
        switch progress {
        case ..<0.6:  return .green
        case ..<0.8:  return .yellow
        case ..<1.0:  return .orange
        default:      return .red
        }
    }

    private var remaining: Decimal { item.allocatedAmount - spent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let cat = item.category {
                    Image(systemName: cat.iconName)
                        .font(.subheadline)
                        .foregroundStyle(cat.color)
                        .frame(width: 22)
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
