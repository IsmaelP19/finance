//
//  AddMovementView.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import SwiftData

/// Formulario para crear movimientos (gasto o ingreso).
struct AddMovementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]

    @State private var selectedAccount: BankAccount?
    @State private var movementType: MovementType = .expense
    @State private var amountText: String = ""
    @State private var concept: String = ""
    @State private var selectedCategory: MovementCategory?
    @State private var categorySearchText: String = ""
    @State private var isCreatingNewCategory = false
    @State private var newCategoryName: String = ""
    @State private var occurredAt: Date = Date()
    @State private var notes: String = ""

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
                        Picker("Cuenta", selection: $selectedAccount) {
                            ForEach(accounts, id: \.id) { account in
                                Text("\(account.name) · \(account.bankDisplayName)")
                                    .tag(Optional(account))
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

                Section("Fecha") {
                    DatePicker("Fecha del movimiento", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
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
            movementType = movementToEdit.type
            amountText = formatAmountForEditing(movementToEdit.amount)
            concept = movementToEdit.concept
            selectedCategory = movementToEdit.category
            occurredAt = movementToEdit.occurredAt
            notes = movementToEdit.notes
            didLoadExistingData = true
            return
        }

        if selectedAccount == nil {
            selectedAccount = accounts.first
        }
        if selectedCategory == nil {
            selectedCategory = categories.first
        }
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

        guard let selectedCategory else {
            validationMessage = "Selecciona o crea una categoría."
            showingValidationAlert = true
            return
        }

        let amount = parseAmount()
        guard amount > 0 else {
            validationMessage = "El importe debe ser mayor que cero."
            showingValidationAlert = true
            return
        }

        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSignedAmount = amount * movementType.signMultiplier

        if let movementToEdit {
            if let oldAccount = movementToEdit.account {
                oldAccount.balance -= movementToEdit.signedAmount
                oldAccount.updatedAt = Date()
            }

            let resultingBalance = selectedAccount.balance + newSignedAmount

            selectedAccount.currency = appCurrencyCode
            selectedAccount.balance = resultingBalance
            selectedAccount.updatedAt = Date()

            movementToEdit.concept = trimmedConcept
            movementToEdit.amount = amount
            movementToEdit.type = movementType
            movementToEdit.occurredAt = occurredAt
            movementToEdit.account = selectedAccount
            movementToEdit.category = selectedCategory
            movementToEdit.notes = notes
            movementToEdit.resultingBalance = resultingBalance
            movementToEdit.updatedAt = Date()
        } else {
            let resultingBalance = selectedAccount.balance + newSignedAmount
            let movement = Movement(
                concept: trimmedConcept,
                amount: amount,
                type: movementType,
                occurredAt: occurredAt,
                account: selectedAccount,
                category: selectedCategory,
                notes: notes,
                resultingBalance: resultingBalance
            )

            modelContext.insert(movement)

            selectedAccount.currency = appCurrencyCode
            selectedAccount.balance = resultingBalance
            selectedAccount.updatedAt = Date()
        }

        dismiss()
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
