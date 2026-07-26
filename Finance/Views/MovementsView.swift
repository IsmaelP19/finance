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

private struct MovementRowData: Identifiable {
    let movement: Movement
    let recoveredReimbursementAmount: Decimal
    let isLocked: Bool

    var id: UUID { movement.id }
}

private struct MovementEditingSelection: Identifiable {
    let id: UUID
    let movement: Movement
}

private struct MovementDetailSelection: Identifiable {
    let id: UUID
    let movement: Movement
}

private struct MovementArchivedAccountSnapshot {
    let movementID: UUID
    let accountID: UUID?
    let destinationAccountID: UUID?
    let reimbursementForID: UUID?
}

private struct MovementDetailSnapshot: Equatable {
    let id: UUID
    let concept: String
    let amount: Decimal
    let typeRaw: String
    let occurredAt: Date
    let accountID: UUID?
    let destinationAccountID: UUID?
    let categoryID: UUID?
    let personalAmount: Decimal?
    let reimbursementForID: UUID?
    let recurringRuleID: UUID?

    init(movement: Movement) {
        id = movement.id
        concept = movement.concept
        amount = movement.amount
        typeRaw = movement.typeRaw
        occurredAt = movement.occurredAt
        accountID = movement.account?.id
        destinationAccountID = movement.destinationAccount?.id
        categoryID = movement.category?.id
        personalAmount = movement.personalAmount
        reimbursementForID = movement.reimbursementForId
        recurringRuleID = movement.recurringRuleId
    }
}

private struct MovementDetailDismissContext {
    let movementCount: Int
    let latestCreatedAt: Date?
    let loadedMovementCount: Int
    let snapshot: MovementDetailSnapshot
}

private struct MovementSheetBaseline {
    let movementCount: Int
    let latestCreatedAt: Date?
    let loadedMovementCount: Int
}

private enum MovementSyncAction {
    case none
    case reconcileListAndRefreshHeader
    case insertNewMovementsAndRefreshHeader
    case reloadAll
}

