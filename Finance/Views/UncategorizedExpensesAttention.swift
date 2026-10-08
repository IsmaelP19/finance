//
//  UncategorizedExpensesAttention.swift
//  Finance
//

import SwiftData
import SwiftUI

enum UncategorizedExpenseAttention {
    static let title = "Hay movimientos que requieren de tu atención"

    static var predicate: Predicate<Movement> {
        #Predicate<Movement> { movement in
            movement.typeRaw == "expense" && movement.category == nil
        }
    }

    static func accessibilityCount(_ count: Int) -> String {
        count == 1 ? "1 gasto sin categoría" : "\(count) gastos sin categoría"
    }
}

struct UncategorizedExpensesAttentionBanner: View {
    let count: Int
    var onDismissList: (() -> Void)?

    @State private var showingList = false

    private var attentionTint: Color {
        Color(red: 236.0 / 255.0, green: 126.0 / 255.0, blue: 0)
    }

    var body: some View {
        FinanceHomeActionBanner(
            title: UncategorizedExpenseAttention.title,
            value: nil,
            subtitle: nil,
            systemImage: "tag.slash.fill",
            pillText: "\(count)",
            tint: attentionTint,
            showsChevron: true
        ) {
            showingList = true
        }
        .accessibilityLabel("\(UncategorizedExpenseAttention.title). \(UncategorizedExpenseAttention.accessibilityCount(count))")
        .accessibilityHint("Muestra los gastos sin categoría para asignarles una")
        .sheet(isPresented: $showingList, onDismiss: {
            onDismissList?()
        }) {
            UncategorizedExpensesListView()
        }
    }
}

private struct UncategorizedExpensesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @Query(filter: UncategorizedExpenseAttention.predicate, sort: \Movement.occurredAt, order: .reverse)
    private var expenses: [Movement]

    @State private var expenseToCategorize: ExpenseCategoryRequest?
    @State private var selectedCategory: MovementCategory?
    @State private var showingCreateCategory = false

    var body: some View {
        NavigationStack {
            List {
                if expenses.isEmpty {
                    FinanceEmptyStateContent(
                        "Todo categorizado",
                        systemImage: "checkmark.circle",
                        description: Text("No quedan gastos pendientes de categoría.")
                    )
                    .financeGlassClearListRow()
                } else {
                    Section {
                        ForEach(expenses, id: \.id) { expense in
                            Button {
                                selectedCategory = nil
                                expenseToCategorize = ExpenseCategoryRequest(movement: expense)
                            } label: {
                                UncategorizedExpenseRow(movement: expense, currencyCode: appCurrencyCode)
                            }
                            .buttonStyle(.plain)
                            .financeGlassClearListRow()
                        }
                    } header: {
                        FinanceGlassSectionHeader(
                            title: "Gastos sin categoría",
                            systemImage: "tag.slash.fill",
                            subtitle: "Toca un movimiento para elegir su categoría"
                        )
                    }
                }
            }
            .financeGlassPageBackground()
            .navigationTitle("Requieren atención")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $expenseToCategorize, onDismiss: {
                selectedCategory = nil
            }) { request in
                MovementCategoryPickerSheet(
                    selection: Binding(
                        get: { selectedCategory },
                        set: { category in
                            selectedCategory = category
                            if let category {
                                assign(category, to: request.movement)
                            }
                        }
                    )
                ) {
                    expenseToCategorize = nil
                    showingCreateCategory = true
                }
            }
            .sheet(isPresented: $showingCreateCategory) {
                CategoryEditorSheet()
            }
        }
    }

    private func assign(_ category: MovementCategory, to movement: Movement) {
        movement.category = category
        movement.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
        }
    }
}

private struct ExpenseCategoryRequest: Identifiable {
    let id: UUID
    let movement: Movement

    init(movement: Movement) {
        id = movement.id
        self.movement = movement
    }
}

private struct UncategorizedExpenseRow: View {
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let movement: Movement
    let currencyCode: String

    private var accountDisplayText: String? {
        guard let account = movement.account else { return nil }
        guard let bankName = account.bank?.name, !bankName.isEmpty else { return account.name }
        return "\(account.name) (\(bankName))"
    }

    var body: some View {
        HStack(spacing: 14) {
            FinanceGlassIconBadge(systemName: "tag.slash.fill", tint: .orange, size: 46)

            VStack(alignment: .leading, spacing: 6) {
                Text(movement.concept)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(movement.occurredAt.asSpanishShortDate())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let accountDisplayText {
                    Text(accountDisplayText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text(movement.amount.masked(hideBalances, code: currencyCode))
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .financeElevatedRow()
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
