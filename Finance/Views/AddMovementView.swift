//
//  AddMovementView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData

private enum RecurringMovementEditScope: String, CaseIterable, Identifiable {
    case occurrenceOnly
    case thisAndFuture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .occurrenceOnly:
            return "Solo este"
        case .thisAndFuture:
            return "Este y futuros"
        }
    }
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
    @Query private var linkedReimbursementIncomes: [Movement]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]

    @State private var selectedAccount: BankAccount?
    @State private var selectedDestinationAccount: BankAccount?
    @State private var movementType: MovementType = .expense
    @State private var amountText: String = ""
    @State private var amountExpression: String = ""
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
    @State private var recurringEditScope: RecurringMovementEditScope = .occurrenceOnly
    @State private var isSharedExpense = false
    @State private var personalAmountText: String = ""
    @State private var personalAmountExpression: String = ""
    @State private var isReimbursementIncome = false
    @State private var selectedReimbursementExpense: Movement?
    @State private var showingQuickReimbursementSheet = false
    @State private var cachedAccountGroups: [MovementAccountBankGroup] = []
    @FocusState private var heroFocusedField: MovementDraftHeroField?
    @FocusState private var personalAmountFocused: Bool

    @State private var amountCalculatorError: String?
    @State private var amountCalculatorErrorHaptic = 0
    @State private var hasConfirmedReceiptAmount = false
    @State private var hasConfirmedReceiptCurrencyMismatch = false

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var didLoadExistingData = false

    private var recurringCalendar: Calendar {
        RecurringMovementService.recurrenceCalendar
    }

    private let movementToEdit: Movement?
    private let preselectedType: MovementType?
    private let preselectedAccountID: UUID?
    private let prefilledConcept: String?
    private let linkedReimbursementExpenseID: UUID?
    private let movementToDuplicate: Movement?
    private let walletExpenseDraft: WalletExpenseDraft?
    private let receiptScanDraft: ReceiptScanDraft?

    private var isEditing: Bool {
        movementToEdit != nil
    }

    private var isDuplicating: Bool {
        movementToDuplicate != nil
    }

    private var linkedRecurringRuleForEditing: RecurringMovement? {
        movementToEdit.flatMap(linkedRecurringRule(for:))
    }

    private var editorNavigationTitle: String {
        if isEditing {
            return "Editar movimiento"
        }
        if isDuplicating {
            return "Duplicar movimiento"
        }
        if linkedReimbursementExpenseID != nil {
            return "Registrar reembolso"
        }
        if walletExpenseDraft != nil {
            return "Gasto de Wallet"
        }
        if receiptScanDraft != nil {
            return "Gasto desde ticket"
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
        linkedReimbursementExpenseID: UUID? = nil,
        movementToDuplicate: Movement? = nil,
        walletExpenseDraft: WalletExpenseDraft? = nil,
        receiptScanDraft: ReceiptScanDraft? = nil
    ) {
        self.movementToEdit = movementToEdit
        self.preselectedType = preselectedType
        self.preselectedAccountID = preselectedAccountID
        self.prefilledConcept = prefilledConcept
        self.linkedReimbursementExpenseID = linkedReimbursementExpenseID
        self.movementToDuplicate = movementToDuplicate
        self.walletExpenseDraft = walletExpenseDraft
        self.receiptScanDraft = receiptScanDraft

        // Scope this query to the expense currently being edited. The empty
        // sentinel is used only for create/duplicate contexts where the result
        // is not consumed.
        let expenseID = movementToEdit?.type == .expense
            ? (movementToEdit?.id ?? UUID())
            : UUID()
        _linkedReimbursementIncomes = Query(
            filter: #Predicate<Movement> { reimbursement in
                reimbursement.typeRaw == "income"
                    && reimbursement.reimbursementForId == expenseID
            },
            sort: [SortDescriptor(\Movement.occurredAt, order: .reverse)]
        )
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

    private var accountGroupingSignature: String {
        accountsSortedByBankThenName.map(\.id.uuidString).joined(separator: "|")
    }

    private func buildAccountGroups(from sortedAccounts: [BankAccount]) -> [MovementAccountBankGroup] {
        let grouped = Dictionary(grouping: sortedAccounts) { account in
            account.bank?.id.uuidString ?? "no-bank"
        }

        return grouped
            .compactMap { key, groupedAccounts in
                guard let first = groupedAccounts.first else { return nil }
                return MovementAccountBankGroup(id: key, bankName: first.bankDisplayName, accounts: groupedAccounts)
            }
            .sorted { lhs, rhs in
                lhs.bankName.localizedCaseInsensitiveCompare(rhs.bankName) == .orderedAscending
            }
    }

    private func refreshCachedAccountGroups() {
        cachedAccountGroups = buildAccountGroups(from: accountsSortedByBankThenName)
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
        isLinkedReimbursementContext || linkedRecurringRuleForEditing != nil
    }

    private var receiptCurrencyMismatch: Bool {
        guard let sourceCurrencyCode = receiptScanDraft?.currencyCode,
              receiptScanDraft?.amount != nil else { return false }
        return sourceCurrencyCode != appCurrencyCode.uppercased()
    }

    private var receiptAmountIsAmbiguous: Bool {
        receiptScanDraft?.amountStatus == .ambiguous
    }

    private var linkedReimbursementsForEditedExpense: [Movement] {
        guard let movementToEdit, movementToEdit.type == .expense else { return [] }
        return linkedReimbursementIncomes
    }

    private var expectedReimbursementForDraftExpense: Decimal {
        guard movementType == .expense, isSharedExpense else { return 0 }
        let total = parseHeroAmount()
        let personal = parsePersonalAmount()
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
        parseHeroAmount()
    }

    private var draftSharedExpensePersonalAmount: Decimal {
        parsePersonalAmount()
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
                if let walletExpenseDraft {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Borrador desde Wallet", systemImage: "wallet.pass.fill")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Revisa el importe y el comercio, elige la cuenta y la categoría y pulsa Guardar. Finance no registrará nada antes de esa confirmación.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let cardName = walletExpenseDraft.cardName {
                                Label(cardName, systemImage: "creditcard")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let sourceCurrencyCode = walletExpenseDraft.currencyCode,
                               sourceCurrencyCode != appCurrencyCode {
                                Label(
                                    "Wallet indicó \(sourceCurrencyCode), pero Finance usa \(appCurrencyCode). Revisa el importe antes de guardar.",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .financeGlassColorCard(
                            gradient: LinearGradient(
                                colors: [Color.blue.opacity(0.18), Color.financeAccent.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            cornerRadius: FinanceGlassTokens.Radius.card
                        )
                        .accessibilityElement(children: .combine)
                    }
                    .financeGlassClearListRow()
                }

                if receiptScanDraft != nil {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Borrador desde ticket", systemImage: "doc.viewfinder.fill")
                                .font(.headline)

                            Text("Revisa los datos detectados, completa la cuenta y la categoría y pulsa Guardar. Finance no registrará nada hasta tu confirmación.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Label("Cuenta y categoría: selección manual", systemImage: "hand.tap.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let receiptScanDraft {
                                ForEach(receiptScanDraft.warnings, id: \.self) { warning in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(Color(red: 0.66, green: 0.29, blue: 0.03))
                                            .accessibilityHidden(true)

                                        Text(warning)
                                            .foregroundStyle(.primary)
                                    }
                                    .font(.caption)
                                }

                                if receiptScanDraft.amountStatus == .ambiguous {
                                    Toggle("Confirmar importe sugerido", isOn: $hasConfirmedReceiptAmount)
                                        .font(.caption)
                                        .tint(.orange)
                                }

                                if receiptCurrencyMismatch {
                                    Label {
                                        Text("El ticket está en \(receiptScanDraft.currencyCode ?? "otra moneda") y Finance registra importes en \(appCurrencyCode). Convierte o revisa el importe manualmente.")
                                            .foregroundStyle(.primary)
                                    } icon: {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(Color(red: 0.66, green: 0.29, blue: 0.03))
                                    }
                                    .font(.caption)

                                    Toggle("He revisado o convertido el importe", isOn: $hasConfirmedReceiptCurrencyMismatch)
                                        .font(.caption)
                                        .tint(.orange)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .financeGlassColorCard(
                            gradient: LinearGradient(
                                colors: [Color.financeAccent.opacity(0.18), Color.teal.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            cornerRadius: FinanceGlassTokens.Radius.card
                        )
                        .accessibilityElement(children: .combine)
                    }
                    .financeGlassClearListRow()
                }

                if isDuplicating {
                    Section {
                        Label(
                            "Se creará un movimiento nuevo con estos datos. La fecha será la de ahora y no se copiarán saldo, reembolso ni recurrencia.",
                            systemImage: "doc.on.doc"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }
                    .financeGlassClearListRow()
                }

                Section {
                    MovementDraftHero(
                        title: $concept,
                        amountText: $amountText,
                        amountExpression: $amountExpression,
                        amountErrorMessage: $amountCalculatorError,
                        type: $movementType,
                        isMovementTypeLocked: isMovementTypeLocked,
                        selectedAccount: $selectedAccount,
                        selectedDestinationAccount: $selectedDestinationAccount,
                    selectedCategory: $selectedCategory,
                    categories: categories,
                    hasActiveAccounts: !activeAccounts.isEmpty,
                    currencyCode: appCurrencyCode,
                    tint: movementTint,
                    focusedField: $heroFocusedField,
                        onAmountDone: {
                            heroFocusedField = nil
                        },
                        onDismissAmountKeyboard: dismissAmountKeyboardIfActive,
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
                                .simultaneousGesture(TapGesture().onEnded {
                                    dismissAmountKeyboardIfActive()
                                })

                            if isSharedExpense {
                                MovementEditorInlineAmountRow(
                                    label: "Mi parte",
                                    text: $personalAmountText,
                                    expression: $personalAmountExpression,
                                    errorMessage: $amountCalculatorError,
                                    currencyCode: appCurrencyCode,
                                    tint: movementTint,
                                    isFocused: $personalAmountFocused,
                                    onDone: {
                                        personalAmountFocused = false
                                    }
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
                            if let linkedRecurringRuleForEditing {
                                if linkedRecurringRuleForEditing.isActive {
                                    Picker("Aplicar cambios", selection: $recurringEditScope) {
                                        ForEach(RecurringMovementEditScope.allCases) { scope in
                                            Text(scope.title)
                                                .tag(scope)
                                        }
                                    }
                                    .pickerStyle(.segmented)

                                    if recurringEditScope == .thisAndFuture {
                                        Picker("Frecuencia", selection: $recurringFrequency) {
                                            ForEach(RecurringMovementFrequency.allCases) { frequency in
                                                Text(frequency.displayName)
                                                    .tag(frequency)
                                            }
                                        }

                                        Toggle("Fecha de fin", isOn: $recurringHasEndDate)

                                        if recurringHasEndDate {
                                            DatePicker(
                                                "Fin",
                                                selection: $recurringEndDate,
                                                in: recurringStartDate...,
                                                displayedComponents: .date
                                            )
                                        }

                                        Text("La plantilla se actualizará desde la ocurrencia programada del \(recurringStartDate.asSpanishShortDate()). Los movimientos anteriores conservarán sus importes reales.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("Solo se actualizará este movimiento. La plantilla recurrente no cambiará.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Esta recurrencia ya está finalizada. Solo se actualizará este movimiento.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
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
            .scrollDismissesKeyboard(.immediately)
            .financeGlassPageBackground()
            .navigationTitle(editorNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
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

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveMovement()
                    } label: {
                        Label(isEditing ? "Actualizar" : "Guardar", systemImage: "checkmark")
                    }
                    .fontWeight(.semibold)
                    .disabled(activeAccounts.isEmpty)
                    .accessibilityLabel(isEditing ? "Actualizar movimiento" : "Guardar movimiento")
                }

                if heroFocusedField != .amount, !personalAmountFocused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Listo") {
                            heroFocusedField = nil
                            personalAmountFocused = false
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .sensoryFeedback(.error, trigger: amountCalculatorErrorHaptic)
            .onChange(of: heroFocusedField) { oldValue, newValue in
                if newValue == .amount {
                    amountCalculatorError = nil
                }
                if oldValue == .amount, newValue != .amount {
                    scheduleAmountExpressionFinalization {
                        guard heroFocusedField != .amount else { return }
                        finalizeAmountExpression(expression: &amountExpression, amount: &amountText)
                    }
                }
            }
            .onChange(of: personalAmountFocused) { wasFocused, isFocused in
                if isFocused {
                    amountCalculatorError = nil
                }
                if wasFocused, !isFocused {
                    scheduleAmountExpressionFinalization {
                        guard !personalAmountFocused else { return }
                        finalizeAmountExpression(expression: &personalAmountExpression, amount: &personalAmountText)
                    }
                }
            }
            .movementEditorSheetPresentation(isEditing: isEditing)
            .environment(\.dismissAmountKeyboard, dismissAmountKeyboardIfActive)
            .onAppear {
                refreshCachedAccountGroups()
                setupDefaults()
                if !isEditing, !isDuplicating, linkedReimbursementExpenseID == nil {
                    heroFocusedField = walletExpenseDraft == nil && receiptScanDraft == nil ? .concept : nil
                }
            }
            .onChange(of: accountGroupingSignature) { _, _ in
                refreshCachedAccountGroups()
            }
            .onChange(of: movementType) { _, newValue in
                if newValue == .transfer {
                    selectedCategory = nil
                    categorySearchText = ""
                    isRecurring = false
                    isSharedExpense = false
                    personalAmountText = ""
                    personalAmountExpression = ""
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
                    personalAmountExpression = ""
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
                    personalAmountExpression = ""
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
            amountText = movementToEdit.amount.asEditableAmount()
            amountExpression = ""
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
                    personalAmountText = personalAmount.asEditableAmount()
                    personalAmountExpression = ""
                }
            } else {
                isSharedExpense = false
                personalAmountText = ""
                personalAmountExpression = ""
            }

            if movementToEdit.type == .income,
               let reimbursementForId = movementToEdit.reimbursementForId {
                isReimbursementIncome = true
                selectedReimbursementExpense = fetchExpenseMovement(id: reimbursementForId)
            } else {
                isReimbursementIncome = false
                selectedReimbursementExpense = nil
            }

            if let recurring = linkedRecurringRule(for: movementToEdit) {
                isRecurring = recurring.isActive
                recurringEditScope = .occurrenceOnly
                recurringFrequency = recurring.frequency
                recurringStartDate = recurringCalendar.startOfDay(
                    for: movementToEdit.recurringScheduledAt ?? recurring.startDate
                )
                if let endDate = recurring.endDate {
                    recurringHasEndDate = true
                    recurringEndDate = recurringCalendar.startOfDay(for: endDate)
                } else {
                    recurringHasEndDate = false
                    recurringEndDate = recurringStartDate
                }
            } else {
                isRecurring = false
                recurringFrequency = .monthly
                recurringStartDate = recurringCalendar.startOfDay(for: movementToEdit.occurredAt)
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

                if !didLoadExistingData, let walletExpenseDraft {
            movementType = .expense
            amountText = walletExpenseDraft.amount?.asEditableAmount() ?? ""
            amountExpression = ""
            concept = walletExpenseDraft.suggestedConcept
            selectedAccount = nil
            selectedDestinationAccount = nil
            selectedCategory = nil
            occurredAt = walletExpenseDraft.transactionDate
            notes = ""
            isRecurring = false
            isSharedExpense = false
            isReimbursementIncome = false
            selectedReimbursementExpense = nil
            recurringFrequency = .monthly
            recurringStartDate = recurringCalendar.startOfDay(for: occurredAt)
            recurringHasEndDate = false
            recurringEndDate = recurringStartDate
            didLoadExistingData = true
            refreshCachedAccountGroups()
            return
        }

        if !didLoadExistingData, let receiptScanDraft {
            movementType = .expense
            amountText = receiptScanDraft.amount?.asEditableAmount() ?? ""
            amountExpression = ""
            concept = receiptScanDraft.merchant ?? "Gasto escaneado"
            selectedAccount = nil
            selectedDestinationAccount = nil
            selectedCategory = nil
            occurredAt = receiptScanDraft.occurredAt ?? Date()
            notes = ""
            isRecurring = false
            isSharedExpense = false
            isReimbursementIncome = false
            selectedReimbursementExpense = nil
            recurringFrequency = .monthly
            recurringStartDate = recurringCalendar.startOfDay(for: occurredAt)
            recurringHasEndDate = false
            recurringEndDate = recurringStartDate
            didLoadExistingData = true
            refreshCachedAccountGroups()
            return
        }

        if !didLoadExistingData, let movementToDuplicate {
            let draft = movementToDuplicate.duplicatedForNewEntry()
            selectedAccount = draft.account?.isActive == true ? draft.account : nil
            selectedDestinationAccount = draft.destinationAccount?.isActive == true ? draft.destinationAccount : nil
            movementType = draft.type
            amountText = draft.amount.asEditableAmount()
            concept = draft.concept
            selectedCategory = draft.category
            occurredAt = draft.occurredAt
            notes = draft.notes
            isSharedExpense = draft.type == .expense && draft.normalizedPersonalAmount != nil
            if isSharedExpense, let personalAmount = draft.normalizedPersonalAmount {
                personalAmountText = personalAmount.asEditableAmount()
            }
            isRecurring = false
            isReimbursementIncome = false
            selectedReimbursementExpense = nil
            didLoadExistingData = true
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
           let linkedExpense = fetchExpenseMovement(id: linkedReimbursementExpenseID) {
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
        recurringStartDate = recurringCalendar.startOfDay(for: occurredAt)
        recurringEndDate = recurringStartDate

        ensureTransferAccountsAreDifferent()
        refreshCachedAccountGroups()
    }

    private func parseHeroAmount() -> Decimal {
        parsedAmount(display: amountText, expression: amountExpression)
    }

    private func parsePersonalAmount() -> Decimal {
        parsedAmount(display: personalAmountText, expression: personalAmountExpression)
    }

    private func parsedAmount(display: String, expression: String) -> Decimal {
        if AmountExpressionEvaluator.containsExpression(expression) {
            if let preview = AmountExpressionEvaluator.previewValue(for: expression) {
                return preview
            }
            return EditableAmount.parse(display) ?? 0
        }
        return EditableAmount.parse(display) ?? 0
    }

    private func scheduleAmountExpressionFinalization(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            action()
        }
    }

    private func dismissAmountKeyboardIfActive() {
        guard heroFocusedField == .amount || personalAmountFocused else { return }

        finalizeAmountExpression(expression: &amountExpression, amount: &amountText)
        finalizeAmountExpression(expression: &personalAmountExpression, amount: &personalAmountText)
        heroFocusedField = nil
        personalAmountFocused = false
    }

    private func finalizeAmountExpression(expression: inout String, amount: inout String) {
        guard AmountExpressionEvaluator.containsExpression(expression) else {
            expression = ""
            return
        }

        switch AmountExpressionEvaluator.evaluate(expression) {
        case .success(let value):
            amount = value.asEditableAmount()
            expression = ""
            amountCalculatorError = nil
        case .failure(let error):
            amountCalculatorError = error.localizedDescription
            amountCalculatorErrorHaptic += 1
        }
    }

    @discardableResult
    private func resolveAmountExpression(expression: inout String, amount: inout String) -> Bool {
        guard AmountExpressionEvaluator.containsExpression(expression) else { return true }

        switch AmountExpressionEvaluator.evaluate(expression) {
        case .success(let value):
            amount = value.asEditableAmount()
            expression = ""
            amountCalculatorError = nil
            return true
        case .failure(let error):
            validationMessage = error.localizedDescription
            showingValidationAlert = true
            amountCalculatorError = error.localizedDescription
            amountCalculatorErrorHaptic += 1
            return false
        }
    }

    private func parseAmount() -> Decimal {
        parseHeroAmount()
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
        if !resolveAmountExpression(expression: &amountExpression, amount: &amountText) {
            recordSaveDiagnostic("parse_amount_failed", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
            return
        }
        let amount = parseAmount()
        guard amount > 0 else {
            recordSaveDiagnostic("parse_amount_failed", accountID: selectedAccount.id, categoryID: selectedCategory?.id)
            validationMessage = "El importe debe ser mayor que cero."
            showingValidationAlert = true
            return
        }

        if receiptCurrencyMismatch && !hasConfirmedReceiptCurrencyMismatch {
            validationMessage = "Revisa o convierte manualmente el importe del ticket antes de guardarlo y confirma la casilla correspondiente."
            showingValidationAlert = true
            return
        }

        if receiptAmountIsAmbiguous && !hasConfirmedReceiptAmount {
            validationMessage = "Revisa el importe sugerido por el ticket y confirma la casilla correspondiente antes de guardarlo."
            showingValidationAlert = true
            return
        }

        recordSaveDiagnostic("parse_amount_after", accountID: selectedAccount.id, categoryID: selectedCategory?.id)

        let personalAmountForStats: Decimal?
        if movementType == .expense && isSharedExpense && canConfigureOwnershipFields {
            if !resolveAmountExpression(expression: &personalAmountExpression, amount: &personalAmountText) {
                return
            }
            let personalAmount = parsePersonalAmount()

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
                      fetchExpenseMovement(id: existingReimbursementForID) != nil {
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
            let normalizedStart = recurringCalendar.startOfDay(for: recurringStartDate)
            let normalizedEnd = recurringHasEndDate ? recurringCalendar.startOfDay(for: recurringEndDate) : nil

            if let normalizedEnd, normalizedEnd < normalizedStart {
                recordSaveDiagnostic("validate_recurring_end_failed", accountID: selectedAccount.id, categoryID: selectedCategory?.id, reimbursementForID: reimbursementForID)
                validationMessage = "La fecha de fin no puede ser anterior al inicio."
                showingValidationAlert = true
                return
            }

            recurringConfiguration = (
                startDate: normalizedStart,
                endDate: normalizedEnd,
                anchorDay: recurringCalendar.component(.day, from: normalizedStart)
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
                do {
                    try unlinkReimbursementsLinkedToExpense(expenseID: movementToEdit.id)
                } catch {
                    modelContext.rollback()
                    validationMessage = "No se pudieron actualizar los reembolsos vinculados: \(error.localizedDescription)"
                    showingValidationAlert = true
                    return
                }
            }

            if let recurring = linkedRecurringRule(for: movementToEdit) {
                if recurring.isActive, recurringEditScope == .thisAndFuture {
                    guard let recurringConfiguration else { return }
                    let boundaryDate = movementToEdit.recurringScheduledAt ?? recurringStartDate
                    let targetRule = RecurringMovementService.ruleForFutureChanges(
                        from: recurring,
                        boundaryDate: boundaryDate,
                        movements: movements,
                        in: modelContext
                    )

                    targetRule.concept = trimmedConcept
                    targetRule.amount = amount
                    targetRule.type = movementType
                    targetRule.frequency = recurringFrequency
                    targetRule.dayOfMonth = recurringFrequency == recurring.frequency
                        ? recurring.dayOfMonth
                        : recurringCalendar.component(.day, from: boundaryDate)
                    targetRule.endDate = recurringConfiguration.endDate
                    targetRule.account = selectedAccount
                    targetRule.category = selectedCategory
                    targetRule.notes = notes
                    targetRule.isActive = true
                    targetRule.updatedAt = Date()
                    movementToEdit.recurringRuleId = targetRule.id
                }

                if movementToEdit.recurringScheduledAt == nil {
                    movementToEdit.recurringScheduledAt = recurringCalendar.startOfDay(for: movementToEdit.occurredAt)
                }
            } else if isRecurring {
                guard let recurringConfiguration else { return }

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
                    movementToEdit.recurringScheduledAt = recurringCalendar.startOfDay(for: movementToEdit.occurredAt)
            } else {
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

        guard rebuildHistoricalBalances() else { return }

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
            modelContext.rollback()
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
            let sourceInvestedAmountBeforeImpact = sourceAccount.effectiveInvestedAmount
            sourceAccount.balance -= amount
            if sourceAccount.isInvestmentAccount {
                sourceAccount.investedAmount = max(0, sourceInvestedAmountBeforeImpact - amount)
            }
            if let destinationAccount {
                destinationAccount.currency = appCurrencyCode
                let destinationInvestedAmountBeforeImpact = destinationAccount.effectiveInvestedAmount
                destinationAccount.balance += amount
                if destinationAccount.isInvestmentAccount {
                    destinationAccount.investedAmount = destinationInvestedAmountBeforeImpact + amount
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
            let sourceInvestedAmountBeforeImpact = sourceAccount.effectiveInvestedAmount
            sourceAccount.balance += movement.amount
            if sourceAccount.isInvestmentAccount {
                sourceAccount.investedAmount = sourceInvestedAmountBeforeImpact + movement.amount
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

        sourceAccount.updatedAt = Date()
    }

    @discardableResult
    private func rebuildHistoricalBalances() -> Bool {
        do {
            _ = try MovementBalanceService.rebuild(in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            CrashReportService.shared.recordDiagnosticEvent(
                "MovementBalanceService.rebuild failed error=\(error.localizedDescription)"
            )
            validationMessage = "No se pudo reconstruir el historial de saldos: \(error.localizedDescription)"
            showingValidationAlert = true
            return false
        }
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
        do {
            return try fetchMovement(id: reimbursementForId)?.account?.isArchived == true
        } catch {
            // Keep the historical movement locked if the directed lookup fails.
            return true
        }
    }

    private func unlinkReimbursementsLinkedToExpense(expenseID: UUID) throws {
        let linkedReimbursements = try fetchReimbursements(for: expenseID)
        for movement in linkedReimbursements {
            movement.reimbursementForId = nil
            movement.updatedAt = Date()
        }
    }

    private func fetchExpenseMovement(id: UUID) -> Movement? {
        do {
            let movement = try fetchMovement(id: id)
            return movement?.type == .expense ? movement : nil
        } catch {
            return nil
        }
    }

    private func fetchMovement(id: UUID) throws -> Movement? {
        var descriptor = FetchDescriptor<Movement>(predicate: #Predicate { movement in
            movement.id == id
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchReimbursements(for expenseID: UUID) throws -> [Movement] {
        let descriptor = FetchDescriptor<Movement>(predicate: #Predicate { movement in
            movement.typeRaw == "income" && movement.reimbursementForId == expenseID
        })
        return try modelContext.fetch(descriptor)
    }

    private func linkedRecurringRule(for movement: Movement) -> RecurringMovement? {
        guard let recurringRuleId = movement.recurringRuleId else { return nil }
        return recurringMovements.first(where: { $0.id == recurringRuleId })
    }
}

enum MovementDraftHeroField: Hashable {
    case concept
    case amount
}

private struct MovementDraftHero: View {
    @Binding var title: String
    @Binding var amountText: String
    @Binding var amountExpression: String
    @Binding var amountErrorMessage: String?
    @Binding var type: MovementType
    var isMovementTypeLocked: Bool = false
    @Binding var selectedAccount: BankAccount?
    @Binding var selectedDestinationAccount: BankAccount?
    @Binding var selectedCategory: MovementCategory?
    let categories: [MovementCategory]
    let hasActiveAccounts: Bool
    let currencyCode: String
    let tint: Color
    var focusedField: FocusState<MovementDraftHeroField?>.Binding
    var onAmountDone: () -> Void
    var onDismissAmountKeyboard: () -> Void
    var onCreateCategory: () -> Void

    @State private var accountLabel = "Sin cuenta"
    @State private var destinationAccountLabel = "Sin destino"
    @State private var categoryLabel = "Sin categoría"
    @State private var categoryIconName = "tag"
    @State private var categoryTint: Color = .secondary
    @State private var isShowingCategoryPicker = false
    @State private var accountBankLabel = ""
    @State private var accountIconName = "creditcard"
    @State private var accountTint: Color = .financeAccent
    @State private var isShowingAccountPicker = false
    @State private var destinationBankLabel = ""
    @State private var destinationIconName = "arrow.down.left.circle"
    @State private var destinationTint: Color = .financeAccent
    @State private var isShowingDestinationAccountPicker = false
    @State private var isShowingTypePicker = false

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
                        .focused(focusedField, equals: .concept)
                }

                Spacer()

                FinanceGlassIconBadge(systemName: type.icon, tint: tint, size: 46)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AmountCalculatorHeroAmountField(
                    displayAmount: $amountText,
                    expression: $amountExpression,
                    errorMessage: $amountErrorMessage,
                    placeholder: "0,00",
                    font: .system(size: 36, weight: .bold, design: .rounded),
                    tint: tint,
                    accessibilityLabel: "Importe",
                    focus: focusedField,
                    onDone: onAmountDone
                )
                .minimumScaleFactor(0.72)

                CurrencySymbolLabel(code: currencyCode, companion: .hero)
            }

            HStack(spacing: 10) {
                accountSelector
                    .frame(maxWidth: .infinity)

                if type == .transfer {
                    destinationAccountSelector
                        .frame(maxWidth: .infinity)
                } else {
                    categorySelector
                        .frame(maxWidth: .infinity)
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
        .onAppear(perform: syncSelectorLabels)
        .onChange(of: selectedAccount?.id) { _, _ in syncSelectorLabels() }
        .onChange(of: selectedDestinationAccount?.id) { _, _ in syncSelectorLabels() }
        .onChange(of: selectedCategory?.id) { _, _ in syncSelectorLabels() }
        .sheet(isPresented: $isShowingCategoryPicker) {
            MovementCategoryPickerSheet(
                selection: $selectedCategory,
                onCreateCategory: onCreateCategory
            )
        }
        .sheet(isPresented: $isShowingAccountPicker) {
            MovementAccountPickerSheet(
                selection: $selectedAccount,
                navigationTitle: type == .transfer ? "Cuenta origen" : "Cuenta"
            )
        }
        .sheet(isPresented: $isShowingDestinationAccountPicker) {
            MovementAccountPickerSheet(
                selection: $selectedDestinationAccount,
                navigationTitle: "Cuenta destino",
                excludingAccountID: selectedAccount?.id
            )
        }
        .sheet(isPresented: $isShowingTypePicker) {
            MovementTypePickerSheet(selection: $type)
        }
    }

    private func syncSelectorLabels() {
        if let selectedAccount {
            accountLabel = selectedAccount.name
            accountBankLabel = selectedAccount.bankDisplayName
            accountIconName = selectedAccount.isInvestmentAccount ? "chart.line.uptrend.xyaxis" : "creditcard"
            accountTint = selectedAccount.accountType.color
        } else {
            accountLabel = "Sin cuenta"
            accountBankLabel = ""
            accountIconName = "creditcard"
            accountTint = .financeAccent
        }

        if let selectedDestinationAccount {
            destinationAccountLabel = selectedDestinationAccount.name
            destinationBankLabel = selectedDestinationAccount.bankDisplayName
            destinationIconName = "arrow.down.left.circle"
            destinationTint = selectedDestinationAccount.accountType.color
        } else {
            destinationAccountLabel = "Sin destino"
            destinationBankLabel = ""
            destinationIconName = "arrow.down.left.circle"
            destinationTint = .financeAccent
        }

        categoryLabel = selectedCategory?.name ?? "Sin categoría"
        categoryIconName = selectedCategory?.iconName ?? "tag"
        categoryTint = selectedCategory?.color ?? .secondary
    }

    @ViewBuilder
    private var typeSelector: some View {
        if isMovementTypeLocked {
            movementTypeChip(
                type: .income,
                showsChevron: false
            )
                .accessibilityLabel("Tipo de movimiento")
                .accessibilityValue(MovementType.income.displayName)
                .accessibilityHint("No editable en un reembolso vinculado")
        } else {
            Button {
                onDismissAmountKeyboard()
                isShowingTypePicker = true
            } label: {
                movementTypeChip(type: type, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tipo de movimiento")
            .accessibilityValue(type.displayName)
            .accessibilityHint("Abre la pantalla de selección de tipo")
        }
    }

    private func movementTypeChip(type: MovementType, showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: type.icon)
                .font(.caption.weight(.semibold))
            Text(type.displayName)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.caption.weight(.bold))
        .textCase(.uppercase)
        .tracking(0.6)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(type.color.opacity(0.16), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(type.color.opacity(0.34), lineWidth: 1)
        )
        .contentShape(Capsule())
    }

    private var accountSelector: some View {
        Button {
            onDismissAmountKeyboard()
            isShowingAccountPicker = true
        } label: {
            MovementAccountPickerPill(
                accountName: accountLabel,
                bankName: accountBankLabel.isEmpty ? "Selecciona una cuenta" : accountBankLabel,
                systemImage: accountIconName,
                tint: accountTint
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasActiveAccounts)
        .accessibilityLabel(type == .transfer ? "Cuenta origen" : "Cuenta")
        .accessibilityValue("\(accountLabel), \(accountBankLabel)")
        .accessibilityHint("Abre el selector de cuenta")
    }

    private var destinationAccountSelector: some View {
        Button {
            onDismissAmountKeyboard()
            isShowingDestinationAccountPicker = true
        } label: {
            MovementAccountPickerPill(
                accountName: destinationAccountLabel,
                bankName: destinationBankLabel.isEmpty ? "Selecciona destino" : destinationBankLabel,
                systemImage: destinationIconName,
                tint: destinationTint
            )
        }
        .buttonStyle(.plain)
        .disabled(!hasActiveAccounts)
        .accessibilityLabel("Cuenta destino")
        .accessibilityValue("\(destinationAccountLabel), \(destinationBankLabel)")
        .accessibilityHint("Abre el selector de cuenta destino")
    }

    private var categorySelector: some View {
        Button {
            onDismissAmountKeyboard()
            isShowingCategoryPicker = true
        } label: {
            MovementCategoryPickerPill(
                title: categoryLabel,
                iconName: categoryIconName,
                tint: categoryTint
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Categoría")
        .accessibilityValue(categoryLabel)
        .accessibilityHint("Abre el selector de categoría")
    }
}

private extension View {
    func movementEditorSheetPresentation(isEditing: Bool) -> some View {
        presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(isEditing)
    }
}

private struct MovementEditorInlineAmountRow: View {
    let label: String
    @Binding var text: String
    @Binding var expression: String
    @Binding var errorMessage: String?
    let currencyCode: String
    let tint: Color
    var isFocused: FocusState<Bool>.Binding
    var onDone: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()

            AmountCalculatorInlineAmountField(
                displayAmount: $text,
                expression: $expression,
                errorMessage: $errorMessage,
                placeholder: label,
                font: .title3.weight(.bold),
                tint: tint,
                focus: isFocused,
                onDone: onDone
            )

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

private struct DismissAmountKeyboardKey: EnvironmentKey {
#if swift(>=6.0)
    static let defaultValue: @MainActor @Sendable () -> Void = {}
#else
    static let defaultValue: () -> Void = {}
#endif
}

private extension EnvironmentValues {
#if swift(>=6.0)
    var dismissAmountKeyboard: @MainActor @Sendable () -> Void {
        get { self[DismissAmountKeyboardKey.self] }
        set { self[DismissAmountKeyboardKey.self] = newValue }
    }
#else
    var dismissAmountKeyboard: () -> Void {
        get { self[DismissAmountKeyboardKey.self] }
        set { self[DismissAmountKeyboardKey.self] = newValue }
    }
#endif
}

private struct MovementEditorDetailSectionModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismissAmountKeyboard) private var dismissAmountKeyboard

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
            .simultaneousGesture(TapGesture().onEnded {
                dismissAmountKeyboard()
            })
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
