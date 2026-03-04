//
//  BudgetsAndGoalsSection.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Budgets Section

/// Sección de presupuestos mensuales para ChartsView.
struct BudgetsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let budgets: [Budget]
    let movements: [Movement]
    let currencyCode: String

    @State private var showingAddBudget = false
    @State private var budgetToEdit: Budget?
    @State private var budgetToDelete: Budget?
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Presupuestos", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    showingAddBudget = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .accessibilityLabel("Añadir presupuesto")
            }

            if budgets.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(activeBudgets) { budget in
                        BudgetProgressRow(
                            budget: budget,
                            movements: movements,
                            currencyCode: currencyCode
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { budgetToEdit = budget }
                        .contextMenu {
                            Button {
                                budgetToEdit = budget
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                budgetToDelete = budget
                                showingDeleteConfirm = true
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }

                    if activeBudgets.count < budgets.count {
                        Text("\(budgets.count - activeBudgets.count) presupuesto\(budgets.count - activeBudgets.count == 1 ? "" : "s") pausado\(budgets.count - activeBudgets.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddBudget) {
            AddBudgetView()
        }
        .sheet(item: $budgetToEdit) { budget in
            AddBudgetView(budgetToEdit: budget)
        }
        .confirmationDialog(
            "Eliminar presupuesto",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let b = budgetToDelete {
                    BudgetService.cancelAllNotifications(for: b)
                    modelContext.delete(b)
                }
                budgetToDelete = nil
            }
            Button("Cancelar", role: .cancel) { budgetToDelete = nil }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
    }

    private var activeBudgets: [Budget] {
        budgets.filter(\.isActive)
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
                    Text("Añade tu primer presupuesto")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("Controla el gasto mensual por categoría.")
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

// MARK: - Budget Progress Row

private struct BudgetProgressRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let budget: Budget
    let movements: [Movement]
    let currencyCode: String

    private var spent: Decimal {
        guard let cat = budget.category else { return 0 }
        return BudgetService.spentAmount(for: cat, movements: movements)
    }

    private var progress: Double {
        guard budget.limitAmount > 0 else { return 0 }
        let p = (spent as NSDecimalNumber).doubleValue /
                (budget.limitAmount as NSDecimalNumber).doubleValue
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let cat = budget.category {
                    Image(systemName: cat.iconName)
                        .font(.subheadline)
                        .foregroundStyle(cat.color)
                        .frame(width: 22)
                }

                Text(budget.category?.name ?? "Sin categoría")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Text(spent.asCurrency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(progress >= 1 ? .red : .primary)

                Text("/ \(budget.limitAmount.asCurrency(code: currencyCode))")
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

                let remaining = budget.limitAmount - spent
                if remaining > 0 {
                    Text("Quedan \(remaining.asCurrency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Superado \((-remaining).asCurrency(code: currencyCode))")
                        .font(.caption2)
                        .foregroundStyle(.red)
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
                        ? Color.red.opacity(0.45)
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12)),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Savings Goals Section

/// Sección de objetivos de ahorro para ChartsView.
struct SavingsGoalsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let goals: [SavingsGoal]
    let currencyCode: String

    @State private var showingAddGoal = false
    @State private var goalToEdit: SavingsGoal?
    @State private var goalToDelete: SavingsGoal?
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Objetivos de ahorro", systemImage: "target")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    showingAddGoal = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .accessibilityLabel("Añadir objetivo")
            }

            if goals.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(activeGoals) { goal in
                        SavingsGoalRow(goal: goal, currencyCode: currencyCode)
                            .contentShape(Rectangle())
                            .onTapGesture { goalToEdit = goal }
                            .contextMenu {
                                Button {
                                    goalToEdit = goal
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                Button {
                                    toggleCompleted(goal)
                                } label: {
                                    Label(goal.isCompleted ? "Marcar como pendiente" : "Marcar como completado",
                                          systemImage: goal.isCompleted ? "circle" : "checkmark.circle.fill")
                                }
                                Button(role: .destructive) {
                                    goalToDelete = goal
                                    showingDeleteConfirm = true
                                } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }

                    if completedGoals.count > 0 {
                        Text("\(completedGoals.count) objetivo\(completedGoals.count == 1 ? "" : "s") completado\(completedGoals.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddSavingsGoalView()
        }
        .sheet(item: $goalToEdit) { goal in
            AddSavingsGoalView(goalToEdit: goal)
        }
        .confirmationDialog(
            "Eliminar objetivo",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let g = goalToDelete { modelContext.delete(g) }
                goalToDelete = nil
            }
            Button("Cancelar", role: .cancel) { goalToDelete = nil }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
    }

    private var activeGoals: [SavingsGoal] {
        goals.filter { !$0.isCompleted }
    }

    private var completedGoals: [SavingsGoal] {
        goals.filter(\.isCompleted)
    }

    private func toggleCompleted(_ goal: SavingsGoal) {
        goal.isCompleted = !goal.isCompleted
        goal.updatedAt = Date()
    }

    private var emptyState: some View {
        Button {
            showingAddGoal = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.dashed")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Añade tu primer objetivo")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("Vincula una cuenta y sigue tu progreso de ahorro.")
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

// MARK: - Savings Goal Row

private struct SavingsGoalRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let goal: SavingsGoal
    let currencyCode: String

    private var currentAmount: Decimal {
        goal.account?.balance ?? 0
    }

    private var progress: Double {
        guard goal.targetAmount > 0 else { return 0 }
        let p = (currentAmount as NSDecimalNumber).doubleValue /
                (goal.targetAmount as NSDecimalNumber).doubleValue
        return min(max(p, 0), 1)
    }

    private var daysRemaining: Int? {
        guard let target = goal.targetDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: target).day ?? 0
        return max(0, days)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: goal.iconName)
                    .font(.subheadline)
                    .foregroundStyle(goal.color)
                    .frame(width: 22)

                Text(goal.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Text(currentAmount.asCurrency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(progress >= 1 ? goal.color : .primary)

                Text("/ \(goal.targetAmount.asCurrency(code: currencyCode))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(goal.color)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(progress * 100)) % alcanzado")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                if let days = daysRemaining {
                    if days == 0 {
                        Text("Fecha límite hoy")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(days) día\(days == 1 ? "" : "s") restante\(days == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if goal.account == nil {
                    Text("Sin cuenta vinculada")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                        ? goal.color.opacity(0.55)
                        : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12)),
                    lineWidth: 1
                )
        )
    }
}
