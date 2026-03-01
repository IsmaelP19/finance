//
//  MovementsView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData

private struct AccountFilterBankGroup: Identifiable {
    let id: String
    let bankName: String
    let accounts: [BankAccount]
}

private enum MovementListTypeFilter: String, CaseIterable, Identifiable {
    case all
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .all: return .gray
        case .expense: return .red
        case .income: return .green
        case .transfer: return .blue
        }
    }

    var title: String {
        switch self {
        case .all: return "Todos"
        case .expense: return "Gastos"
        case .income: return "Ingresos"
        case .transfer: return "Transferencias"
        }
    }

    func matches(_ type: MovementType) -> Bool {
        switch self {
        case .all: return true
        case .expense: return type == .expense
        case .income: return type == .income
        case .transfer: return type == .transfer
        }
    }
}

private enum MovementCategoryFilter: Hashable {
    case category(UUID)
}

/// Pantalla principal de movimientos (gastos e ingresos).
struct MovementsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]

    @State private var showingAddMovement = false
    @State private var showingEditMovement = false
    @State private var movementToEdit: Movement?
    @State private var selectedAccountFilterID: UUID?
    @State private var selectedTypeFilter: MovementListTypeFilter = .all
    @State private var selectedCategoryFilters: Set<MovementCategoryFilter> = []
    @State private var searchText = ""
    @State private var showingPendingAlert = false
    @State private var pendingAlertMessage = ""

    private var accountFilteredMovements: [Movement] {
        guard let selectedAccountFilterID else { return movements }
        return movements.filter {
            $0.account?.id == selectedAccountFilterID || $0.destinationAccount?.id == selectedAccountFilterID
        }
    }

    private var typeFilteredMovements: [Movement] {
        accountFilteredMovements.filter { selectedTypeFilter.matches($0.type) }
    }

    private var filteredMovements: [Movement] {
        let categoryFiltered: [Movement]
        if selectedTypeFilter == .transfer {
            categoryFiltered = typeFilteredMovements
        } else if selectedCategoryFilters.isEmpty {
            categoryFiltered = typeFilteredMovements
        } else {
            categoryFiltered = typeFilteredMovements.filter { movement in
                guard let categoryID = movement.category?.id else { return false }
                return selectedCategoryFilters.contains(.category(categoryID))
            }
        }

        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return categoryFiltered }

        return categoryFiltered.filter { matchesSearch($0, query: trimmedQuery) }
    }

    private var categoryFilterOptions: [(id: MovementCategoryFilter, title: String, color: Color)] {
        var options: [(MovementCategoryFilter, String, Color)] = []

        let grouped = Dictionary(grouping: typeFilteredMovements.compactMap { $0.category }) { $0.id }
        let sortedCategories = grouped.values
            .compactMap { $0.first }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        options += sortedCategories.map { category in
            (MovementCategoryFilter.category(category.id), category.name, category.color)
        }

        return options
    }

    private var accountsSortedByBankThenName: [BankAccount] {
        accounts.sorted { lhs, rhs in
            let bankComparison = lhs.bankDisplayName.localizedCaseInsensitiveCompare(rhs.bankDisplayName)
            if bankComparison != .orderedSame {
                return bankComparison == .orderedAscending
            }

            let accountComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if accountComparison != .orderedSame {
                return accountComparison == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var groupedAccountsByBank: [AccountFilterBankGroup] {
        let grouped = Dictionary(grouping: accountsSortedByBankThenName) { account in
            account.bank?.id.uuidString ?? "no-bank"
        }

        return grouped
            .compactMap { key, groupedAccounts in
                guard let first = groupedAccounts.first else { return nil }
                return AccountFilterBankGroup(id: key, bankName: first.bankDisplayName, accounts: groupedAccounts)
            }
            .sorted { lhs, rhs in
                lhs.bankName.localizedCaseInsensitiveCompare(rhs.bankName) == .orderedAscending
            }
    }

    private var pendingRecurringMovements: [PendingRecurringMovement] {
        let allPending = RecurringMovementService.pendingMovements(
            for: recurringMovements,
            confirmedMovements: movements,
            horizonDays: 5
        )

        guard let selectedAccountFilterID else {
            return allPending
        }

        return allPending.filter { pending in
            pending.rule.account?.id == selectedAccountFilterID
        }
    }

    private var totalIncome: Decimal {
        filteredMovements
            .filter { $0.type == .income }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var totalExpense: Decimal {
        filteredMovements
            .filter { $0.type == .expense }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var netBalance: Decimal {
        totalIncome - totalExpense
    }

    private var movementCount: Int {
        filteredMovements.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !movements.isEmpty {
                    filtersHeader
                        .padding(.bottom, 8)
                }

                List {
                    if !accounts.isEmpty {
                        Section {
                            Picker("Cuenta", selection: $selectedAccountFilterID) {
                                Text("Todas las cuentas")
                                    .tag(nil as UUID?)

                                ForEach(groupedAccountsByBank) { bankGroup in
                                    Section(bankGroup.bankName) {
                                        ForEach(bankGroup.accounts, id: \.id) { account in
                                            Text(account.name)
                                                .tag(Optional(account.id))
                                        }
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    if !movements.isEmpty {
                        Section {
                            MovementSummaryView(
                                totalIncome: totalIncome,
                                totalExpense: totalExpense,
                                netBalance: netBalance,
                                movementCount: movementCount,
                                currencyCode: appCurrencyCode
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }

                    if !pendingRecurringMovements.isEmpty {
                        Section {
                            ForEach(pendingRecurringMovements) { pending in
                                PendingRecurringMovementRowView(
                                    pending: pending,
                                    currencyCode: appCurrencyCode
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        confirmPendingRecurring(pending)
                                    } label: {
                                        Label("Confirmar", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.green)
                                }

                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        cancelPendingRecurring(pending.rule)
                                    } label: {
                                        Label("Cancelar", systemImage: "xmark.circle")
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("Próximos recurrentes")
                                Spacer()
                                Text("\(pendingRecurringMovements.count)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    if movements.isEmpty && pendingRecurringMovements.isEmpty {
                        ContentUnavailableView(
                            accounts.isEmpty ? "Sin cuentas" : "Sin movimientos",
                            systemImage: accounts.isEmpty ? "building.columns" : "arrow.left.arrow.right.circle",
                            description: Text(accounts.isEmpty
                                              ? "Crea al menos una cuenta en Inicio para registrar movimientos"
                                              : "Pulsa + para registrar tu primer gasto, ingreso o transferencia")
                        )
                        .listRowBackground(Color.clear)
                    } else if !movements.isEmpty && filteredMovements.isEmpty {
                        ContentUnavailableView(
                            "Sin movimientos con estos filtros",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Ajusta cuenta, tipo o búsqueda para ver más resultados")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredMovements, id: \.id) { movement in
                            MovementRowView(movement: movement, currencyCode: appCurrencyCode)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    movementToEdit = movement
                                    showingEditMovement = true
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        movementToEdit = movement
                                        showingEditMovement = true
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                        .onDelete(perform: deleteMovements)
                    }
                }
            }
            .navigationTitle("Movimientos")
            .searchable(text: $searchText, prompt: "Buscar movimientos")
            .onChange(of: selectedTypeFilter) { _, newValue in
                if newValue == .transfer {
                    selectedCategoryFilters.removeAll()
                } else {
                    pruneCategorySelections()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddMovement = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddMovement) {
                AddMovementView()
            }
            .sheet(isPresented: $showingEditMovement, onDismiss: {
                movementToEdit = nil
            }) {
                if let movementToEdit {
                    AddMovementView(movementToEdit: movementToEdit)
                }
            }
            .alert("Acción no disponible", isPresented: $showingPendingAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(pendingAlertMessage)
            }
        }
    }

    private func deleteMovements(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let movement = filteredMovements[index]
                if let account = movement.account {
                    switch movement.type {
                    case .expense:
                        account.balance += movement.amount
                    case .income:
                        account.balance -= movement.amount
                    case .transfer:
                        account.balance += movement.amount
                        if let destination = movement.destinationAccount {
                            destination.balance -= movement.amount
                            destination.updatedAt = Date()
                        }
                    }

                    account.updatedAt = Date()
                }
                modelContext.delete(movement)
            }
        }
    }

    private func confirmPendingRecurring(_ pending: PendingRecurringMovement) {
        guard pending.rule.type != .transfer else {
            pendingAlertMessage = "Las transferencias no se pueden confirmar como recurrentes."
            showingPendingAlert = true
            return
        }

        guard let account = pending.rule.account else {
            pendingAlertMessage = "La cuenta asociada ya no está disponible. Edita la recurrencia para continuar."
            showingPendingAlert = true
            return
        }

        guard !RecurringMovementService.isOccurrenceConfirmed(
            ruleID: pending.rule.id,
            dueDate: pending.dueDate,
            movements: movements
        ) else {
            return
        }

        let resultingBalance = applyRecurringImpact(
            type: pending.rule.type,
            amount: pending.rule.amount,
            account: account
        )

        let movement = Movement(
            concept: pending.rule.concept,
            amount: pending.rule.amount,
            type: pending.rule.type,
            occurredAt: pending.dueDate,
            account: account,
            destinationAccount: nil,
            category: pending.rule.category,
            notes: pending.rule.notes,
            resultingBalance: resultingBalance,
            recurringRuleId: pending.rule.id,
            recurringScheduledAt: pending.dueDate
        )

        withAnimation {
            modelContext.insert(movement)
            pending.rule.updatedAt = Date()
        }

        HapticFeedback.success()
    }

    private func cancelPendingRecurring(_ recurring: RecurringMovement) {
        withAnimation {
            recurring.isActive = false
            recurring.updatedAt = Date()
        }
    }

    @discardableResult
    private func applyRecurringImpact(type: MovementType, amount: Decimal, account: BankAccount) -> Decimal {
        account.currency = appCurrencyCode

        switch type {
        case .expense:
            account.balance -= amount
        case .income:
            account.balance += amount
        case .transfer:
            break
        }

        account.updatedAt = Date()
        return account.balance
    }

    private func matchesSearch(_ movement: Movement, query: String) -> Bool {
        let normalizedQuery = normalizeForSearch(query)
        guard !normalizedQuery.isEmpty else { return true }

        let currencyAmount = movement.amount.asCurrency(code: appCurrencyCode)
        let rawAmount = NSDecimalNumber(decimal: movement.amount).stringValue
        let signedRawAmount = NSDecimalNumber(decimal: movement.signedAmount).stringValue

        let candidates: [String] = [
            movement.concept,
            movement.notes,
            movement.type.displayName,
            movement.category?.name ?? "",
            movement.account?.name ?? "",
            movement.account?.bankDisplayName ?? "",
            movement.destinationAccount?.name ?? "",
            movement.destinationAccount?.bankDisplayName ?? "",
            movement.occurredAt.asSpanishShortDate(),
            movement.occurredAt.asSpanishDateTime(),
            currencyAmount,
            rawAmount,
            signedRawAmount,
            rawAmount.replacingOccurrences(of: ".", with: ","),
            signedRawAmount.replacingOccurrences(of: ".", with: ",")
        ]

        return candidates
            .map(normalizeForSearch)
            .contains { $0.contains(normalizedQuery) }
    }

    private func normalizeForSearch(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtersHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MovementListTypeFilter.allCases) { filter in
                        MovementFilterChip(
                            title: filter.title,
                            color: filter.color,
                            isSelected: selectedTypeFilter == filter,
                            action: { selectedTypeFilter = filter }
                        )
                    }
                }
                .padding(.leading, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if selectedTypeFilter != .transfer {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        MovementFilterChip(
                            title: "Todas",
                            color: .gray,
                            isSelected: selectedCategoryFilters.isEmpty,
                            action: { selectedCategoryFilters.removeAll() }
                        )

                        ForEach(categoryFilterOptions, id: \.id) { option in
                            MovementFilterChip(
                                title: option.title,
                                color: option.color,
                                isSelected: selectedCategoryFilters.contains(option.id),
                                action: { toggleCategoryFilter(option.id) }
                            )
                        }
                    }
                    .padding(.leading, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleCategoryFilter(_ filter: MovementCategoryFilter) {
        if selectedCategoryFilters.contains(filter) {
            selectedCategoryFilters.remove(filter)
        } else {
            selectedCategoryFilters.insert(filter)
        }
    }

    private func pruneCategorySelections() {
        let validFilters = Set(categoryFilterOptions.map { $0.id })
        selectedCategoryFilters = selectedCategoryFilters.intersection(validFilters)
    }
}

private struct MovementFilterChip: View {
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? color : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected
                    ? color.opacity(0.16)
                    : Color.secondary.opacity(0.12)
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? color.opacity(0.28) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MovementSummaryView: View {
    let totalIncome: Decimal
    let totalExpense: Decimal
    let netBalance: Decimal
    let movementCount: Int
    let currencyCode: String

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SummaryPill(title: "Ingresos", value: totalIncome.asCurrency(code: currencyCode), color: .green)
                SummaryPill(title: "Gastos", value: totalExpense.asCurrency(code: currencyCode), color: .red)
            }

            HStack {
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(netBalance.asCurrency(code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(netBalance >= 0 ? .green : .red)
            }

            HStack {
                Text("Movimientos")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(movementCount)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct PendingRecurringMovementRowView: View {
    let pending: PendingRecurringMovement
    let currencyCode: String

    private var dueDateLabel: String {
        switch pending.status {
        case .overdue:
            return "Vencido · \(pending.dueDate.asSpanishShortDate())"
        case .dueToday:
            return "Vence hoy"
        case .upcoming:
            return "Vence \(pending.dueDate.asSpanishShortDate())"
        }
    }

    private var statusColor: Color {
        switch pending.status {
        case .overdue:
            return .red
        case .dueToday:
            return .orange
        case .upcoming:
            return .blue
        }
    }

    private var amountText: String {
        switch pending.rule.type {
        case .expense, .income:
            return (pending.rule.amount * pending.rule.type.signMultiplier).asCurrency(code: currencyCode)
        case .transfer:
            return pending.rule.amount.asCurrency(code: currencyCode)
        }
    }

    private var accountName: String {
        pending.rule.account?.name ?? "Cuenta no disponible"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pending.rule.type.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(pending.rule.type.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(pending.rule.concept)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let category = pending.rule.category {
                    CategoryChipView(
                        name: category.name,
                        iconName: category.iconName,
                        color: category.color
                    )
                }

                Text(accountName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(dueDateLabel)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(pending.rule.type == .expense ? .red : .green)

                Text(pending.status.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MovementRowView: View {
    let movement: Movement
    let currencyCode: String

    private var accountAndBankText: String {
        let accountText = movement.account?.name ?? "Sin cuenta"
        if movement.type == .transfer {
            let destinationText = movement.destinationAccount?.name ?? "Sin cuenta destino"
            return "\(accountText) -> \(destinationText)"
        }
        return accountText
    }

    private var balanceAfterText: String? {
        guard let resultingBalance = movement.resultingBalance else { return nil }
        return "Saldo: \(resultingBalance.asCurrency(code: currencyCode))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: movement.type.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(movement.type.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(movement.concept)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if movement.type == .transfer {
                    CategoryChipView(
                        name: "Transferencia",
                        iconName: "arrow.left.arrow.right",
                        color: .blue
                    )
                } else {
                    CategoryChipView(
                        name: movement.category?.name ?? "Sin categoría",
                        iconName: movement.category?.iconName ?? "tag",
                        color: movement.category?.color ?? .secondary
                    )
                }

                Text(accountAndBankText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let balanceAfterText {
                    Text(balanceAfterText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(displayAmount)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(displayAmountColor)

                Text(movement.occurredAt.asSpanishShortDate())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var displayAmount: String {
        switch movement.type {
        case .expense, .income:
            return movement.signedAmount.asCurrency(code: currencyCode)
        case .transfer:
            return movement.amount.asCurrency(code: currencyCode)
        }
    }

    private var displayAmountColor: Color {
        switch movement.type {
        case .expense:
            return .red
        case .income:
            return .green
        case .transfer:
            return .blue
        }
    }
}
