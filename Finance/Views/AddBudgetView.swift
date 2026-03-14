//
//  AddBudgetView.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import SwiftUI
import SwiftData

// MARK: - Draft item (in-memory while editing)

private struct DraftItem: Identifiable {
    let id = UUID()
    var category: MovementCategory
    var amountText: String

    var parsedAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let v = Decimal(string: normalized), v > 0 else { return nil }
        return v
    }
}

// MARK: - AddBudgetView

/// Formulario para crear o editar el presupuesto mensual único.
struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @Query(sort: \MovementCategory.name) private var allCategories: [MovementCategory]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]

    private let budgetToEdit: Budget?

    // MARK: State

    @State private var totalText: String = ""
    @State private var notifyAt80: Bool = true
    @State private var notifyAt100: Bool = true
    @State private var isActive: Bool = true

    /// Líneas de distribución por categoría.
    @State private var draftItems: [DraftItem] = []

    /// Picker de categoría para añadir nueva línea.
    @State private var categoryToAdd: MovementCategory? = nil
    @State private var showingAddItemPicker = false

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    init(budgetToEdit: Budget? = nil) {
        self.budgetToEdit = budgetToEdit
    }

    private var isEditing: Bool { budgetToEdit != nil }

    // MARK: - Derived values

    private var parsedTotal: Decimal? {
        let normalized = totalText.replacingOccurrences(of: ",", with: ".")
        guard let v = Decimal(string: normalized), v > 0 else { return nil }
        return v
    }

    private var allocatedSum: Decimal {
        draftItems.compactMap(\.parsedAmount).reduce(0, +)
    }

    private var remaining: Decimal {
        (parsedTotal ?? 0) - allocatedSum
    }

    private var allocationProgress: Double {
        guard let total = parsedTotal, total > 0 else { return 0 }
        let ratio = (allocatedSum as NSDecimalNumber).doubleValue /
                    (total as NSDecimalNumber).doubleValue
        return min(ratio, 1)
    }

    /// Categorías que todavía no están en la lista de ítems.
    private var availableCategories: [MovementCategory] {
        let usedIDs = Set(draftItems.map { $0.category.id })
        return allCategories.filter { !usedIDs.contains($0.id) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                totalSection
                allocationSection
                notificationsSection
                statusSection
            }
            .financeGlassListContainer()
            .navigationTitle(isEditing ? "Editar presupuesto" : "Presupuesto mensual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadExistingData() }
            .sheet(isPresented: $showingAddItemPicker) {
                categoryPickerSheet
            }
            .alert("Campos requeridos", isPresented: $showingValidationAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    // MARK: - Sections

    private var totalSection: some View {
        Section {
            HStack {
                TextField("0,00", text: $totalText)
                    .keyboardType(.decimalPad)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(appCurrencyCode)
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Presupuesto total mensual")
        } footer: {
            Text("Importe global que tienes disponible para gastar este mes.")
        }
    }

    private var allocationSection: some View {
        Section {
            // Progress bar + remaining indicator
            if parsedTotal != nil {
                allocationProgressView
            }

            // Draft items
            ForEach($draftItems) { $item in
                HStack(spacing: 10) {
                    Image(systemName: item.category.iconName)
                        .foregroundStyle(item.category.color)
                        .frame(width: 22)

                    Text(item.category.name)
                        .lineLimit(1)

                    Spacer()

                    TextField("0,00", text: $item.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)

                    Text(appCurrencyCode)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .onDelete { indexSet in
                draftItems.remove(atOffsets: indexSet)
            }

            // Add category button
            if !availableCategories.isEmpty {
                Button {
                    showingAddItemPicker = true
                } label: {
                    Label("Añadir categoría", systemImage: "plus.circle.fill")
                        .foregroundStyle(.tint)
                }
            }

        } header: {
            Text("Distribución por categorías")
        } footer: {
            if parsedTotal != nil {
                allocationFooterText
            }
        }
    }

    @ViewBuilder
    private var allocationProgressView: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.15))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(progressBarColor)
                        .frame(width: max(0, geo.size.width * allocationProgress))
                        .animation(.easeInOut(duration: 0.3), value: allocationProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("Asignado: \(allocatedSum.asCurrency(code: appCurrencyCode)) / \(parsedTotal?.asCurrency(code: appCurrencyCode) ?? "-")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if remaining != 0 {
                    Text(remaining > 0
                         ? "Quedan \(remaining.asCurrency(code: appCurrencyCode))"
                         : "Exceso: \((-remaining).asCurrency(code: appCurrencyCode))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(remaining < 0 ? .red : .secondary)
                } else {
                    Text("Distribución completa")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var progressBarColor: Color {
        if remaining < 0 { return .red }
        if remaining == 0 { return .green }
        return .blue
    }

    @ViewBuilder
    private var allocationFooterText: some View {
        if draftItems.isEmpty {
            Text("Añade al menos una categoría y asígnale su importe.")
        } else if remaining < 0 {
            Text("La suma de categorías supera el total. Ajusta los importes.")
                .foregroundStyle(.red)
        } else if remaining > 0 {
            Text("Quedan \(remaining.asCurrency(code: appCurrencyCode)) sin asignar. La suma debe ser igual al total.")
        } else {
            Text("Perfecto: todas las categorías suman el total del presupuesto.")
        }
    }

    private var notificationsSection: some View {
        Section("Notificaciones por categoría") {
            Toggle("Aviso al 80 %", isOn: $notifyAt80)
            Toggle("Aviso al 100 %", isOn: $notifyAt100)
            Text("Recibirás una notificación cuando el gasto real de cada categoría alcance estos umbrales respecto a su asignación.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section("Estado") {
            Toggle("Presupuesto activo", isOn: $isActive)
        }
    }

    // MARK: - Category picker sheet

    private var categoryPickerSheet: some View {
        NavigationStack {
            List(availableCategories) { cat in
                Button {
                    draftItems.append(DraftItem(category: cat, amountText: ""))
                    showingAddItemPicker = false
                } label: {
                    Label(cat.name, systemImage: cat.iconName)
                        .foregroundStyle(.primary)
                }
            }
            .financeGlassListContainer()
            .navigationTitle("Seleccionar categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showingAddItemPicker = false }
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadExistingData() {
        guard let b = budgetToEdit else { return }
        totalText   = formatAmount(b.totalAmount)
        notifyAt80  = b.notifyAt80Percent
        notifyAt100 = b.notifyAt100Percent
        isActive    = b.isActive
        draftItems  = b.items
            .sorted { ($0.createdAt) < ($1.createdAt) }
            .compactMap { item in
                guard let cat = item.category else { return nil }
                return DraftItem(category: cat, amountText: formatAmount(item.allocatedAmount))
            }
    }

    private func formatAmount(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Save

    private func save() {
        guard let total = parsedTotal else {
            validationMessage = "Introduce un importe total mayor que 0."
            showingValidationAlert = true
            return
        }

        guard !draftItems.isEmpty else {
            validationMessage = "Añade al menos una categoría al presupuesto."
            showingValidationAlert = true
            return
        }

        // Validate all items have a valid amount
        for item in draftItems {
            guard item.parsedAmount != nil else {
                validationMessage = "El importe de \"\(item.category.name)\" debe ser mayor que 0."
                showingValidationAlert = true
                return
            }
        }

        // Validate sum == total
        let sum = draftItems.compactMap(\.parsedAmount).reduce(Decimal(0), +)
        guard sum == total else {
            let diff = total - sum
            if diff > 0 {
                validationMessage = "La suma de categorías (\(sum.asCurrency(code: appCurrencyCode))) es menor que el total (\(total.asCurrency(code: appCurrencyCode))). Faltan \(diff.asCurrency(code: appCurrencyCode)) por asignar."
            } else {
                validationMessage = "La suma de categorías (\(sum.asCurrency(code: appCurrencyCode))) supera el total (\(total.asCurrency(code: appCurrencyCode))). Reduce alguna categoría en \((-diff).asCurrency(code: appCurrencyCode))."
            }
            showingValidationAlert = true
            return
        }

        let savedBudget: Budget

        if let b = budgetToEdit {
            // Cancel existing item notifications before replacing items
            BudgetService.cancelAllNotifications(for: b)

            b.totalAmount       = total
            b.notifyAt80Percent = notifyAt80
            b.notifyAt100Percent = notifyAt100
            b.isActive          = isActive
            b.updatedAt         = Date()

            // Remove old items and replace with new ones
            for old in b.items { modelContext.delete(old) }
            b.items = buildBudgetItems(for: b)
            savedBudget = b
        } else {
            let budget = Budget(
                totalAmount: total,
                isActive: isActive,
                notifyAt80Percent: notifyAt80,
                notifyAt100Percent: notifyAt100
            )
            modelContext.insert(budget)
            budget.items = buildBudgetItems(for: budget)
            savedBudget = budget
        }

        if savedBudget.isActive && (savedBudget.notifyAt80Percent || savedBudget.notifyAt100Percent) {
            BudgetService.evaluateAndNotify(budget: savedBudget, movements: movements)
        }

        dismiss()
    }

    private func buildBudgetItems(for budget: Budget) -> [BudgetItem] {
        draftItems.compactMap { draft in
            guard let amount = draft.parsedAmount else { return nil }
            let item = BudgetItem(allocatedAmount: amount, category: draft.category)
            item.budget = budget
            modelContext.insert(item)
            return item
        }
    }
}
