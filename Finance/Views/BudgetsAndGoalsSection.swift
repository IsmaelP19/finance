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
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Presupuesto mensual", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

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
                            Label("Eliminar", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.tint)
                    }
                    .accessibilityLabel("Opciones del presupuesto")
                    let _ = budget
                } else {
                    Button {
                        showingAddBudget = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.tint)
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
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crea tu presupuesto mensual")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("Define cuánto puedes gastar y repártelo por categorías.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.blue.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Budget Summary Card (en ChartsView)

private struct BudgetSummaryCard: View {
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Amounts row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gastado este mes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(spent.asCurrency(code: currencyCode))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(progress >= 1 ? .red : .primary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(budget.totalAmount.asCurrency(code: currencyCode))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(progressColor)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 7)

            // Footer
            HStack {
                Text("\(Int(progress * 100)) % consumido")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if remaining > 0 {
                    Text("Quedan \(remaining.asCurrency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if remaining < 0 {
                    Text("Superado \((-remaining).asCurrency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Presupuesto agotado")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    progress >= 1
                        ? Color.red.opacity(0.4)
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12)),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Budget Detail View

/// Vista de detalle del presupuesto: barra global + desglose por categoría.
struct BudgetDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

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
                    Text(totalSpent.asCurrency(code: currencyCode))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                    Text(budget.totalAmount.asCurrency(code: currencyCode))
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
                    Text("Quedan \(remaining.asCurrency(code: currencyCode))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                } else if remaining < 0 {
                    Text("Superado \((-remaining).asCurrency(code: currencyCode))")
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

                Text(spent.asCurrency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(progress >= 1 ? .red : .primary)

                Text("/ \(item.allocatedAmount.asCurrency(code: currencyCode))")
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
                    Text("Quedan \(remaining.asCurrency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if remaining < 0 {
                    Text("Superado \((-remaining).asCurrency(code: currencyCode))")
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