private struct MovementListScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Pantalla principal de movimientos (gastos e ingresos).
struct MovementsView: View {
    private static let movementPageSize = 20
    private static let movementFetchBatchSize = 120
    private static let movementSummaryBatchSize = 60

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]
    @Query(filter: #Predicate<Movement> { $0.typeRaw == "income" && $0.reimbursementForId != nil })
    private var reimbursementIncomes: [Movement]

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
    @State private var showingAdvancedFiltersSheet = false
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
    @State private var summaryReloadTask: Task<Void, Never>?
    @State private var isSummaryLoading = false
    @State private var availablePeriodYears: [Int] = [Calendar.current.component(.year, from: Date())]
    @State private var reloadToken = UUID()
    @State private var movementDetailDismissContext: MovementDetailDismissContext?
    @State private var archivedAccountMovementSnapshots: [MovementArchivedAccountSnapshot] = []
    @State private var addMovementBaseline: MovementSheetBaseline?
    @State private var editMovementDismissContext: MovementDetailDismissContext?
    @State private var lastFiltersMinY: CGFloat = 0
    @State private var hasInitializedFiltersMinY = false
    @State private var isFloatingFiltersVisible = false

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

    private var categoryFilterOptions: [(id: MovementCategoryFilter, title: String, iconName: String, color: Color)] {
        categories.map { category in
            (MovementCategoryFilter.category(category.id), category.name, category.iconName, category.color)
        }
    }

    private var accountsSortedByBankThenName: [BankAccount] {
        activeAccounts.sorted { lhs, rhs in
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

    private var activeAccounts: [BankAccount] {
        accounts.filter(\.isActive)
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

    private var shouldShowFiltersHeader: Bool {
        !activeAccounts.isEmpty
    }

    private var recoveredReimbursementAmountsByExpenseID: [UUID: Decimal] {
        reimbursementIncomes.reduce(into: [:]) { partialResult, reimbursement in
            guard let expenseID = reimbursement.reimbursementForId else { return }
            partialResult[expenseID, default: 0] += reimbursement.amount
        }
    }

    private var visibleMovementRows: [MovementRowData] {
        visibleFilteredMovements.map { movement in
            MovementRowData(
                movement: movement,
                recoveredReimbursementAmount: recoveredReimbursementAmountsByExpenseID[movement.id] ?? 0,
                isLocked: movementTouchesArchivedAccount(movement)
            )
        }
    }

    private var archivedAccountIDs: Set<UUID> {
        Set(accounts.filter(\.isArchived).map(\.id))
    }

    var body: some View {
        NavigationStack {
            List {
                if shouldShowFiltersHeader {
                    filtersHeader
                        .padding(.bottom, 2)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: MovementListScrollOffsetKey.self,
                                        value: geometry.frame(in: .named("movementsListScroll")).minY
                                    )
                            }
                        )
                }

                if !activeAccounts.isEmpty {
                    accountFilterControl
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if shouldShowFiltersHeader {
                    summaryHeaderContent
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if shouldShowExpandedPendingRecurringSection && !pendingRecurringMovements.isEmpty {
                    MovementInlineSectionHeader(
                        title: "Próximos recurrentes",
                        count: pendingRecurringMovements.count,
                        systemImage: "repeat",
                        tint: .blue
                    )

                    Section {
                        ForEach(pendingRecurringMovements) { pending in
                            PendingRecurringMovementRowView(
                                pending: pending,
                                currencyCode: appCurrencyCode,
                                hideBalances: hideBalances
                            )
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
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
                    }
                }

                if shouldShowPendingRecurringHint {
                    MovementInlineSectionHeader(
                        title: "Próximos recurrentes",
                        systemImage: "repeat",
                        tint: .blue
                    )

                    Section {
                        PendingRecurringPeriodHintRow(
                            pendingCount: pendingRecurringMovements.count,
                            periodLabel: activePeriodLabel
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                if !hasAnyMovements && pendingRecurringMovements.isEmpty {
                    FinanceEmptyStateContent(
                        activeAccounts.isEmpty ? "Sin cuentas" : "Sin movimientos",
                        systemImage: activeAccounts.isEmpty ? "building.columns" : "arrow.left.arrow.right.circle",
                        description: Text(activeAccounts.isEmpty
                                          ? "Crea al menos una cuenta en Cuentas para registrar movimientos"
                                          : "Pulsa + para registrar tu primer gasto, ingreso o transferencia")
                    )
                    .financeGlassCenteredEmptyListRow(minHeight: 460)
                } else if hasAnyMovements && movementCount == 0 {
                    FinanceEmptyStateContent(
                        "Sin movimientos con estos filtros",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Ajusta cuenta, tipo o búsqueda para ver más resultados")
                    )
                    .financeGlassCenteredEmptyListRow(minHeight: 460)
                } else {
                    if shouldShowExpandedPendingRecurringSection && !pendingRecurringMovements.isEmpty {
                        MovementInlineSectionHeader(
                            title: "Movimientos",
                            systemImage: "arrow.left.arrow.right.circle",
                            tint: .indigo
                        )
                    }

                    Section {
                        ForEach(visibleMovementRows) { row in
                            MovementRowView(
                                movement: row.movement,
                                currencyCode: appCurrencyCode,
                                hideBalances: hideBalances,
                                recoveredReimbursementAmount: row.recoveredReimbursementAmount
                            )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                                 .contentShape(Rectangle())
                                 .onTapGesture {
                                     presentMovementDetail(for: row.movement)
                                 }
                                 .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                     if !row.isLocked {
                                         Button {
                                             presentEditMovement(for: row.movement)
                                         } label: {
                                             Label("Editar", systemImage: "pencil")
                                         }
                                        .tint(.financeAccent)
                                    }
                                }
                        }
                        .onDelete(perform: deleteMovements)

                        if visibleFilteredMovements.count < movementCount {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .onAppear {
                                loadNextMovementPage()
                            }
                        }
                    }
                    .animation(.snappy(duration: 0.28, extraBounce: 0.04), value: visibleFilteredMovements.map(\.id))
                    .animation(.snappy(duration: 0.24, extraBounce: 0), value: recoveredReimbursementAmountsByExpenseID)
                }

            }
            .coordinateSpace(name: "movementsListScroll")
            .onPreferenceChange(MovementListScrollOffsetKey.self) { offset in
                guard hasAnyMovements else {
                    isFloatingFiltersVisible = false
                    hasInitializedFiltersMinY = false
                    lastFiltersMinY = offset
                    return
                }

                guard hasInitializedFiltersMinY else {
                    hasInitializedFiltersMinY = true
                    lastFiltersMinY = offset
                    return
                }

                let delta = offset - lastFiltersMinY
                let isNearTop = offset > -8
                let isFiltersOffscreen = offset < -26
                let threshold: CGFloat = 0.8

                if isNearTop {
                    if isFloatingFiltersVisible {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            isFloatingFiltersVisible = false
                        }
                    }
                } else if delta > threshold && isFiltersOffscreen {
                    if !isFloatingFiltersVisible {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                            isFloatingFiltersVisible = true
                        }
                    }
                } else if delta < -threshold {
                    if isFloatingFiltersVisible {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFloatingFiltersVisible = false
                        }
                    }
                }

                lastFiltersMinY = offset
            }
            .overlay(alignment: .top) {
                if isFloatingFiltersVisible && shouldShowFiltersHeader {
                    floatingFiltersHeader
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .financeGlassPageBackground()
            .navigationTitle("Movimientos")
            .searchable(text: $searchText, prompt: "Buscar movimientos")
            .onAppear {
                clearArchivedAccountFilterIfNeeded()
                refreshArchivedAccountMovementSnapshots()
                reloadMovements(refreshAvailableYears: true)
            }
            .onDisappear {
                searchReloadTask?.cancel()
                searchReloadTask = nil
                summaryReloadTask?.cancel()
                summaryReloadTask = nil
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
                clearArchivedAccountFilterIfNeeded()
                reloadMovements()
            }
            .onChange(of: accounts.map(\.isArchived)) { _, _ in
                clearArchivedAccountFilterIfNeeded()
                refreshArchivedAccountMovementSnapshots()
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
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentAddMovement()
                    } label: {
                        Image(systemName: "plus")
                            .financeToolbarIconStyle()
                    }
                    .disabled(activeAccounts.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddMovement, onDismiss: {
                handleAddMovementDismiss()
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
            .sheet(isPresented: $showingAdvancedFiltersSheet) {
                MovementAdvancedFiltersSheet(
                    selectedTypeFilter: $selectedTypeFilter,
                    selectedCategoryFilters: $selectedCategoryFilters,
                    categoryOptions: categoryFilterOptions,
                    onClearCategories: { selectedCategoryFilters.removeAll() }
                )
            }
            .sheet(item: $movementToView, onDismiss: {
                reloadMovementsIfNeededAfterDetailDismiss()
            }) { selection in
                MovementDetailView(
                    movement: selection.movement,
                    currencyCode: appCurrencyCode
                )
            }
            .sheet(item: $movementToEdit, onDismiss: {
                handleEditMovementDismiss()
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
        CrashReportService.shared.recordBreadcrumb("MovementsView.deleteMovements count=\(offsets.count)")

        var rebuildError: Error?
        withAnimation {
            for index in offsets {
                let movement = visibleFilteredMovements[index]
                guard !movementTouchesArchivedAccount(movement) else {
                    pendingAlertMessage = "No se puede eliminar un movimiento asociado a una cuenta archivada. Sus movimientos se conservan solo como histórico."
                    showingPendingAlert = true
                    continue
                }
                unlinkReimbursementsLinkedToDeletedMovement(movement)
                if let account = movement.account {
                    switch movement.type {
                    case .expense:
                        account.balance += movement.amount
                    case .income:
                        account.balance -= movement.amount
                    case .transfer:
                        let sourceInvestedAmountBeforeImpact = account.effectiveInvestedAmount
                        account.balance += movement.amount
                        if account.isInvestmentAccount {
                            account.investedAmount = sourceInvestedAmountBeforeImpact + movement.amount
                        }
                        if let destination = movement.destinationAccount {
                            let destinationInvestedAmountBeforeImpact = destination.effectiveInvestedAmount
                            destination.balance -= movement.amount
                            if destination.isInvestmentAccount {
                                destination.investedAmount = max(0, destinationInvestedAmountBeforeImpact - movement.amount)
                            }
                            destination.updatedAt = Date()
                        }
                    }

                    account.updatedAt = Date()
                }
                modelContext.delete(movement)
            }
            do {
                _ = try MovementBalanceService.rebuild(in: modelContext)
                try modelContext.save()
            } catch {
                modelContext.rollback()
                rebuildError = error
                CrashReportService.shared.recordDiagnosticEvent(
                    "MovementBalanceService.rebuild failed error=\(error.localizedDescription)"
                )
            }
        }

        if let rebuildError {
            pendingAlertMessage = "No se pudo reconstruir el historial de saldos: \(rebuildError.localizedDescription)"
            showingPendingAlert = true
            return
        }

        reloadMovements(refreshAvailableYears: true)
    }

    private func unlinkReimbursementsLinkedToDeletedMovement(_ deletedMovement: Movement) {
        guard deletedMovement.type == .expense else { return }

        for movement in reimbursementIncomes where movement.reimbursementForId == deletedMovement.id {
            movement.reimbursementForId = nil
            movement.updatedAt = Date()
        }
    }

    private func reloadMovements(refreshAvailableYears: Bool = false) {
        searchReloadTask?.cancel()
        searchReloadTask = nil

        summaryReloadTask?.cancel()
        summaryReloadTask = nil

        let token = UUID()
        reloadToken = token
        isSummaryLoading = true
        summary = MovementListSummary()

        resetMovementPagination()
        loadNextMovementPage()
        startSummaryReload(token: token, refreshAvailableYears: refreshAvailableYears)
    }

    private func refreshSummaryAndRecurringStateSilently(refreshAvailableYears: Bool = false) {
        summaryReloadTask?.cancel()
        summaryReloadTask = nil

        let token = UUID()
        reloadToken = token
        startSummaryReload(token: token, refreshAvailableYears: refreshAvailableYears)
    }

    private func presentAddMovement() {
        addMovementBaseline = currentMovementSheetBaseline()
        showingAddMovement = true
    }

    private func handleAddMovementDismiss() {
        defer { addMovementBaseline = nil }
        guard let baseline = addMovementBaseline else {
            reloadMovements(refreshAvailableYears: true)
            return
        }

        applyMovementSyncAction(syncAction(afterDismissFrom: baseline), baseline: baseline)
    }

    private func presentEditMovement(for movement: Movement) {
        guard !movementTouchesArchivedAccount(movement) else {
            pendingAlertMessage = "No se puede editar un movimiento asociado a una cuenta archivada. Sus movimientos se conservan solo como histórico."
            showingPendingAlert = true
            return
        }

        guard let baseline = currentMovementSheetBaseline() else {
            editMovementDismissContext = nil
            movementToEdit = MovementEditingSelection(id: movement.id, movement: movement)
            return
        }

        editMovementDismissContext = MovementDetailDismissContext(
            movementCount: baseline.movementCount,
            latestCreatedAt: baseline.latestCreatedAt,
            loadedMovementCount: baseline.loadedMovementCount,
            snapshot: MovementDetailSnapshot(movement: movement)
        )
        movementToEdit = MovementEditingSelection(id: movement.id, movement: movement)
    }

    private func handleEditMovementDismiss() {
        defer { editMovementDismissContext = nil }
        guard let context = editMovementDismissContext else {
            reloadMovements(refreshAvailableYears: true)
            return
        }

        applyMovementSyncAction(syncAction(afterDismissFrom: context), baseline: MovementSheetBaseline(
            movementCount: context.movementCount,
            latestCreatedAt: context.latestCreatedAt,
            loadedMovementCount: context.loadedMovementCount
        ))
    }

    private func presentMovementDetail(for movement: Movement) {
        guard let baseline = currentMovementSheetBaseline() else {
            movementDetailDismissContext = nil
            movementToView = MovementDetailSelection(id: movement.id, movement: movement)
            return
        }

        movementDetailDismissContext = MovementDetailDismissContext(
            movementCount: baseline.movementCount,
            latestCreatedAt: baseline.latestCreatedAt,
            loadedMovementCount: baseline.loadedMovementCount,
            snapshot: MovementDetailSnapshot(movement: movement)
        )
        movementToView = MovementDetailSelection(id: movement.id, movement: movement)
    }

    private func reloadMovementsIfNeededAfterDetailDismiss() {
        defer { movementDetailDismissContext = nil }

        guard let context = movementDetailDismissContext else {
            reloadMovements(refreshAvailableYears: true)
            return
        }

        applyMovementSyncAction(syncAction(afterDismissFrom: context), baseline: MovementSheetBaseline(
            movementCount: context.movementCount,
            latestCreatedAt: context.latestCreatedAt,
            loadedMovementCount: context.loadedMovementCount
        ))
    }

    private func currentMovementSheetBaseline() -> MovementSheetBaseline? {
        guard let movementCount = currentMovementCount() else { return nil }
        return MovementSheetBaseline(
            movementCount: movementCount,
            latestCreatedAt: currentLatestMovementCreatedAt(),
            loadedMovementCount: loadedMovements.count
        )
    }

    private func currentMovementCount() -> Int? {
        do {
            return try modelContext.fetchCount(FetchDescriptor<Movement>())
        } catch {
            return nil
        }
    }

    private func currentLatestMovementCreatedAt() -> Date? {
        do {
            var descriptor = FetchDescriptor<Movement>(
                sortBy: [SortDescriptor(\Movement.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first?.createdAt
        } catch {
            return nil
        }
    }

    private func fetchMovement(id: UUID) -> Movement? {
        do {
            var descriptor = FetchDescriptor<Movement>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            return try modelContext.fetch(descriptor).first
        } catch {
            return nil
        }
    }

    private func fetchRecentlyCreatedMovements(limit: Int) -> [Movement] {
        do {
            var descriptor = FetchDescriptor<Movement>(
                sortBy: [
                    SortDescriptor(\Movement.createdAt, order: .reverse),
                    SortDescriptor(\Movement.occurredAt, order: .reverse)
                ]
            )
            descriptor.fetchLimit = limit
            return try modelContext.fetch(descriptor)
        } catch {
            return []
        }
    }

    private func syncAction(afterDismissFrom baseline: MovementSheetBaseline) -> MovementSyncAction {
        guard let currentCount = currentMovementCount() else { return .reloadAll }
        if currentCount < baseline.movementCount { return .reloadAll }
        if currentCount > baseline.movementCount { return .insertNewMovementsAndRefreshHeader }

        let currentLatestCreatedAt = currentLatestMovementCreatedAt()
        if currentLatestCreatedAt != baseline.latestCreatedAt { return .insertNewMovementsAndRefreshHeader }
        return .none
    }

    private func syncAction(afterDismissFrom context: MovementDetailDismissContext) -> MovementSyncAction {
        guard let currentCount = currentMovementCount() else { return .reloadAll }
        if currentCount < context.movementCount { return .reloadAll }
        if currentCount > context.movementCount { return .insertNewMovementsAndRefreshHeader }

        guard let currentMovement = fetchMovement(id: context.snapshot.id) else {
            return .reloadAll
        }

        let currentSnapshot = MovementDetailSnapshot(movement: currentMovement)
        return movementChangeAction(from: context.snapshot, to: currentSnapshot)
    }

    private func movementChangeAction(from previous: MovementDetailSnapshot, to current: MovementDetailSnapshot) -> MovementSyncAction {
        if previous == current { return .none }

        if previous.concept != current.concept {
            return trimmedSearchText.isEmpty ? .none : .reconcileListAndRefreshHeader
        }

        let hasStructuralChange = previous.amount != current.amount
            || previous.typeRaw != current.typeRaw
            || previous.occurredAt != current.occurredAt
            || previous.accountID != current.accountID
            || previous.destinationAccountID != current.destinationAccountID
            || previous.categoryID != current.categoryID
            || previous.personalAmount != current.personalAmount
            || previous.reimbursementForID != current.reimbursementForID
            || previous.recurringRuleID != current.recurringRuleID

        return hasStructuralChange ? .reconcileListAndRefreshHeader : .none
    }

    private func applyMovementSyncAction(_ action: MovementSyncAction, baseline: MovementSheetBaseline) {
        switch action {
        case .none:
            return
        case .reconcileListAndRefreshHeader:
            reconcileLoadedMovements(preferredVisibleCount: baseline.loadedMovementCount)
            refreshSummaryAndRecurringStateSilently(refreshAvailableYears: true)
        case .insertNewMovementsAndRefreshHeader:
            reloadMovements(refreshAvailableYears: true)
        case .reloadAll:
            reloadMovements(refreshAvailableYears: true)
        }
    }

    private func reconcileLoadedMovements(preferredVisibleCount: Int) {
        let targetVisibleCount = targetVisibleMovementCount(from: preferredVisibleCount)
        let existingIDs = Set(loadedMovements.map(\.id))
        pendingFilteredMovements.removeAll { existingIDs.contains($0.id) }

        let reconciledMovements = Array(
            Dictionary(grouping: loadedMovements.filter { matchesActiveFilters($0) }, by: \.id)
                .values
                .compactMap(\.first)
                .sorted(by: movementSortsBefore)
        )

        loadedMovements = Array(reconciledMovements.prefix(targetVisibleCount))

        if reconciledMovements.count > targetVisibleCount {
            let overflow = Array(reconciledMovements.dropFirst(targetVisibleCount))
            let overflowIDs = Set(overflow.map(\.id))
            pendingFilteredMovements = overflow + pendingFilteredMovements.filter { !overflowIDs.contains($0.id) }
        }

        if loadedMovements.count < targetVisibleCount {
            loadNextMovementPage()
        }
    }

    private func insertRecentlyCreatedMovements(since baselineLatestCreatedAt: Date?, preferredVisibleCount: Int) {
        let targetVisibleCount = targetVisibleMovementCount(from: preferredVisibleCount)
        let candidateLimit = max(Self.movementPageSize * 2, targetVisibleCount + 12)
        let recentCandidates = fetchRecentlyCreatedMovements(limit: candidateLimit)
        let existingIDs = Set(loadedMovements.map(\.id))

        let newVisibleMovements = recentCandidates.filter { movement in
            guard !existingIDs.contains(movement.id) else { return false }
            if let baselineLatestCreatedAt {
                guard movement.createdAt > baselineLatestCreatedAt else { return false }
            }
            return matchesActiveFilters(movement)
        }

        guard !newVisibleMovements.isEmpty else { return }

        mergeVisibleMovements(newVisibleMovements, preferredVisibleCount: targetVisibleCount)
    }

    private func mergeVisibleMovements(_ newVisibleMovements: [Movement], preferredVisibleCount: Int) {
        guard !newVisibleMovements.isEmpty else { return }

        loadedMovements.append(contentsOf: newVisibleMovements)
        loadedMovements = Array(
            Dictionary(grouping: loadedMovements, by: \.id)
                .values
                .compactMap(\.first)
                .sorted(by: movementSortsBefore)
        )
        hasAnyMovements = true

        if loadedMovements.count > preferredVisibleCount {
            let overflow = Array(loadedMovements.dropFirst(preferredVisibleCount))
            loadedMovements = Array(loadedMovements.prefix(preferredVisibleCount))

            let loadedIDs = Set(loadedMovements.map(\.id))
            let overflowUnique = overflow.filter { !loadedIDs.contains($0.id) }
            pendingFilteredMovements.removeAll { loadedIDs.contains($0.id) }
            pendingFilteredMovements = overflowUnique + pendingFilteredMovements.filter { !Set(overflowUnique.map(\.id)).contains($0.id) }
        }
    }

    private func targetVisibleMovementCount(from preferredVisibleCount: Int) -> Int {
        preferredVisibleCount == 0 ? Self.movementPageSize : preferredVisibleCount
    }

    private func movementSortsBefore(_ lhs: Movement, _ rhs: Movement) -> Bool {
        if lhs.occurredAt != rhs.occurredAt {
            return lhs.occurredAt > rhs.occurredAt
        }
        return lhs.createdAt > rhs.createdAt
    }

    private func startSummaryReload(token: UUID, refreshAvailableYears: Bool) {
        summaryReloadTask = Task(priority: .utility) { @MainActor in
            await reloadMovementSummaryAndRecurringState(token: token, refreshAvailableYears: refreshAvailableYears)
        }
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

    @MainActor
    private func reloadMovementSummaryAndRecurringState(token: UUID, refreshAvailableYears: Bool) async {
        var computedSummary = MovementListSummary()
        var refreshedAvailableYears: [Int]?

        do {
            if Task.isCancelled || token != reloadToken { return }

            let summaryMovements = try fetchMovementsForSummary()
            let confirmations = try fetchRecurringConfirmationMovements()

            if refreshAvailableYears {
                refreshedAvailableYears = try fetchAvailablePeriodYears()
            }

            for movement in summaryMovements {
                if Task.isCancelled || token != reloadToken { return }

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

            guard !Task.isCancelled, token == reloadToken else { return }
            summary = computedSummary
            recurringConfirmationMovements = confirmations
            hasAnyMovements = (currentMovementCount() ?? summaryMovements.count) > 0
            if let refreshedAvailableYears {
                availablePeriodYears = refreshedAvailableYears
            }
            isSummaryLoading = false
        } catch {
            guard !Task.isCancelled, token == reloadToken else { return }
            summary = MovementListSummary()
            recurringConfirmationMovements = []
            hasAnyMovements = false
            if refreshAvailableYears {
                availablePeriodYears = Array(Set([calendar.component(.year, from: Date()), selectedYear])).sorted(by: >)
            }
            isSummaryLoading = false
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

            if !loadedMovements.isEmpty {
                hasAnyMovements = true
            }

            if matches.count > missing {
                pendingFilteredMovements.append(contentsOf: matches.dropFirst(missing))
            }

            if batch.isEmpty {
                hasMoreSourceMovements = false
            }
        }

        if loadedMovements.isEmpty, !hasMoreSourceMovements {
            hasAnyMovements = false
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

    private func fetchMovementsForSummary() throws -> [Movement] {
        if let interval = activeDateInterval {
            let start = interval.start
            let end = interval.end
            let descriptor = FetchDescriptor<Movement>(
                predicate: #Predicate { movement in
                    movement.occurredAt >= start && movement.occurredAt < end
                }
            )
            return try modelContext.fetch(descriptor)
        }

        let descriptor = FetchDescriptor<Movement>()
        return try modelContext.fetch(descriptor)
    }

    private func fetchRecurringConfirmationMovements() throws -> [Movement] {
        let descriptor = FetchDescriptor<Movement>(
            predicate: #Predicate { movement in
                movement.recurringRuleId != nil
            }
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchAvailablePeriodYears() throws -> [Int] {
        let descriptor = FetchDescriptor<Movement>()
        let movements = try modelContext.fetch(descriptor)
        let discoveredYears = movements.reduce(into: Set([calendar.component(.year, from: Date()), selectedYear])) { years, movement in
            years.insert(calendar.component(.year, from: movement.occurredAt))
        }
        return discoveredYears.sorted(by: >)
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
        return movement.occurredAt >= activeDateInterval.start && movement.occurredAt < activeDateInterval.end
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

        guard account.isActive else {
            pending.rule.isActive = false
            pending.rule.updatedAt = Date()
            pendingAlertMessage = "La cuenta asociada está archivada. La recurrencia se ha desactivado."
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

        let confirmationDate = Date()
        let movement = Movement(
            concept: pending.rule.concept,
            amount: pending.rule.amount,
            type: pending.rule.type,
            occurredAt: confirmationDate,
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
        do {
            _ = try MovementBalanceService.rebuild(in: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            CrashReportService.shared.recordDiagnosticEvent(
                "MovementBalanceService.rebuild failed error=\(error.localizedDescription)"
            )
            pendingAlertMessage = "No se pudo confirmar el movimiento recurrente: \(error.localizedDescription)"
            showingPendingAlert = true
            return
        }
        recurringConfirmationMovements.append(movement)

        HapticFeedback.success()
        mergeVisibleMovements([movement], preferredVisibleCount: targetVisibleMovementCount(from: loadedMovements.count))
        refreshSummaryAndRecurringStateSilently(refreshAvailableYears: true)
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
        let rawAmount = movement.amount.asEditableAmount()
        let signedRawAmount = movement.signedAmount.asEditableAmount()

        let candidates: [String] = [
            movement.concept,
            movement.notes,
            movement.type.displayName,
            movement.category?.name ?? "",
            movement.account?.name ?? "Cuenta eliminada",
            movement.account?.bankDisplayName ?? "",
            movement.destinationAccount?.name ?? "Cuenta eliminada",
            movement.destinationAccount?.bankDisplayName ?? "",
            movement.occurredAt.asSpanishShortDate(),
            movement.occurredAt.asSpanishDateTime(),
            currencyAmount,
            rawAmount,
            signedRawAmount
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

    private var selectedAccountFilterTitle: String {
        guard let selectedAccountFilterID,
              let account = activeAccounts.first(where: { $0.id == selectedAccountFilterID }) else {
            return "Todas"
        }

        return account.name
    }

    private var activeAdvancedFilterLabel: String {
        if selectedTypeFilter != .all {
            return selectedTypeFilter.title
        }

        return "Todos los tipos de movimientos"
    }

    private var advancedFiltersCount: Int {
        (selectedTypeFilter == .all ? 0 : 1) + (selectedTypeFilter == .transfer ? 0 : selectedCategoryFilters.count)
    }

    @ViewBuilder
    private var summaryHeaderContent: some View {
        if isSummaryLoading {
            MovementSummaryLoadingView()
        } else {
            MovementSummaryView(
                totalIncome: totalIncome,
                totalExpense: totalExpense,
                netBalance: netBalance,
                movementCount: movementCount,
                currencyCode: appCurrencyCode,
                hideBalances: hideBalances
            )
        }
    }

    private var accountFilterControl: some View {
        AccountSelectionMenu(
            accounts: activeAccounts,
            selectedAccountID: $selectedAccountFilterID,
            allowsAllAccounts: true,
            accessibilityLabel: "Filtrar por cuenta"
        )
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

    private func movementTouchesArchivedAccount(_ movement: Movement) -> Bool {
        if movement.account?.isArchived == true || movement.destinationAccount?.isArchived == true {
            return true
        }

        guard movement.type == .income, let reimbursementForId = movement.reimbursementForId else { return false }
        return archivedAccountMovementSnapshots.contains { snapshot in
            snapshot.movementID == reimbursementForId
            && snapshot.accountID.map { archivedAccountIDs.contains($0) } == true
        }
    }

    private func refreshArchivedAccountMovementSnapshots() {
        let archivedIDs = archivedAccountIDs
        guard !archivedIDs.isEmpty else {
            archivedAccountMovementSnapshots = []
            return
        }

        var descriptor = FetchDescriptor<Movement>()
        descriptor.includePendingChanges = true

        do {
            let fetchedMovements = try modelContext.fetch(descriptor)
            archivedAccountMovementSnapshots = fetchedMovements.map { movement in
                MovementArchivedAccountSnapshot(
                    movementID: movement.id,
                    accountID: movement.account?.id,
                    destinationAccountID: movement.destinationAccount?.id,
                    reimbursementForID: movement.reimbursementForId
                )
            }
        } catch {
            archivedAccountMovementSnapshots = []
        }
    }

    private func clearArchivedAccountFilterIfNeeded() {
        guard let selectedAccountFilterID else { return }
        if !activeAccounts.contains(where: { $0.id == selectedAccountFilterID }) {
            self.selectedAccountFilterID = nil
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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(activePeriodLabel)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(activeAdvancedFilterLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    showingAdvancedFiltersSheet = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        Text("Filtros")

                        if advancedFiltersCount > 0 {
                            Text("\(advancedFiltersCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.financeAccent, in: Capsule())
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.financeAccent.opacity(0.13), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filtros")
                .accessibilityValue(activeAdvancedFilterLabel)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickDateFilterChips, id: \.id) { filter in
                        MovementQuickDatePill(
                            title: filter.displayName,
                            isSelected: selectedDateFilter == filter,
                            action: { selectedDateFilter = filter }
                        )
                    }

                    MovementQuickDatePill(
                        title: selectedDateFilter == .customMonth ? activePeriodLabel : MovementListDateFilter.customMonth.displayName,
                        systemImage: "calendar.badge.clock",
                        isSelected: selectedDateFilter == .customMonth,
                        action: {
                            prepareCustomPeriodDrafts()
                            showingCustomPeriodSheet = true
                        }
                    )
                }
            }
            .scrollClipDisabled()
        }
        .padding(14)
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.hero)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var floatingFiltersHeader: some View {
        filtersHeader
            .background(
                Rectangle()
                    .fill(.regularMaterial)
                    .overlay(alignment: .bottom) {
                        Divider()
                            .opacity(0.35)
                    }
            )
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
                .financeGlassPill(tint: color, isSelected: isSelected)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MovementQuickDatePill: View {
    let title: String
    var systemImage: String = "calendar"
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
                    .symbolRenderingMode(.hierarchical)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? LinearGradient(colors: [Color.financeAccent.opacity(0.82), Color.financeAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.white.opacity(0.38) : Color.white.opacity(0.26), lineWidth: 0.75)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MovementInlineSectionHeader: View {
    let title: String
    var count: Int? = nil
    var systemImage: String? = nil
    var tint: Color = .blue

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(.primary.opacity(0.82))
            }

            Spacer(minLength: 12)

            if let count {
                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
        .padding(.top, 10)
        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .combine)
    }
}

private struct MovementAdvancedFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedTypeFilter: MovementListTypeFilter
    @Binding var selectedCategoryFilters: Set<MovementCategoryFilter>
    let categoryOptions: [(id: MovementCategoryFilter, title: String, iconName: String, color: Color)]
    var onClearCategories: () -> Void

    var body: some View {
        NavigationStack {
            List {
                MovementInlineSectionHeader(
                    title: "Tipo de movimiento",
                    systemImage: "line.3.horizontal.decrease.circle",
                    tint: .blue
                )

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(MovementListTypeFilter.allCases) { filter in
                            MovementAdvancedFilterTile(
                                title: filter.title,
                                systemImage: iconName(for: filter),
                                color: filter.color,
                                isSelected: selectedTypeFilter == filter
                            ) {
                                selectedTypeFilter = filter
                                if filter == .transfer {
                                    onClearCategories()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Las transferencias ocultan categorías porque no tienen categoría asociada.")
                }

                if selectedTypeFilter != .transfer {
                    MovementInlineSectionHeader(
                        title: "Categorías",
                        systemImage: "tag",
                        tint: .purple
                    )

                    Section {
                        Button {
                            onClearCategories()
                        } label: {
                            HStack {
                                Label("Todas las categorías", systemImage: "sparkles")
                                Spacer()
                                if selectedCategoryFilters.isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        ForEach(categoryOptions, id: \.id) { option in
                            Button {
                                if selectedCategoryFilters.contains(option.id) {
                                    selectedCategoryFilters.remove(option.id)
                                } else {
                                    selectedCategoryFilters.insert(option.id)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: option.iconName)
                                        .font(.subheadline.weight(.semibold))
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(option.color)
                                        .frame(width: 30, height: 30)
                                        .background(option.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    Text(option.title)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if selectedCategoryFilters.contains(option.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(option.color)
                                    }
                                }
                            }
                            .accessibilityAddTraits(selectedCategoryFilters.contains(option.id) ? .isSelected : [])
                        }
                    }
                }
            }
            .financeGlassListContainer()
            .navigationTitle("Ajustar filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Restablecer") {
                        selectedTypeFilter = .all
                        onClearCategories()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func iconName(for filter: MovementListTypeFilter) -> String {
        switch filter {
        case .all: return "circle.grid.2x2.fill"
        case .expense: return "arrow.down.left.circle.fill"
        case .income: return "arrow.up.right.circle.fill"
        case .transfer: return "arrow.left.arrow.right.circle.fill"
        }
    }
}

private struct MovementAdvancedFilterTile: View {
    let title: String
    let systemImage: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(color)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color)
                }
            }
            .financeInsetCard(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? color.opacity(0.55) : Color.clear, lineWidth: 1.2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                MovementInlineSectionHeader(
                    title: "Mes",
                    systemImage: "calendar",
                    tint: .blue
                )

                Section {
                    Picker("Mes", selection: $selectedMonth) {
                        ForEach(monthOptions, id: \.0) { month, name in
                            Text(name).tag(month)
                        }
                    }
                }

                MovementInlineSectionHeader(
                    title: "Año",
                    systemImage: "calendar.circle",
                    tint: .indigo
                )

                Section {
                    Picker("Año", selection: $selectedYear) {
                        ForEach(availableYears, id: \.self) { year in
                            Text(verbatim: String(year)).tag(year)
                        }
                    }
                }
            }
            .financeGlassListContainer()
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
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.vertical, 2)
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryPill(title: "Ingresos", value: totalIncome.masked(hideBalances, code: currencyCode), color: .green)
                Divider().opacity(0.35)
                SummaryPill(title: "Gastos", value: totalExpense.masked(hideBalances, code: currencyCode), color: .red)
            }

            Divider().opacity(0.25)

            HStack(spacing: 12) {
                SummaryPill(title: "Balance", value: netBalance.masked(hideBalances, code: currencyCode), color: netBalance >= 0 ? .green : .red)
                Divider().opacity(0.35)
                SummaryPill(title: "Movimientos", value: "\(movementCount)", color: .financeAccent)
            }
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }
}

private struct MovementSummaryLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: 58)
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: 58)
            }

            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 34)

            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 34)
        }
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
        .redacted(reason: .placeholder)
    }
}

private struct SummaryPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let color: Color

    private var titleColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : .black.opacity(0.88)
    }

    private var valueColor: Color {
        colorScheme == .dark ? .white : .black.opacity(0.96)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(color.opacity(colorScheme == .dark ? 0.35 : 0.22))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(titleColor)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PendingRecurringMovementRowView: View {
    let pending: PendingRecurringMovement
    let currencyCode: String
    let hideBalances: Bool

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

    private var statusTitle: String {
        switch pending.status {
        case .overdue:
            return "Vencido"
        case .dueToday:
            return "Hoy"
        case .upcoming:
            return "Pendiente"
        }
    }

    var body: some View {
        let badges: [MovementRowBadge] = {
            guard let categoryName = pending.rule.category?.name,
                  let categoryIconName = pending.rule.category?.iconName,
                  let categoryColor = pending.rule.category?.color else {
                return []
            }

            return [
                MovementRowBadge(
                    id: "category",
                    name: categoryName,
                    iconName: categoryIconName,
                    color: categoryColor
                )
            ]
        }()

        RecurringMovementRowContent(
            type: pending.rule.type,
            concept: pending.rule.concept,
            badges: badges,
            detailLines: [accountName],
            amountText: amountText,
            trailingPill: MovementTrailingPill(title: statusTitle, color: statusColor),
            dateText: pending.dueDate.asSpanishShortDate(),
            style: .movementListCard
        )
    }
}

private struct MovementRowView: View, Equatable {
    let movement: Movement
    let currencyCode: String
    let hideBalances: Bool
    let recoveredReimbursementAmount: Decimal

    static func == (lhs: MovementRowView, rhs: MovementRowView) -> Bool {
        lhs.movement.id == rhs.movement.id
            && lhs.currencyCode == rhs.currencyCode
            && lhs.hideBalances == rhs.hideBalances
            && lhs.recoveredReimbursementAmount == rhs.recoveredReimbursementAmount
            && lhs.movement.amount == rhs.movement.amount
            && lhs.movement.personalAmount == rhs.movement.personalAmount
            && lhs.movement.resultingBalance == rhs.movement.resultingBalance
            && lhs.movement.occurredAt == rhs.movement.occurredAt
    }

    private var accountAndBankText: String {
        let accountText = movement.account?.name ?? "Cuenta eliminada"
        if movement.type == .transfer {
            let destinationText = movement.destinationAccount?.name ?? "Cuenta eliminada"
            return "\(accountText) -> \(destinationText)"
        }
        return accountText
    }

    private var balanceAfterText: String? {
        guard let resultingBalance = movement.resultingBalance else { return nil }
        return "Saldo: \(resultingBalance.masked(hideBalances, code: currencyCode))"
    }

    private var reimbursementExpectedText: String? {
        guard movement.type == .expense, movement.isSharedExpense else { return nil }
        let pending = movement.pendingReimbursementAmount(recoveredAmount: recoveredReimbursementAmount)
        guard pending > 0 else { return nil }
        return "Pendiente: \(pending.masked(hideBalances, code: currencyCode))"
    }

    private var detailLines: [String] {
        var lines: [String] = [accountAndBankText]

        if let reimbursementExpectedText {
            lines.append(reimbursementExpectedText)
        }

        if let balanceAfterText {
            lines.append(balanceAfterText)
        }

        return lines
    }

    private var badgeItems: [MovementRowBadge] {
        if movement.type == .transfer {
            return [
                MovementRowBadge(
                    id: "transfer",
                    name: "Transferencia",
                    iconName: "arrow.left.arrow.right",
                    color: .blue
                )
            ]
        }

        var items: [MovementRowBadge] = [
            MovementRowBadge(
                id: "category",
                name: movement.category?.name ?? "Sin categoría",
                iconName: movement.category?.iconName ?? "tag",
                color: movement.category?.color ?? .secondary
            )
        ]

        if movement.isReimbursementIncome {
            items.append(
                MovementRowBadge(
                    id: "reimbursement",
                    name: "Reembolso",
                    iconName: "arrow.uturn.left.circle",
                    color: .blue
                )
            )
        }

        if movement.isSharedExpense {
            items.append(
                MovementRowBadge(
                    id: "shared",
                    name: "Compartido",
                    iconName: "person.2.fill",
                    color: .orange
                )
            )
        }

        return items
    }

    var body: some View {
        RecurringMovementRowContent(
            type: movement.type,
            concept: movement.concept,
            badges: badgeItems,
            detailLines: detailLines,
            amountText: displayAmount,
            amountColor: displayAmountColor,
            trailingInfoText: personalAmountText,
            dateText: movement.occurredAt.asSpanishShortDate(),
            style: .movementListCard
        )
        .contentTransition(.opacity)
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
}
