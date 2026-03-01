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

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""
    @State private var didLoadExistingData = false

    private let movementToEdit: Movement?

    private var isEditing: Bool {
        movementToEdit != nil
    }

    init(movementToEdit: Movement? = nil) {
        self.movementToEdit = movementToEdit
    }

    private var filteredCategories: [MovementCategory] {
        if categorySearchText.isEmpty {
            return categories
        }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(categorySearchText) }
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

    private var canCreateNewCategory: Bool {
        let trimmed = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return !categories.contains { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    if accounts.isEmpty {
                        Text("No hay cuentas disponibles. Crea una cuenta antes de registrar movimientos.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Cuenta origen", selection: $selectedAccount) {
                            ForEach(groupedAccountsByBank) { bankGroup in
                                Section(bankGroup.bankName) {
                                    ForEach(bankGroup.accounts, id: \.id) { account in
                                        Text(account.name)
                                            .tag(Optional(account))
                                    }
                                }
                            }
                        }

                        if movementType == .transfer {
                            Picker("Cuenta destino", selection: $selectedDestinationAccount) {
                                Text("Selecciona una cuenta")
                                    .tag(nil as BankAccount?)

                                ForEach(groupedAccountsByBank) { bankGroup in
                                    Section(bankGroup.bankName) {
                                        ForEach(bankGroup.accounts, id: \.id) { account in
                                            Text(account.name)
                                                .tag(Optional(account))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Tipo") {
                    Picker("Tipo", selection: $movementType) {
                        ForEach(MovementType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Detalle") {
                    TextField("Concepto", text: $concept)
                        .textInputAutocapitalization(.sentences)

                    HStack {
                        TextField("0,00", text: $amountText)
                            .keyboardType(.decimalPad)

                        Text(appCurrencyCode)
                            .foregroundStyle(.secondary)
                    }
                }

                if movementType != .transfer {
                    Section("Categoría") {
                    if let category = selectedCategory {
                        HStack {
                            CategoryChipView(
                                name: category.name,
                                iconName: category.iconName,
                                color: category.color
                            )
                            Spacer()
                            Button("Cambiar") {
                                selectedCategory = nil
                                categorySearchText = ""
                            }
                            .font(.caption)
                        }
                    } else {
                        TextField("Buscar o crear categoría...", text: $categorySearchText)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()

                        ForEach(filteredCategories, id: \.id) { category in
                            Button {
                                selectedCategory = category
                                categorySearchText = ""
                            } label: {
                                CategoryChipView(
                                    name: category.name,
                                    iconName: category.iconName,
                                    color: category.color
                                )
                            }
                        }

                        if canCreateNewCategory {
                            Button {
                                newCategoryName = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
                                isCreatingNewCategory = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Crear \"\(categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                }

                if !isRecurring || isEditing {
                    Section("Fecha") {
                        DatePicker("Fecha del movimiento", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if movementType != .transfer {
                    Section("Recurrencia") {
                        Toggle("Marcar como recurrente", isOn: $isRecurring)

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

                Section("Notas (opcional)") {
                    TextField("Añade una nota...", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(isEditing ? "Editar movimiento" : "Nuevo movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Actualizar" : "Guardar") {
                        saveMovement()
                    }
                    .fontWeight(.semibold)
                    .disabled(accounts.isEmpty)
                }
            }
            .onAppear(perform: setupDefaults)
            .onChange(of: movementType) { _, newValue in
                if newValue == .transfer {
                    selectedCategory = nil
                    categorySearchText = ""
                    isRecurring = false
                    ensureTransferAccountsAreDifferent()
                } else if selectedCategory == nil {
                    selectedCategory = categories.first
                }
            }
            .onChange(of: selectedAccount?.id) { _, _ in
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

            didLoadExistingData = true
            return
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

    private func parseAmount() -> Decimal {
        let cleaned = amountText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned) ?? 0
    }

    private func formatAmountForEditing(_ amount: Decimal) -> String {
        NSDecimalNumber(decimal: amount).stringValue.replacingOccurrences(of: ".", with: ",")
    }

    private func saveMovement() {
        guard let selectedAccount else {
            validationMessage = "Selecciona una cuenta."
            showingValidationAlert = true
            return
        }

        let trimmedConcept = concept.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedConcept.isEmpty else {
            validationMessage = "El concepto es obligatorio."
            showingValidationAlert = true
            return
        }

        if movementType != .transfer {
            guard selectedCategory != nil else {
                validationMessage = "Selecciona o crea una categoría."
                showingValidationAlert = true
                return
            }
        }

        let amount = parseAmount()
        guard amount > 0 else {
            validationMessage = "El importe debe ser mayor que cero."
            showingValidationAlert = true
            return
        }

        if movementType == .transfer {
            guard let selectedDestinationAccount else {
                validationMessage = "Selecciona una cuenta destino para la transferencia."
                showingValidationAlert = true
                return
            }

            guard selectedDestinationAccount.id != selectedAccount.id else {
                validationMessage = "La cuenta origen y destino no pueden ser la misma."
                showingValidationAlert = true
                return
            }
        }

        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let recurringConfiguration: (startDate: Date, endDate: Date?, anchorDay: Int)?

        if isRecurring && movementType != .transfer {
            let normalizedStart = Calendar.current.startOfDay(for: recurringStartDate)
            let normalizedEnd = recurringHasEndDate ? Calendar.current.startOfDay(for: recurringEndDate) : nil

            if let normalizedEnd, normalizedEnd < normalizedStart {
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

        if isRecurring && !isEditing {
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

            modelContext.insert(recurringMovement)
            dismiss()
            return
        }

        if let movementToEdit {
            revertMovementImpact(movementToEdit)

            let resultingBalance = applyMovementImpact(
                type: movementType,
                amount: amount,
                sourceAccount: selectedAccount,
                destinationAccount: movementType == .transfer ? selectedDestinationAccount : nil
            )

            movementToEdit.concept = trimmedConcept
            movementToEdit.amount = amount
            movementToEdit.type = movementType
            movementToEdit.occurredAt = occurredAt
            movementToEdit.account = selectedAccount
            movementToEdit.destinationAccount = movementType == .transfer ? selectedDestinationAccount : nil
            movementToEdit.category = movementType == .transfer ? nil : selectedCategory
            movementToEdit.notes = notes
            movementToEdit.resultingBalance = resultingBalance

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
        } else {
            let resultingBalance = applyMovementImpact(
                type: movementType,
                amount: amount,
                sourceAccount: selectedAccount,
                destinationAccount: movementType == .transfer ? selectedDestinationAccount : nil
            )

            let movement = Movement(
                concept: trimmedConcept,
                amount: amount,
                type: movementType,
                occurredAt: occurredAt,
                account: selectedAccount,
                destinationAccount: movementType == .transfer ? selectedDestinationAccount : nil,
                category: movementType == .transfer ? nil : selectedCategory,
                notes: notes,
                resultingBalance: resultingBalance
            )

            modelContext.insert(movement)
        }

        dismiss()
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
            if let destinationAccount {
                destinationAccount.currency = appCurrencyCode
                destinationAccount.balance += amount
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
            if let destination = movement.destinationAccount {
                destination.balance -= movement.amount
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

    private func linkedRecurringRule(for movement: Movement) -> RecurringMovement? {
        guard let recurringRuleId = movement.recurringRuleId else { return nil }
        return recurringMovements.first(where: { $0.id == recurringRuleId })
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
                Section("Nombre de la categoría") {
                    TextField("Nombre", text: $categoryName)
                }

                Section("Icono") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryIcon.allCases) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon.systemName)
                                    .font(.title3)
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

                Section("Color") {
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
            }
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
