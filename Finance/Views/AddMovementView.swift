//
//  AddMovementView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData

private struct AccountBankGroup: Identifiable {
    let id: String
    let bankName: String
    let accounts: [BankAccount]
}

/// Formulario para crear movimientos (gasto o ingreso).
struct AddMovementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]

    @State private var selectedAccount: BankAccount?
    @State private var selectedDestinationAccount: BankAccount?
    @State private var movementType: MovementType = .expense
    @State private var amountText: String = ""
    @State private var concept: String = ""
    @State private var selectedCategory: MovementCategory?
    @State private var categorySearchText: String = ""
    @State private var isCreatingNewCategory = false
    @State private var newCategoryName: String = ""
    @State private var occurredAt: Date = Date()
    @State private var notes: String = ""
    @State private var isRecurring = false
    @State private var recurringFrequency: RecurringMovementFrequency = .monthly
    @State private var recurringStartDate: Date = Date()
    @State private var recurringHasEndDate = false
    @State private var recurringEndDate: Date = Date()
    @State private var isSharedExpense = false
    @State private var personalAmountText: String = ""
    @State private var isReimbursementIncome = false
    @State private var selectedReimbursementExpense: Movement?
    @State private var showingQuickReimbursementSheet = false

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var didLoadExistingData = false

    private let movementToEdit: Movement?
    private let preselectedType: MovementType?
    private let preselectedAccountID: UUID?
    private let prefilledConcept: String?
    private let linkedReimbursementExpenseID: UUID?

    private var isEditing: Bool {
        movementToEdit != nil
    }

    private var editorNavigationTitle: String {
        if isEditing {
            return "Editar movimiento"
        }
        if linkedReimbursementExpenseID != nil {
            return "Registrar reembolso"
        }
        return "Nuevo movimiento"
    }

    private var movementTint: Color {
        switch movementType {
        case .expense: return .red
        case .income: return .green
        case .transfer: return .blue
        }
    }

    init(
        movementToEdit: Movement? = nil,
        preselectedType: MovementType? = nil,
        preselectedAccountID: UUID? = nil,
        prefilledConcept: String? = nil,
        linkedReimbursementExpenseID: UUID? = nil
    ) {
        self.movementToEdit = movementToEdit
        self.preselectedType = preselectedType
        self.preselectedAccountID = preselectedAccountID
        self.prefilledConcept = prefilledConcept
        self.linkedReimbursementExpenseID = linkedReimbursementExpenseID
    }

    private var filteredCategories: [MovementCategory] {
        if categorySearchText.isEmpty {
            return categories
        }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(categorySearchText) }
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

    private var groupedAccountsByBank: [AccountBankGroup] {
        let grouped = Dictionary(grouping: accountsSortedByBankThenName) { account in
            account.bank?.id.uuidString ?? "no-bank"
        }

        return grouped
            .compactMap { key, groupedAccounts in
                guard let first = groupedAccounts.first else { return nil }
                return AccountBankGroup(id: key, bankName: first.bankDisplayName, accounts: groupedAccounts)
            }
            .sorted { lhs, rhs in
                lhs.bankName.localizedCaseInsensitiveCompare(rhs.bankName) == .orderedAscending
            }
    }

    private var selectedAccountIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedAccount?.id },
            set: { newID in
                selectedAccount = newID.flatMap { id in
                    activeAccounts.first { $0.id == id }
                }
            }
        )
    }

    private var selectedDestinationAccountIDBinding: Binding<UUID?> {
        Binding(
            get: { selectedDestinationAccount?.id },
            set: { newID in
                selectedDestinationAccount = newID.flatMap { id in
                    activeAccounts.first { $0.id == id }
                }
            }
        )
    }

    private var canCreateNewCategory: Bool {
        let trimmed = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !categories.contains { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    private var canConfigureOwnershipFields: Bool {
        !isRecurring || isEditing
    }

    private var allowsReimbursementLinkingInThisContext: Bool {
        linkedReimbursementExpenseID != nil || movementToEdit?.reimbursementForId != nil
    }

    private var isLinkedReimbursementContext: Bool {
        linkedReimbursementExpenseID != nil || movementToEdit?.reimbursementForId != nil
    }

    private var allowsRecurringConfiguration: Bool {
        movementType != .transfer && !isLinkedReimbursementContext
    }

    private var isMovementTypeLocked: Bool {
        isLinkedReimbursementContext
    }

    private var linkedReimbursementsForEditedExpense: [Movement] {
        guard let movementToEdit, movementToEdit.type == .expense else { return [] }
        return movements
            .filter { $0.type == .income && $0.reimbursementForId == movementToEdit.id }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var expectedReimbursementForDraftExpense: Decimal {
        guard movementType == .expense, isSharedExpense else { return 0 }
        let total = parseAmount(from: amountText)
        let personal = parseAmount(from: personalAmountText)
        guard total > 0 else { return 0 }
        return max(total - personal, 0)
    }

    private var recoveredAmountForEditedExpense: Decimal {
        linkedReimbursementsForEditedExpense.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var pendingReimbursementForEditedExpense: Decimal {
        max(expectedReimbursementForDraftExpense - recoveredAmountForEditedExpense, 0)
    }

    private var reimbursementOverageForEditedExpense: Decimal {
        max(recoveredAmountForEditedExpense - expectedReimbursementForDraftExpense, 0)
    }

    private var draftSharedExpenseTotal: Decimal {
        parseAmount(from: amountText)
    }

    private var draftSharedExpensePersonalAmount: Decimal {
        parseAmount(from: personalAmountText)
    }

    private var isReimbursementFullyRecovered: Bool {
        guard expectedReimbursementForDraftExpense > 0 else { return false }
        return recoveredAmountForEditedExpense >= expectedReimbursementForDraftExpense
    }

    private var willUnlinkReimbursementsOnSave: Bool {
        guard isEditing, movementType == .expense else { return false }
        guard !linkedReimbursementsForEditedExpense.isEmpty else { return false }
        return normalizedPersonalAmountForExpense(
            totalAmount: draftSharedExpenseTotal,
            rawPersonalAmount: isSharedExpense ? draftSharedExpensePersonalAmount : nil
        ) == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MovementDraftHero(
                        title: $concept,
                        amountText: $amountText,
                        type: $movementType,
                        isMovementTypeLocked: isMovementTypeLocked,
                        selectedAccount: $selectedAccount,
                        selectedDestinationAccount: $selectedDestinationAccount,
                        selectedCategory: $selectedCategory,
                        accountGroups: groupedAccountsByBank,
                        categories: categories,
                        currencyCode: appCurrencyCode,
                        tint: movementTint,
                        onCreateCategory: {
                            newCategoryName = ""
                            categorySearchText = ""
                            isCreatingNewCategory = true
                        }
                    )
                }
                .financeGlassClearListRow()

                if movementType == .expense && canConfigureOwnershipFields {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Definir mi gasto", isOn: $isSharedExpense)
                                .tint(movementTint)

                            if isSharedExpense {
                                MovementEditorInlineAmountRow(
                                    label: "Mi parte",
                                    text: $personalAmountText,
                                    currencyCode: appCurrencyCode,
                                    tint: movementTint
                                )

                                if draftSharedExpenseTotal > 0 {
                                    Text("Total: \(draftSharedExpenseTotal.asCurrency(code: appCurrencyCode)) · Mi parte: \(draftSharedExpensePersonalAmount.asCurrency(code: appCurrencyCode))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if willUnlinkReimbursementsOnSave {
                                    Text("Al guardar, \(linkedReimbursementsForEditedExpense.count) \(linkedReimbursementsForEditedExpense.count == 1 ? "reembolso" : "reembolsos") dejarán de estar vinculados y pasarán a ingresos normales.")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }

                                if isEditing {
                                    if expectedReimbursementForDraftExpense > 0 {
                                        Divider()

                                        ProgressView(
                                            value: min((recoveredAmountForEditedExpense as NSDecimalNumber).doubleValue, (expectedReimbursementForDraftExpense as NSDecimalNumber).doubleValue),
                                            total: max((expectedReimbursementForDraftExpense as NSDecimalNumber).doubleValue, 0.0001)
                                        )
                                        .tint(isReimbursementFullyRecovered ? .green : .blue)

                                        Text("Recuperado: \(recoveredAmountForEditedExpense.asCurrency(code: appCurrencyCode)) de \(expectedReimbursementForDraftExpense.asCurrency(code: appCurrencyCode))")
                                            .font(.caption)
                                            .foregroundStyle(isReimbursementFullyRecovered ? .green : .secondary)

                                        Text("Pendiente: \(pendingReimbursementForEditedExpense.asCurrency(code: appCurrencyCode))")
                                            .font(.caption)
                                            .foregroundStyle(isReimbursementFullyRecovered ? .green : .secondary)

                                        if reimbursementOverageForEditedExpense > 0 {
                                            Text("Extra recibido: \(reimbursementOverageForEditedExpense.asCurrency(code: appCurrencyCode))")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                        }

                                        Button {
                                            showingQuickReimbursementSheet = true
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "plus.circle.fill")
                                                Text("Registrar reembolso")
                                                    .fontWeight(.semibold)
                                            }
                                            .font(.subheadline)
                                            .foregroundStyle(Color.financeAccent)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Registrar reembolso")
                                    }

                                    if !linkedReimbursementsForEditedExpense.isEmpty {
                                        ForEach(linkedReimbursementsForEditedExpense.prefix(5), id: \.id) { reimbursement in
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(reimbursement.concept)
                                                        .font(.subheadline)
                                                        .lineLimit(1)
                                                    Text(reimbursement.occurredAt.asSpanishShortDate())
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }

                                                Spacer()

                                                Text(reimbursement.amount.asCurrency(code: appCurrencyCode))
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                    }
                                }
                            }

                            if !isSharedExpense, isEditing, !linkedReimbursementsForEditedExpense.isEmpty {
                                Text("Al guardar, \(linkedReimbursementsForEditedExpense.count) \(linkedReimbursementsForEditedExpense.count == 1 ? "reembolso" : "reembolsos") dejarán de estar vinculados y pasarán a ingresos normales.")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        MovementEditorSectionHeader(title: "Gasto compartido", systemImage: "person.2.fill", subtitle: "Controla tu parte y reembolsos", tint: .financeAccent)
                    }
                    .movementEditorDetailSection()
                }

                if movementType == .income && canConfigureOwnershipFields && isReimbursementIncome {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            if let selectedReimbursementExpense {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Gasto vinculado")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    HStack(alignment: .center) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(selectedReimbursementExpense.concept)
                                                .font(.subheadline.weight(.medium))
                                            Text(selectedReimbursementExpense.occurredAt.asSpanishShortDate())
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer(minLength: 12)

                                        Text(selectedReimbursementExpense.amount.asCurrency(code: appCurrencyCode))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.red)
                                    }
                                }

                                Text("Este vínculo se define desde el gasto con \"Registrar reembolso\".")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Este reembolso está vinculado a un gasto que ya no se encuentra.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        MovementEditorSectionHeader(title: "Reembolso", systemImage: "arrow.down.circle.fill", subtitle: "Ingreso vinculado a un gasto", tint: .financeAccent)
                    }
                    .movementEditorDetailSection()
                }

                if !isRecurring || isEditing {
                    Section {
                        DatePicker("Fecha del movimiento", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                    } header: {
                        MovementEditorSectionHeader(title: "Fecha", systemImage: "calendar", subtitle: "Cuándo ocurrió", tint: .financeAccent)
                    }
                    .movementEditorDetailSection()
                }

                if allowsRecurringConfiguration {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Marcar como recurrente", isOn: $isRecurring)
                                .tint(movementTint)

                            if isRecurring {
                                Picker("Frecuencia", selection: $recurringFrequency) {
                                    ForEach(RecurringMovementFrequency.allCases) { frequency in
                                        Text(frequency.displayName)
                                            .tag(frequency)
                                    }
                                }

                                DatePicker(
                                    "Primer cobro/pago",
                                    selection: $recurringStartDate,
                                    displayedComponents: .date
                                )

                                Toggle("Fecha de fin", isOn: $recurringHasEndDate)

                                if recurringHasEndDate {
                                    DatePicker(
                                        "Fin",
                                        selection: $recurringEndDate,
                                        in: recurringStartDate...,
                                        displayedComponents: .date
                                    )
                                }

                                Text("Se guardará como pendiente recurrente. No afectará al saldo hasta confirmar el cobro/pago.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        MovementEditorSectionHeader(title: "Recurrencia", systemImage: "repeat", subtitle: "Convierte pagos periódicos en pendientes", tint: .financeAccent)
                    }
                    .movementEditorDetailSection()
                }

                Section {
                    TextField("Añade una nota...", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    MovementEditorSectionHeader(title: "Notas", systemImage: "note.text", subtitle: "Opcional", tint: .financeAccent)
                }
                .movementEditorDetailSection()
            }
            .financeGlassListContainer()
            .navigationTitle(editorNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button("Cancelar") { dismiss() }
                        .financeGlassSecondaryAction(tint: .secondary)

                    Button {
                        saveMovement()
                    } label: {
                        Label(isEditing ? "Actualizar" : "Guardar", systemImage: "checkmark")
                    }
                    .financeGlassPrimaryAction(tint: movementTint)
                    .disabled(activeAccounts.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Cerrar")
                }
            }
            .onAppear(perform: setupDefaults)
            .onChange(of: movementType) { _, newValue in
                if newValue == .transfer {
                    selectedCategory = nil
                    categorySearchText = ""
                    isRecurring = false
                    isSharedExpense = false
                    personalAmountText = ""
                    if !allowsReimbursementLinkingInThisContext {
                        isReimbursementIncome = false
                        selectedReimbursementExpense = nil
                    }
                    ensureTransferAccountsAreDifferent()
                } else {
                    if selectedCategory == nil {
                        selectedCategory = categories.first
                    }

                    if newValue != .expense {
                        isSharedExpense = false
                        personalAmountText = ""
                    }

                    if newValue != .income {
                        if !allowsReimbursementLinkingInThisContext {
                            isReimbursementIncome = false
                            selectedReimbursementExpense = nil
                        }
                    } else if allowsReimbursementLinkingInThisContext,
                              selectedReimbursementExpense != nil {
                        isReimbursementIncome = true
                    }
                }
            }
            .onChange(of: isSharedExpense) { _, enabled in
                if !enabled {
                    personalAmountText = ""
                } else if personalAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    personalAmountText = amountText
                }
            }
            .onChange(of: selectedAccount?.id) { _, _ in
                if movementType == .transfer {
                    ensureTransferAccountsAreDifferent()
                }
            }
            .onChange(of: selectedDestinationAccount?.id) { _, _ in
                if movementType == .transfer {
                    ensureTransferAccountsAreDifferent()
                }
            }
            .sheet(isPresented: $isCreatingNewCategory) {
                CreateMovementCategorySheet(categoryName: $newCategoryName) { category in
                    selectedCategory = category
                    categorySearchText = ""
                }
            }
            .sheet(isPresented: $showingQuickReimbursementSheet) {
                if let movementToEdit {
                    AddMovementView(
                        preselectedType: .income,
                        preselectedAccountID: activeReimbursementAccount(for: movementToEdit)?.id,
                        prefilledConcept: "Reembolso: \(movementToEdit.concept)",
                        linkedReimbursementExpenseID: movementToEdit.id
                    )
                }
            }
            .alert("Campos requeridos", isPresented: $showingValidationAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func setupDefaults() {
        if !didLoadExistingData, let movementToEdit {
            selectedAccount = movementToEdit.account
            selectedDestinationAccount = movementToEdit.destinationAccount
            movementType = movementToEdit.type
            amountText = formatAmountForEditing(movementToEdit.amount)
            concept = movementToEdit.concept
            selectedCategory = movementToEdit.category
            occurredAt = movementToEdit.occurredAt
            notes = movementToEdit.notes

            if movementToEdit.type == .expense,
               let personalAmount = movementToEdit.personalAmount,
               personalAmount >= 0,
               personalAmount <= movementToEdit.amount {
                isSharedExpense = personalAmount < movementToEdit.amount
                if isSharedExpense {
                    personalAmountText = formatAmountForEditing(personalAmount)
                }
            } else {
                isSharedExpense = false
                personalAmountText = ""
            }

            if movementToEdit.type == .income,
               let reimbursementForId = movementToEdit.reimbursementForId {
                isReimbursementIncome = true
                selectedReimbursementExpense = movements.first(where: { $0.id == reimbursementForId && $0.type == .expense })
            } else {
                isReimbursementIncome = false
                selectedReimbursementExpense = nil
            }

            if let recurring = linkedRecurringRule(for: movementToEdit) {
                isRecurring = recurring.isActive
                recurringFrequency = recurring.frequency
                recurringStartDate = Calendar.current.startOfDay(for: recurring.startDate)
                if let endDate = recurring.endDate {
                    recurringHasEndDate = true
                    recurringEndDate = Calendar.current.startOfDay(for: endDate)
                } else {
                    recurringHasEndDate = false
                    recurringEndDate = recurringStartDate
                }
            } else {
                isRecurring = false
                recurringFrequency = .monthly
                recurringStartDate = Calendar.current.startOfDay(for: movementToEdit.occurredAt)
                recurringHasEndDate = false
                recurringEndDate = recurringStartDate
            }

            if isLinkedReimbursementContext {
                movementType = .income
                isRecurring = false
            }

            didLoadExistingData = true
            return
        }

        if let preselectedType {
            movementType = preselectedType
        }

        if concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let prefilledConcept,
           !prefilledConcept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            concept = prefilledConcept
        }

        if let preselectedAccountID,
            let matchingAccount = accountsSortedByBankThenName.first(where: { $0.id == preselectedAccountID }) {
            selectedAccount = matchingAccount
        }

        if let linkedReimbursementExpenseID,
           let linkedExpense = movements.first(where: { $0.id == linkedReimbursementExpenseID && $0.type == .expense }) {
            selectedReimbursementExpense = linkedExpense
            isReimbursementIncome = true
            selectedCategory = linkedExpense.category

            if selectedAccount == nil {
                selectedAccount = activeReimbursementAccount(for: linkedExpense)
            }

            if concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                concept = "Reembolso: \(linkedExpense.concept)"
            }

            movementType = .income
            isRecurring = false
        }

        if selectedAccount == nil {
            selectedAccount = accountsSortedByBankThenName.first
        }
        if selectedDestinationAccount == nil {
            selectedDestinationAccount = accountsSortedByBankThenName.dropFirst().first ?? accountsSortedByBankThenName.first
        }
        if selectedCategory == nil {
            selectedCategory = categories.first
        }

        recurringFrequency = .monthly
        recurringStartDate = Calendar.current.startOfDay(for: occurredAt)
        recurringEndDate = recurringStartDate

        ensureTransferAccountsAreDifferent()
    }

    private func parseAmount(from text: String) -> Decimal {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned) ?? 0
    }

    private func parseAmount() -> Decimal {
        parseAmount(from: amountText)
    }

    private func formatAmountForEditing(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    private func normalizedPersonalAmountForExpense(totalAmount: Decimal, rawPersonalAmount: Decimal?) -> Decimal? {
        guard let rawPersonalAmount else { return nil }
        guard rawPersonalAmount < totalAmount else { return nil }
        return max(rawPersonalAmount, 0)
    }

    private func saveMovement() {
        if isLinkedReimbursementContext {
            movementType = .income
        }

        CrashReportService.shared.recordBreadcrumb("Guardando movimiento de tipo \(movementType.displayName)")
        recordSaveDiagnostic("start")

        recordSaveDiagnostic("resolve_account_before")
        guard let selectedAccount else {
            recordSaveDiagnostic("resolve_account_failed")
            validationMessage = "Selecciona una cuenta."
            showingValidationAlert = true
            return
        }
        recordSaveDiagnostic("resolve_account_after", accountID: selectedAccount.id)

        if let movementToEdit, movementTouchesArchivedAccount(movementToEdit) {
            validationMessage = "No se puede editar un movimiento asociado a una cuenta archivada. Sus movimientos se conservan solo como histórico."
            showingValidationAlert = true
            return
        }

        guard selectedAccount.isActive else {
            validationMessage = "Selecciona una cuenta activa. Las cuentas archivadas solo se conservan como histórico."
            showingValidationAlert = true
            return
        }

        let trimmedConcept = concept.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedConcept.isEmpty else {
            recordSaveDiagnostic("validate_concept_failed", accountID: selectedAccount.id)
            validationMessage = "El concepto es obligatorio."
            showingValidationAlert = true
            return
        }

        if movementType != .transfer {
            recordSaveDiagnostic("resolve_category_before", accountID: selectedAccount.id)
            guard selectedCategory != nil else {
                recordSaveDiagnostic("resolve_category_failed", accountID: selectedAccount.id)
                validationMessage = "Selecciona o crea una categoría."
                showingValidationAlert = true
                return
            }
            recordSaveDiagnostic("resolve_category_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
        }

        recordSaveDiagnostic("parse_amount_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
        let amount = parseAmount()
        guard amount > 0 else {
            recordSaveDiagnostic("parse_amount_failed", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
            validationMessage = "El importe debe ser mayor que cero."
            showingValidationAlert = true
            return
        }
        recordSaveDiagnostic("parse_amount_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id)

        let personalAmountForStats: Decimal?
        if movementType == .expense && isSharedExpense && canConfigureOwnershipFields {
            let personalAmount = parseAmount(from: personalAmountText)

            guard personalAmount >= 0 else {
                recordSaveDiagnostic("parse_personal_amount_negative", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
                validationMessage = "Tu parte no puede ser negativa."
                showingValidationAlert = true
                return
            }

            guard personalAmount <= amount else {
                recordSaveDiagnostic("parse_personal_amount_exceeds_total", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
                validationMessage = "Tu parte no puede superar el importe total del gasto."
                showingValidationAlert = true
                return
            }

            personalAmountForStats = personalAmount
        } else {
            personalAmountForStats = nil
        }

        let normalizedPersonalAmountForStats = movementType == .expense
            ? normalizedPersonalAmountForExpense(totalAmount: amount, rawPersonalAmount: personalAmountForStats)
            : nil

        let reimbursementForID: UUID?
        if movementType == .income && isReimbursementIncome && canConfigureOwnershipFields {
            recordSaveDiagnostic("resolve_reimbursement_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
            if let linkedExpense = selectedReimbursementExpense {
                reimbursementForID = linkedExpense.id
            } else if let existingReimbursementForID = movementToEdit?.reimbursementForId,
                      movements.contains(where: { $0.id == existingReimbursementForID && $0.type == .expense }) {
                reimbursementForID = existingReimbursementForID
            } else {
                recordSaveDiagnostic("resolve_reimbursement_failed", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
                validationMessage = "No se pudo resolver el gasto vinculado para este reembolso."
                showingValidationAlert = true
                return
            }
            recordSaveDiagnostic("resolve_reimbursement_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)

            if let linkedExpense = selectedReimbursementExpense,
               linkedExpense.account?.isArchived == true,
               linkedExpense.account?.id == selectedAccount.id {
                validationMessage = "El reembolso de un gasto de una cuenta archivada debe registrarse en otra cuenta activa distinta."
                showingValidationAlert = true
                return
            }
        } else {
            reimbursementForID = nil
        }

        if movementType == .transfer {
            guard let selectedDestinationAccount else {
                recordSaveDiagnostic("resolve_destination_account_failed", accountID: selectedAccount.id)
                validationMessage = "Selecciona una cuenta destino para la transferencia."
                showingValidationAlert = true
                return
            }

            guard selectedDestinationAccount.isActive else {
                validationMessage = "Selecciona una cuenta destino activa."
                showingValidationAlert = true
                return
            }

            guard selectedDestinationAccount.id != selectedAccount.id else {
                recordSaveDiagnostic("resolve_destination_account_same_as_source", accountID: selectedAccount.id)
                validationMessage = "La cuenta origen y destino no pueden ser la misma."
                showingValidationAlert = true
                return
            }
        }

        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let recurringConfiguration: (startDate: Date, endDate: Date?, anchorDay: Int)?

        if isRecurring && allowsRecurringConfiguration {
            let normalizedStart = Calendar.current.startOfDay(for: recurringStartDate)
            let normalizedEnd = recurringHasEndDate ? Calendar.current.startOfDay(for: recurringEndDate) : nil

            if let normalizedEnd, normalizedEnd < normalizedStart {
                recordSaveDiagnostic("validate_recurring_end_failed", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
                validationMessage = "La fecha de fin no puede ser anterior al inicio."
                showingValidationAlert = true
                return
            }

            recurringConfiguration = (
                startDate: normalizedStart,
                endDate: normalizedEnd,
                anchorDay: Calendar.current.component(.day, from: normalizedStart)
            )
        } else {
            recurringConfiguration = nil
        }

        if isRecurring && !isEditing && allowsRecurringConfiguration {
            guard let recurringConfiguration else { return }

            let recurringMovement = RecurringMovement(
                concept: trimmedConcept,
                amount: amount,
                type: movementType,
                frequency: recurringFrequency,
                dayOfMonth: recurringConfiguration.anchorDay,
                startDate: recurringConfiguration.startDate,
                endDate: recurringConfiguration.endDate,
                account: selectedAccount,
                category: selectedCategory,
                notes: notes,
                isActive: true
            )

            recordSaveDiagnostic("insert_recurring_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
            modelContext.insert(recurringMovement)
            recordSaveDiagnostic("insert_recurring_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
            saveContextAndDismiss()
            return
        }

        let editedMovementWasExpense = movementToEdit?.type == .expense
        var movementForBudgetReevaluation: Movement?

        if let movementToEdit {
            recordSaveDiagnostic("update_existing_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
            revertMovementImpact(movementToEdit)

            recordSaveDiagnostic("apply_impact_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
            let resultingBalance = applyMovementImpact(
                type: movementType,
                amount: amount,
                sourceAccount: selectedAccount,
                destinationAccount: movementType == .transfer ? selectedDestinationAccount : nil
            )
            recordSaveDiagnostic("apply_impact_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)

            movementToEdit.concept = trimmedConcept
            movementToEdit.amount = amount
            movementToEdit.type = movementType
            movementToEdit.occurredAt = occurredAt
            movementToEdit.account = selectedAccount
            movementToEdit.destinationAccount = movementType == .transfer ? selectedDestinationAccount : nil
            movementToEdit.category = movementType == .transfer ? nil : selectedCategory
            movementToEdit.notes = notes
            movementToEdit.resultingBalance = resultingBalance
            movementToEdit.personalAmount = normalizedPersonalAmountForStats
            movementToEdit.reimbursementForId = movementType == .income ? reimbursementForID : nil

            let shouldUnlinkExistingReimbursements = movementType != .expense || normalizedPersonalAmountForStats == nil
            if shouldUnlinkExistingReimbursements {
                unlinkReimbursementsLinkedToExpense(expenseID: movementToEdit.id)
            }

            if isRecurring {
                guard let recurringConfiguration else { return }

                if let recurring = linkedRecurringRule(for: movementToEdit) {
                    recurring.concept = trimmedConcept
                    recurring.amount = amount
                    recurring.type = movementType
                    recurring.frequency = recurringFrequency
                    recurring.dayOfMonth = recurringConfiguration.anchorDay
                    recurring.startDate = recurringConfiguration.startDate
                    recurring.endDate = recurringConfiguration.endDate
                    recurring.account = selectedAccount
                    recurring.category = selectedCategory
                    recurring.notes = notes
                    recurring.isActive = true
                    recurring.updatedAt = Date()
                    movementToEdit.recurringRuleId = recurring.id
                    movementToEdit.recurringScheduledAt = Calendar.current.startOfDay(for: movementToEdit.occurredAt)
                } else {
                    let recurring = RecurringMovement(
                        concept: trimmedConcept,
                        amount: amount,
                        type: movementType,
                        frequency: recurringFrequency,
                        dayOfMonth: recurringConfiguration.anchorDay,
                        startDate: recurringConfiguration.startDate,
                        endDate: recurringConfiguration.endDate,
                        account: selectedAccount,
                        category: selectedCategory,
                        notes: notes,
                        isActive: true
                    )
                    modelContext.insert(recurring)
                    movementToEdit.recurringRuleId = recurring.id
                    movementToEdit.recurringScheduledAt = Calendar.current.startOfDay(for: movementToEdit.occurredAt)
                }
            } else {
                if let recurring = linkedRecurringRule(for: movementToEdit) {
                    recurring.isActive = false
                    recurring.updatedAt = Date()
                }
                movementToEdit.recurringRuleId = nil
                movementToEdit.recurringScheduledAt = nil
            }

            movementToEdit.updatedAt = Date()
            recordSaveDiagnostic("update_existing_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
        } else {
            recordSaveDiagnostic("apply_impact_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
            let resultingBalance = applyMovementImpact(
                type: movementType,
                amount: amount,
                sourceAccount: selectedAccount,
                destinationAccount: movementType == .transfer ? selectedDestinationAccount : nil
            )
            recordSaveDiagnostic("apply_impact_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)

            recordSaveDiagnostic("create_movement_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
            let movement = Movement(
                concept: trimmedConcept,
                amount: amount,
                type: movementType,
                occurredAt: occurredAt,
                account: selectedAccount,
                destinationAccount: movementType == .transfer ? selectedDestinationAccount : nil,
                category: movementType == .transfer ? nil : selectedCategory,
                notes: notes,
                resultingBalance: resultingBalance,
                personalAmount: normalizedPersonalAmountForStats,
                reimbursementForId: movementType == .income ? reimbursementForID : nil
            )
            
            recordSaveDiagnostic("insert_movement_before", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
            modelContext.insert(movement)
            recordSaveDiagnostic("insert_movement_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)

            if movementType == .expense {
                movementForBudgetReevaluation = movement
            }
        }

        saveContextAndDismiss(
            reevaluateBudgetsAfterSave: movementType == .expense || editedMovementWasExpense,
            budgetMovementToAppendAfterSave: movementForBudgetReevaluation
        )
    }

    private func saveContextAndDismiss(
        reevaluateBudgetsAfterSave: Bool = false,
        budgetMovementToAppendAfterSave: Movement? = nil
    ) {
        do {
            recordSaveDiagnostic("modelContext_save_before")
            try modelContext.save()
            recordSaveDiagnostic("modelContext_save_after")

            if reevaluateBudgetsAfterSave {
                recordSaveDiagnostic("budget_reevaluate_before")
                reevaluateBudgetNotifications(appending: budgetMovementToAppendAfterSave)
                recordSaveDiagnostic("budget_reevaluate_after")
            } else {
                recordSaveDiagnostic("budget_reevaluate_skipped")
            }

            dismiss()
        } catch {
            recordSaveDiagnostic("modelContext_save_failed", error: error)
            validationMessage = "No se pudo guardar el movimiento: \(error.localizedDescription)"
            showingValidationAlert = true
        }
    }

    private func recordSaveDiagnostic(
        _ checkpoint: String,
        accountID: UUID? = nil,
        categoryID: UUID? = nil,
        reimbursementForID: UUID? = nil,
        error: Error? = nil
    ) {
        var parts = [
            "AddMovement.save",
            "checkpoint=\(checkpoint)",
            "type=\(movementType.rawValue)",
            "edit=\(isEditing)",
            "rec=\(isRecurring)",
            "shared=\(isSharedExpense)",
            "reimb=\(isReimbursementIncome)",
            "counts=\(accounts.count)/\(categories.count)/\(movements.count)",
            "amountEmpty=\(amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)",
            "personalEmpty=\(personalAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"
        ]

        if let movementID = movementToEdit?.id {
            parts.append("movement=\(shortID(movementID))")
        }
        if let selectedAccountID = selectedAccount?.id {
            parts.append("selectedAccount=\(shortID(selectedAccountID))")
        }
        if movementType == .transfer, let selectedDestinationAccountID = selectedDestinationAccount?.id {
            parts.append("selectedDestination=\(shortID(selectedDestinationAccountID))")
        }
        if let selectedCategoryID = selectedCategory?.id {
            parts.append("selectedCategory=\(shortID(selectedCategoryID))")
        }
        if let selectedReimbursementExpenseID = selectedReimbursementExpense?.id {
            parts.append("selectedReimbExpense=\(shortID(selectedReimbursementExpenseID))")
        }
        if let accountID {
            parts.append("account=\(shortID(accountID))")
        }
        if let categoryID {
            parts.append("category=\(shortID(categoryID))")
        }
        if let reimbursementForID {
            parts.append("reimbursementFor=\(shortID(reimbursementForID))")
        }
        if let error {
            parts.append("errorType=\(type(of: error))")
            parts.append("error=\(error.localizedDescription)")
        }

        CrashReportService.shared.recordDiagnosticEvent(parts.joined(separator: " "))
    }

    private func shortID(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    private func reevaluateBudgetNotifications(appending movement: Movement? = nil) {
        guard let activeBudget = budgets.first(where: { $0.isActive }) else { return }

        var updatedMovements = movements
        if let movement, !updatedMovements.contains(where: { $0.id == movement.id }) {
            updatedMovements.append(movement)
        }

        BudgetService.evaluateAndNotify(budget: activeBudget, movements: updatedMovements)
    }

    @discardableResult
    private func applyMovementImpact(
        type: MovementType,
        amount: Decimal,
        sourceAccount: BankAccount,
        destinationAccount: BankAccount?
    ) -> Decimal {
        sourceAccount.currency = appCurrencyCode

        switch type {
        case .expense:
            sourceAccount.balance -= amount
        case .income:
            sourceAccount.balance += amount
        case .transfer:
            sourceAccount.balance -= amount
            if sourceAccount.isInvestmentAccount {
                sourceAccount.investedAmount = max(0, sourceAccount.effectiveInvestedAmount - amount)
            }
            if let destinationAccount {
                destinationAccount.currency = appCurrencyCode
                destinationAccount.balance += amount
                if destinationAccount.isInvestmentAccount {
                    destinationAccount.investedAmount = destinationAccount.effectiveInvestedAmount + amount
                }
                destinationAccount.updatedAt = Date()
            }
        }

        sourceAccount.updatedAt = Date()
        return sourceAccount.balance
    }

    private func revertMovementImpact(_ movement: Movement) {
        guard let sourceAccount = movement.account else { return }

        switch movement.type {
        case .expense:
            sourceAccount.balance += movement.amount
        case .income:
            sourceAccount.balance -= movement.amount
        case .transfer:
            sourceAccount.balance += movement.amount
            if sourceAccount.isInvestmentAccount {
                sourceAccount.investedAmount = sourceAccount.effectiveInvestedAmount + movement.amount
            }
            if let destination = movement.destinationAccount {
                destination.balance -= movement.amount
                if destination.isInvestmentAccount {
                    destination.investedAmount = max(0, destination.effectiveInvestedAmount - movement.amount)
                }
                destination.updatedAt = Date()
            }
        }

        sourceAccount.updatedAt = Date()
    }

    private func ensureTransferAccountsAreDifferent() {
        guard let selectedAccount else { return }
        if selectedDestinationAccount?.id == selectedAccount.id {
            selectedDestinationAccount = accountsSortedByBankThenName.first(where: { $0.id != selectedAccount.id })
        }
    }

    private func activeReimbursementAccount(for expense: Movement) -> BankAccount? {
        activeAccounts.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        .first { account in
            guard expense.account?.isArchived == true, let archivedExpenseAccountID = expense.account?.id else { return true }
            return account.id != archivedExpenseAccountID
        }
    }

    private func movementTouchesArchivedAccount(_ movement: Movement) -> Bool {
        if movement.account?.isArchived == true || movement.destinationAccount?.isArchived == true {
            return true
        }

        guard movement.type == .income, let reimbursementForId = movement.reimbursementForId else { return false }
        return movements.first(where: { $0.id == reimbursementForId })?.account?.isArchived == true
    }

    private func unlinkReimbursementsLinkedToExpense(expenseID: UUID) {
        for movement in movements where movement.type == .income && movement.reimbursementForId == expenseID {
            movement.reimbursementForId = nil
            movement.updatedAt = Date()
        }
    }

    private func linkedRecurringRule(for movement: Movement) -> RecurringMovement? {
        guard let recurringRuleId = movement.recurringRuleId else { return nil }
        return recurringMovements.first(where: { $0.id == recurringRuleId })
    }
}

private struct MovementDraftHero: View {
    @Binding var title: String
    @Binding var amountText: String
    @Binding var type: MovementType
    var isMovementTypeLocked: Bool = false
    @Binding var selectedAccount: BankAccount?
    @Binding var selectedDestinationAccount: BankAccount?
    @Binding var selectedCategory: MovementCategory?
    let accountGroups: [AccountBankGroup]
    let categories: [MovementCategory]
    let currencyCode: String
    let tint: Color
    var onCreateCategory: () -> Void

    private var accountName: String {
        selectedAccount?.name ?? "Sin cuenta"
    }

    private var destinationAccountName: String {
        selectedDestinationAccount?.name ?? "Sin destino"
    }

    private var categoryName: String {
        selectedCategory?.name ?? "Sin categoría"
    }

    private var accounts: [BankAccount] {
        accountGroups.flatMap(\.accounts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    typeSelector

                    TextField("Concepto del movimiento", text: $title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .font(.title3.weight(.bold))
                        .lineLimit(1...2)
                        .tint(tint)
                }

                Spacer()

                FinanceGlassIconBadge(systemName: type.icon, tint: tint, size: 46)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0,00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .tint(tint)

                CurrencySymbolLabel(code: currencyCode, companion: .hero)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    accountSelector

                    if type == .transfer {
                        destinationAccountSelector
                    } else {
                        categorySelector
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    accountSelector

                    if type == .transfer {
                        destinationAccountSelector
                    } else {
                        categorySelector
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeGlassColorCard(
            gradient: LinearGradient(
                colors: [tint.opacity(0.20), Color.financeAccent.opacity(0.10), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            cornerRadius: FinanceGlassTokens.Radius.hero
        )
    }

    @ViewBuilder
    private var typeSelector: some View {
        if isMovementTypeLocked {
            Text(MovementType.income.displayName)
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(tint)
                .accessibilityLabel("Tipo de movimiento")
                .accessibilityValue(MovementType.income.displayName)
                .accessibilityHint("No editable en un reembolso vinculado")
        } else {
            Menu {
                ForEach(MovementType.allCases) { option in
                    Button {
                        type = option
                    } label: {
                        Label(option.displayName, systemImage: option.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(type.displayName)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(tint)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tipo de movimiento")
            .accessibilityValue(type.displayName)
        }
    }

    private var accountSelector: some View {
        Menu {
            ForEach(accountGroups) { group in
                Section(group.bankName) {
                    ForEach(group.accounts, id: \.id) { account in
                        Button {
                            selectedAccount = account
                        } label: {
                            Label(account.name, systemImage: account.id == selectedAccount?.id ? "checkmark" : accountIconName(for: account))
                        }
                    }
                }
            }
        } label: {
            quickSelectorLabel(title: accountName, systemImage: type == .transfer ? "arrow.up.right.circle" : "creditcard")
        }
        .disabled(accounts.isEmpty)
        .buttonStyle(.plain)
        .accessibilityLabel(type == .transfer ? "Cuenta origen" : "Cuenta")
        .accessibilityValue(accountName)
    }

    private var destinationAccountSelector: some View {
        Menu {
            ForEach(accountGroups) { group in
                let destinationAccounts = group.accounts.filter { $0.id != selectedAccount?.id }
                if !destinationAccounts.isEmpty {
                    Section(group.bankName) {
                        ForEach(destinationAccounts, id: \.id) { account in
                            Button {
                                selectedDestinationAccount = account
                            } label: {
                                Label(account.name, systemImage: account.id == selectedDestinationAccount?.id ? "checkmark" : accountIconName(for: account))
                            }
                        }
                    }
                }
            }
        } label: {
            quickSelectorLabel(title: destinationAccountName, systemImage: "arrow.down.left.circle")
        }
        .disabled(accounts.isEmpty)
        .buttonStyle(.plain)
        .accessibilityLabel("Cuenta destino")
        .accessibilityValue(destinationAccountName)
    }

    private var categorySelector: some View {
        Menu {
            ForEach(categories, id: \.id) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Label(category.name, systemImage: category.id == selectedCategory?.id ? "checkmark" : category.iconName)
                }
            }

            Divider()

            Button {
                onCreateCategory()
            } label: {
                Label("Crear categoría", systemImage: "plus.circle")
            }
        } label: {
            quickSelectorLabel(title: categoryName, systemImage: selectedCategory?.iconName ?? "tag")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Categoría")
        .accessibilityValue(categoryName)
    }

    private func quickSelectorLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .opacity(0.62)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
    }

    private func accountIconName(for account: BankAccount) -> String {
        account.isInvestmentAccount ? "chart.line.uptrend.xyaxis" : "building.columns"
    }
}

private struct MovementEditorInlineAmountRow: View {
    let label: String
    @Binding var text: String
    let currencyCode: String
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()

            TextField(label, text: $text)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.trailing)
                .tint(tint)

            CurrencySymbolLabel(code: currencyCode, companion: .inline)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(text) \(AppCurrency.displayName(for: currencyCode))")
    }
}

private struct MovementEditorSectionHeader: View {
    let title: String
    let systemImage: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.primary.opacity(0.82))
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct MovementEditorDetailSectionModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var surface: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.black.opacity(0.025)
    }

    private var stroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.black.opacity(0.03)
    }

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 1)
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            )
    }
}

private extension View {
    func movementEditorDetailSection() -> some View {
        modifier(MovementEditorDetailSectionModifier())
    }
}

/// Sheet para crear una categoría nueva en caliente desde el formulario.
private struct CreateMovementCategorySheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]

    @Binding var categoryName: String
    var onCreated: (MovementCategory) -> Void

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var selectedIcon: CategoryIcon = .tag
    @State private var selectedColor: CategoryColor = .blue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $categoryName)
                }
                header: {
                    FinanceGlassSectionHeader(title: "Nombre de la categoría", systemImage: "textformat", subtitle: "Cómo aparecerá en tus movimientos")
                }
                .financeGlassFormSection()

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryIcon.allCases) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon.systemName)
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 38, height: 38)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                    .background(selectedIcon == icon ? selectedColor.color : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selectedIcon == icon ? Color.clear : Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                header: {
                    FinanceGlassSectionHeader(title: "Icono", systemImage: "square.grid.3x3", subtitle: "Identifica la categoría de un vistazo")
                }
                .financeGlassFormSection()

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryColor.allCases) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                    )
                                    .overlay(
                                        Circle().stroke(color.color, lineWidth: selectedColor == color ? 1 : 0)
                                            .padding(-2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                header: {
                    FinanceGlassSectionHeader(title: "Color", systemImage: "paintpalette", subtitle: "Acento visual para gráficos y listados")
                }
                .financeGlassFormSection()
            }
            .financeGlassListContainer()
            .navigationTitle("Nueva categoría")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        createCategory()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Error", isPresented: $showingValidationAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func createCategory() {
        let trimmed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "El nombre de la categoría es obligatorio."
            showingValidationAlert = true
            return
        }

        let duplicateExists = categories.contains {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !duplicateExists else {
            validationMessage = "Ya existe una categoría con ese nombre."
            showingValidationAlert = true
            return
        }

        let category = MovementCategory(name: trimmed, icon: selectedIcon, color: selectedColor)
        modelContext.insert(category)
        onCreated(category)
        dismiss()
    }
}
