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

private enum MovementListDateFilter: String, CaseIterable, Identifiable {
    case all
    case currentMonth
    case previousMonth
    case last3Months
    case currentYear
    case previousYear
    case customMonth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return "Todo"
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
        case .customMonth:
            return "Personalizado"
        }
    }
}

private struct MovementListSummary {
    var totalIncome: Decimal = 0
    var totalExpense: Decimal = 0
    var movementCount: Int = 0
}

private struct MovementEditingSelection: Identifiable {
    let id: UUID
    let movement: Movement
}

private struct MovementDetailSelection: Identifiable {
    let id: UUID
    let movement: Movement
}

/// Pantalla principal de movimientos (gastos e ingresos).
struct MovementsView: View {
    private static let movementPageSize = 20
    private static let movementFetchBatchSize = 120

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]

    @State private var showingAddMovement = false
    @State private var movementToView: MovementDetailSelection?
    @State private var movementToEdit: MovementEditingSelection?
    @State private var selectedAccountFilterID: UUID?
    @State private var selectedTypeFilter: MovementListTypeFilter = .all
    @State private var selectedCategoryFilters: Set<MovementCategoryFilter> = []
    @State private var selectedDateFilter: MovementListDateFilter = .currentMonth
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingCustomPeriodSheet = false
    @State private var customMonthDraft: Int = Calendar.current.component(.month, from: Date())
    @State private var customYearDraft: Int = Calendar.current.component(.year, from: Date())
    @State private var searchText = ""
    @State private var showingPendingAlert = false
    @State private var pendingAlertMessage = ""
    @State private var loadedMovements: [Movement] = []
    @State private var sourceFetchOffset = 0
    @State private var hasMoreSourceMovements = true
    @State private var isLoadingMovementPage = false
    @State private var pendingFilteredMovements: [Movement] = []
    @State private var hasAnyMovements = false
    @State private var summary = MovementListSummary()
    @State private var recurringConfirmationMovements: [Movement] = []
    @State private var searchReloadTask: Task<Void, Never>?
    @State private var availablePeriodYears: [Int] = [Calendar.current.component(.year, from: Date())]

    private var calendar: Calendar { .current }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var quickDateFilterChips: [MovementListDateFilter] {
        [.all, .currentMonth, .previousMonth, .last3Months, .currentYear, .previousYear]
    }

    private var activeDateInterval: DateInterval? {
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
        case .customMonth:
            return monthInterval(month: selectedMonth, year: selectedYear)
        }
    }

    private var activePeriodLabel: String {
        switch selectedDateFilter {
        case .all:
            return "Todo"
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
        case .customMonth:
            return "\(monthName(for: selectedMonth)) \(selectedYear)"
        }
    }

    private var categoryFilterOptions: [(id: MovementCategoryFilter, title: String, color: Color)] {
        categories.map { category in
            (MovementCategoryFilter.category(category.id), category.name, category.color)
        }
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
            confirmedMovements: recurringConfirmationMovements,
            horizonDays: 5
        )

        guard let selectedAccountFilterID else {
            return allPending
        }

        return allPending.filter { pending in
            pending.rule.account?.id == selectedAccountFilterID
        }
    }

    private var shouldShowExpandedPendingRecurringSection: Bool {
        selectedDateFilter == .currentMonth
    }

    private var shouldShowPendingRecurringHint: Bool {
        !shouldShowExpandedPendingRecurringSection && !pendingRecurringMovements.isEmpty
    }

    private var totalIncome: Decimal {
        summary.totalIncome
    }

    private var totalExpense: Decimal {
        summary.totalExpense
    }

    private var netBalance: Decimal {
        totalIncome - totalExpense
    }

    private var movementCount: Int {
        summary.movementCount
    }

    private var visibleFilteredMovements: [Movement] {
        loadedMovements
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasAnyMovements {
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

                    if hasAnyMovements {
                        Section {
                            MovementSummaryView(
                                totalIncome: totalIncome,
                                totalExpense: totalExpense,
                                netBalance: netBalance,
                                movementCount: movementCount,
                                currencyCode: appCurrencyCode,
                                hideBalances: hideBalances
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }

                    if shouldShowExpandedPendingRecurringSection && !pendingRecurringMovements.isEmpty {
                        Section {
                            ForEach(pendingRecurringMovements) { pending in
                                PendingRecurringMovementRowView(
                                    pending: pending,
                                    currencyCode: appCurrencyCode,
                                    hideBalances: hideBalances
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

                    if shouldShowPendingRecurringHint {
                        Section {
                            PendingRecurringPeriodHintRow(
                                pendingCount: pendingRecurringMovements.count,
                                periodLabel: activePeriodLabel
                            )
                        } header: {
                            Text("Próximos recurrentes")
                        }
                    }

                    if !hasAnyMovements && pendingRecurringMovements.isEmpty {
                        ContentUnavailableView(
                            accounts.isEmpty ? "Sin cuentas" : "Sin movimientos",
                            systemImage: accounts.isEmpty ? "building.columns" : "arrow.left.arrow.right.circle",
                            description: Text(accounts.isEmpty
                                              ? "Crea al menos una cuenta en Cuentas para registrar movimientos"
                                              : "Pulsa + para registrar tu primer gasto, ingreso o transferencia")
                        )
                        .listRowBackground(Color.clear)
                    } else if hasAnyMovements && movementCount == 0 {
                        ContentUnavailableView(
                            "Sin movimientos con estos filtros",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Ajusta cuenta, tipo o búsqueda para ver más resultados")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(visibleFilteredMovements, id: \.id) { movement in
                            MovementRowView(
                                movement: movement,
                                currencyCode: appCurrencyCode,
                                hideBalances: hideBalances
                            )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    movementToView = MovementDetailSelection(id: movement.id, movement: movement)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        movementToEdit = MovementEditingSelection(id: movement.id, movement: movement)
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                        .onDelete(perform: deleteMovements)

                        if visibleFilteredMovements.count < movementCount {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .onAppear {
                                loadNextMovementPage()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Movimientos")
            .searchable(text: $searchText, prompt: "Buscar movimientos")
            .onAppear {
                reloadMovements()
            }
            .onDisappear {
                searchReloadTask?.cancel()
                searchReloadTask = nil
            }
            .onChange(of: selectedDateFilter) { _, _ in
                reloadMovements()
            }
            .onChange(of: selectedTypeFilter) { _, newValue in
                if newValue == .transfer {
                    selectedCategoryFilters.removeAll()
                } else {
                    pruneCategorySelections()
                }

                reloadMovements()
            }
            .onChange(of: selectedAccountFilterID) { _, _ in
                reloadMovements()
            }
            .onChange(of: selectedCategoryFilters) { _, _ in
                reloadMovements()
            }
            .onChange(of: searchText) { _, _ in
                scheduleSearchReload()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        hideBalances.toggle()
                    } label: {
                        Image(systemName: hideBalances ? "eye.slash" : "eye")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddMovement = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .disabled(accounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddMovement, onDismiss: {
                reloadMovements()
            }) {
                AddMovementView()
            }
            .sheet(isPresented: $showingCustomPeriodSheet) {
                MovementCustomMonthSheet(
                    monthOptions: monthOptions,
                    availableYears: availablePeriodYears,
                    selectedMonth: $customMonthDraft,
                    selectedYear: $customYearDraft,
                    onApply: applyCustomPeriod
                )
            }
            .sheet(item: $movementToView, onDismiss: {
                reloadMovements()
            }) { selection in
                MovementDetailView(
                    movement: selection.movement,
                    currencyCode: appCurrencyCode
                )
            }
            .sheet(item: $movementToEdit, onDismiss: {
                reloadMovements()
            }) { selection in
                AddMovementView(movementToEdit: selection.movement)
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
                let movement = visibleFilteredMovements[index]
                if let account = movement.account {
                    switch movement.type {
                    case .expense:
                        account.balance += movement.amount
                    case .income:
                        account.balance -= movement.amount
                    case .transfer:
                        account.balance += movement.amount
                        if account.isInvestmentAccount {
                            account.investedAmount = account.effectiveInvestedAmount + movement.amount
                        }
                        if let destination = movement.destinationAccount {
                            destination.balance -= movement.amount
                            if destination.isInvestmentAccount {
                                destination.investedAmount = max(0, destination.effectiveInvestedAmount - movement.amount)
                            }
                            destination.updatedAt = Date()
                        }
                    }

                    account.updatedAt = Date()
                }
                modelContext.delete(movement)
            }
        }

        reloadMovements()
    }

    private func reloadMovements() {
        searchReloadTask?.cancel()
        searchReloadTask = nil
        reloadMovementSummaryAndRecurringState()
        resetMovementPagination()
        loadNextMovementPage()
    }

    private func scheduleSearchReload() {
        searchReloadTask?.cancel()
        searchReloadTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                reloadMovements()
            }
        }
    }

    private func reloadMovementSummaryAndRecurringState() {
        var computedSummary = MovementListSummary()
        var confirmations: [Movement] = []
        var scannedCount = 0
        var offset = 0
        var discoveredYears: Set<Int> = [calendar.component(.year, from: Date()), selectedYear]

        do {
            while true {
                let batch = try fetchMovementBatch(offset: offset, limit: Self.movementFetchBatchSize)
                guard !batch.isEmpty else { break }

                scannedCount += batch.count
                offset += batch.count

                for movement in batch {
                    discoveredYears.insert(calendar.component(.year, from: movement.occurredAt))

                    if movement.recurringRuleId != nil {
                        confirmations.append(movement)
                    }

                    guard matchesActiveFilters(movement) else { continue }
                    computedSummary.movementCount += 1

                    switch movement.type {
                    case .income:
                        computedSummary.totalIncome += movement.statsIncomeAmount
                    case .expense:
                        computedSummary.totalExpense += movement.statsExpenseAmount
                    case .transfer:
                        break
                    }
                }

                if batch.count < Self.movementFetchBatchSize {
                    break
                }
            }

            summary = computedSummary
            recurringConfirmationMovements = confirmations
            hasAnyMovements = scannedCount > 0
            availablePeriodYears = discoveredYears.sorted(by: >)
        } catch {
            summary = MovementListSummary()
            recurringConfirmationMovements = []
            hasAnyMovements = false
            availablePeriodYears = Array(Set([calendar.component(.year, from: Date()), selectedYear])).sorted(by: >)
        }
    }

    private func resetMovementPagination() {
        loadedMovements = []
        sourceFetchOffset = 0
        hasMoreSourceMovements = true
        isLoadingMovementPage = false
        pendingFilteredMovements = []
    }

    private func loadNextMovementPage() {
        guard !isLoadingMovementPage else { return }
        guard hasMoreSourceMovements || !pendingFilteredMovements.isEmpty else { return }

        isLoadingMovementPage = true
        defer { isLoadingMovementPage = false }

        let targetCount = loadedMovements.count + Self.movementPageSize

        while loadedMovements.count < targetCount {
            if !pendingFilteredMovements.isEmpty {
                let missing = targetCount - loadedMovements.count
                let chunk = Array(pendingFilteredMovements.prefix(missing))
                loadedMovements.append(contentsOf: chunk)
                pendingFilteredMovements.removeFirst(chunk.count)
                continue
            }

            guard hasMoreSourceMovements else { break }

            guard let batch = try? fetchMovementBatch(offset: sourceFetchOffset, limit: Self.movementFetchBatchSize) else {
                hasMoreSourceMovements = false
                break
            }

            sourceFetchOffset += batch.count

            if batch.count < Self.movementFetchBatchSize {
                hasMoreSourceMovements = false
            }

            let matches = batch.filter { movement in
                matchesActiveFilters(movement)
            }

            let missing = targetCount - loadedMovements.count
            let visibleChunk = Array(matches.prefix(missing))
            loadedMovements.append(contentsOf: visibleChunk)

            if matches.count > missing {
                pendingFilteredMovements.append(contentsOf: matches.dropFirst(missing))
            }

            if batch.isEmpty {
                hasMoreSourceMovements = false
            }
        }
    }

    private func fetchMovementBatch(offset: Int, limit: Int) throws -> [Movement] {
        var descriptor = FetchDescriptor<Movement>(
            sortBy: [
                SortDescriptor(\Movement.occurredAt, order: .reverse),
                SortDescriptor(\Movement.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    private func matchesActiveFilters(_ movement: Movement) -> Bool {
        guard matchesDateFilter(movement) else { return false }
        guard matchesAccountAndTypeFilters(movement) else { return false }
        guard matchesCategoryFilters(movement) else { return false }
        guard !trimmedSearchText.isEmpty else { return true }
        return matchesSearch(movement, query: trimmedSearchText)
    }

    private func matchesDateFilter(_ movement: Movement) -> Bool {
        guard let activeDateInterval else { return true }
        return activeDateInterval.contains(movement.occurredAt)
    }

    private func matchesAccountAndTypeFilters(_ movement: Movement) -> Bool {
        if let selectedAccountFilterID {
            let belongsToSelectedAccount = movement.account?.id == selectedAccountFilterID
                || movement.destinationAccount?.id == selectedAccountFilterID
            guard belongsToSelectedAccount else { return false }
        }

        return selectedTypeFilter.matches(movement.type)
    }

    private func matchesCategoryFilters(_ movement: Movement) -> Bool {
        if selectedTypeFilter == .transfer {
            return true
        }

        guard !selectedCategoryFilters.isEmpty else {
            return true
        }

        guard let categoryID = movement.category?.id else {
            return false
        }

        return selectedCategoryFilters.contains(.category(categoryID))
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
            movements: recurringConfirmationMovements
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
        reloadMovements()
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

    private func monthName(for month: Int) -> String {
        monthOptions.first(where: { $0.0 == month })?.1 ?? "Mes"
    }

    private func prepareCustomPeriodDrafts() {
        customMonthDraft = selectedMonth
        customYearDraft = selectedYear

        if !availablePeriodYears.contains(customYearDraft), let fallback = availablePeriodYears.first {
            customYearDraft = fallback
        }
    }

    private func applyCustomPeriod() {
        selectedMonth = customMonthDraft
        selectedYear = customYearDraft

        if selectedDateFilter == .customMonth {
            reloadMovements()
        } else {
            selectedDateFilter = .customMonth
        }
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

    private var filtersHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickDateFilterChips, id: \.id) { filter in
                        MovementFilterChip(
                            title: filter.displayName,
                            color: .indigo,
                            isSelected: selectedDateFilter == filter,
                            action: { selectedDateFilter = filter }
                        )
                    }

                    MovementFilterChip(
                        title: MovementListDateFilter.customMonth.displayName,
                        color: .indigo,
                        isSelected: selectedDateFilter == .customMonth,
                        action: {
                            prepareCustomPeriodDrafts()
                            showingCustomPeriodSheet = true
                        }
                    )
                }
                .padding(.leading, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(activePeriodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if selectedDateFilter == .customMonth {
                    Button("Editar") {
                        prepareCustomPeriodDrafts()
                        showingCustomPeriodSheet = true
                    }
                    .font(.caption)
                }
            }
            .padding(.horizontal, 16)

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

private struct MovementCustomMonthSheet: View {
    @Environment(\.dismiss) private var dismiss

    let monthOptions: [(Int, String)]
    let availableYears: [Int]
    @Binding var selectedMonth: Int
    @Binding var selectedYear: Int
    var onApply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Mes") {
                    Picker("Mes", selection: $selectedMonth) {
                        ForEach(monthOptions, id: \.0) { month, name in
                            Text(name).tag(month)
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

private struct PendingRecurringPeriodHintRow: View {
    let pendingCount: Int
    let periodLabel: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.subheadline)
                .foregroundStyle(.blue)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(pendingCount) recurrentes próximos")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Con el periodo \"\(periodLabel)\" no se muestran en detalle. Cambia a \"Mes actual\" o revisa la pestaña Calendario.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

private struct MovementSummaryView: View {
    let totalIncome: Decimal
    let totalExpense: Decimal
    let netBalance: Decimal
    let movementCount: Int
    let currencyCode: String
    let hideBalances: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SummaryPill(title: "Ingresos", value: totalIncome.masked(hideBalances, code: currencyCode), color: .green)
                SummaryPill(title: "Gastos", value: totalExpense.masked(hideBalances, code: currencyCode), color: .red)
            }

            HStack {
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(netBalance.masked(hideBalances, code: currencyCode))
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
    let hideBalances: Bool

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
            return (pending.rule.amount * pending.rule.type.signMultiplier).masked(hideBalances, code: currencyCode)
        case .transfer:
            return pending.rule.amount.masked(hideBalances, code: currencyCode)
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
                    .lineLimit(2)

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
    let hideBalances: Bool

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
        return "Saldo: \(resultingBalance.masked(hideBalances, code: currencyCode))"
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
                    .lineLimit(2)

                HStack(spacing: 6) {
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

                        if movement.isReimbursementIncome {
                            CategoryChipView(
                                name: "Reembolso",
                                iconName: "arrow.uturn.left.circle",
                                color: .blue
                            )
                        }

                        if movement.isSharedExpense {
                            CategoryChipView(
                                name: "Compartido",
                                iconName: "person.2.fill",
                                color: .orange
                            )
                        }
                    }
                }

                Text(accountAndBankText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let statsDetailText {
                    Text(statsDetailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

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

                if let personalAmountText {
                    Text(personalAmountText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

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
            return movement.signedAmount.masked(hideBalances, code: currencyCode)
        case .transfer:
            return movement.amount.masked(hideBalances, code: currencyCode)
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

    private var personalAmountText: String? {
        guard movement.type == .expense, movement.isSharedExpense else { return nil }
        let signedPersonal = movement.statsExpenseAmount * movement.type.signMultiplier
        return "Mi parte: \(signedPersonal.masked(hideBalances, code: currencyCode))"
    }

    private var statsDetailText: String? {
        if movement.isReimbursementIncome {
            return "No cuenta como ingreso en estadísticas"
        }

        if movement.isSharedExpense {
            let expected = max(movement.amount - movement.statsExpenseAmount, 0)
            return "Reembolso esperado: \(expected.masked(hideBalances, code: currencyCode))"
        }

        return nil
    }
}
