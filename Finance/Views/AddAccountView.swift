//
//  AddAccountView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Formulario para crear una nueva cuenta bancaria o editar una existente.
/// El banco se selecciona de un desplegable de bancos existentes,
/// o se puede crear uno nuevo escribiendo el nombre directamente.
struct AddAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @Query(sort: \Bank.name) private var banks: [Bank]

    /// Si se pasa una cuenta existente, se edita. Si es nil, se crea una nueva.
    var existingAccount: BankAccount?

    @State private var name: String = ""
    @State private var selectedBank: Bank?
    @State private var bankSearchText: String = ""
    @State private var isCreatingNewBank = false
    @State private var newBankName: String = ""
    @State private var newBankIcon: BankIcon = .buildingColumns
    @State private var newBankColor: BankColor = .blue
    @State private var accountType: AccountType = .checking
    @State private var balanceText: String = ""
    @State private var investedAmountText: String = ""
    @State private var marketValueText: String = ""
    @State private var notes: String = ""

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    private var isEditing: Bool { existingAccount != nil }

    private var navigationTitle: String {
        isEditing ? "Editar cuenta" : "Nueva cuenta"
    }

    /// Bancos filtrados por el texto de búsqueda.
    private var filteredBanks: [Bank] {
        if bankSearchText.isEmpty {
            return banks
        }
        return banks.filter { $0.name.localizedCaseInsensitiveContains(bankSearchText) }
    }

    /// Si el texto no coincide exactamente con ningún banco existente, se ofrece crear uno nuevo.
    private var canCreateNewBank: Bool {
        let trimmed = bankSearchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return !banks.contains { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Banco
                Section("Banco") {
                    if let bank = selectedBank {
                        // Banco seleccionado - mostrar con opción de cambiar
                        HStack(spacing: 10) {
                            Image(systemName: bank.iconName)
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(bank.color)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(bank.name)
                                .fontWeight(.medium)
                            Spacer()
                            Button("Cambiar") {
                                selectedBank = nil
                                bankSearchText = ""
                            }
                            .font(.caption)
                        }
                    } else {
                        // Campo de búsqueda / selección de banco
                        TextField("Buscar o crear banco...", text: $bankSearchText)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()

                        // Lista de bancos existentes filtrados
                        ForEach(filteredBanks) { bank in
                            Button {
                                selectedBank = bank
                                bankSearchText = ""
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: bank.iconName)
                                        .font(.body)
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(bank.color)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    Text(bank.name)
                                        .foregroundStyle(.primary)
                                }
                            }
                        }

                        // Opción de crear banco nuevo
                        if canCreateNewBank {
                            Button {
                                newBankName = bankSearchText.trimmingCharacters(in: .whitespaces)
                                isCreatingNewBank = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Crear \"\(bankSearchText.trimmingCharacters(in: .whitespaces))\"")
                                        .foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }

                // Datos de la cuenta
                Section("Información de la cuenta") {
                    TextField("Nombre de la cuenta", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Tipo de cuenta", selection: $accountType) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                // Saldo (solo para cuentas no inversión)
                if accountType != .investment {
                    Section("Saldo") {
                        HStack {
                            TextField("0,00", text: $balanceText)
                                .keyboardType(.decimalPad)
                            Text(appCurrencyCode)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if accountType == .investment {
                    Section("Inversión") {
                        HStack {
                            TextField("Cantidad invertida", text: $investedAmountText)
                                .keyboardType(.decimalPad)
                            Text(appCurrencyCode)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            TextField("Valor de mercado", text: $marketValueText)
                                .keyboardType(.decimalPad)
                            Text(appCurrencyCode)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Notas opcionales
                Section("Notas (opcional)") {
                    TextField("Añade notas sobre esta cuenta...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Guardar" : "Añadir") {
                        saveAccount()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadExistingData()
            }
            .onChange(of: accountType) { _, newType in
                if newType == .investment {
                    if investedAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        investedAmountText = balanceText
                    }
                    if marketValueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        marketValueText = balanceText
                    }
                }
            }
            .alert("Campos requeridos", isPresented: $showingValidationAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
            .sheet(isPresented: $isCreatingNewBank) {
                CreateBankSheet(
                    bankName: $newBankName,
                    selectedIcon: $newBankIcon,
                    selectedColor: $newBankColor
                ) { createdBank in
                    selectedBank = createdBank
                    bankSearchText = ""
                }
            }
        }
    }

    // MARK: - Lógica

    /// Carga los datos de la cuenta existente en los campos del formulario.
    private func loadExistingData() {
        guard let account = existingAccount else { return }
        name = account.name
        selectedBank = account.bank
        accountType = account.accountType
        balanceText = formatBalanceForEditing(account.balance)
        investedAmountText = formatBalanceForEditing(account.effectiveInvestedAmount)
        marketValueText = formatBalanceForEditing(account.effectiveMarketValue)
        notes = account.notes
    }

    private func parseDecimal(_ text: String) -> Decimal {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned) ?? 0
    }

    /// Parsea el texto del saldo a Decimal, soportando tanto coma como punto decimal.
    private func parseBalance() -> Decimal {
        let cleaned = balanceText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned) ?? 0
    }

    /// Formatea un Decimal para mostrar en el campo de texto.
    private func formatBalanceForEditing(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// Valida y guarda la cuenta (nueva o editada).
    private func saveAccount() {
        // Validación
        guard selectedBank != nil else {
            validationMessage = "Selecciona o crea un banco."
            showingValidationAlert = true
            return
        }

        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "El nombre de la cuenta es obligatorio."
            showingValidationAlert = true
            return
        }

        let balance = parseBalance()
        let investedAmount = parseDecimal(investedAmountText)
        let marketValue = parseDecimal(marketValueText)

        if let account = existingAccount {
            // Editar cuenta existente
            account.name = name.trimmingCharacters(in: .whitespaces)
            account.bank = selectedBank
            account.accountType = accountType
            if accountType == .investment {
                account.investedAmount = investedAmount
                account.marketValue = marketValue
                account.marketValueUpdatedAt = Date()
                account.balance = marketValue
                upsertTodayInvestmentSnapshot(
                    for: account,
                    investedAmount: investedAmount,
                    marketValue: marketValue
                )
            } else {
                account.investedAmount = nil
                account.marketValue = nil
                account.marketValueUpdatedAt = nil
                account.balance = balance
            }
            account.currency = appCurrencyCode
            account.notes = notes.trimmingCharacters(in: .whitespaces)
            account.updatedAt = Date()
        } else {
            // Crear nueva cuenta
            let newAccount = BankAccount(
                name: name.trimmingCharacters(in: .whitespaces),
                bank: selectedBank,
                accountType: accountType,
                balance: accountType == .investment ? marketValue : balance,
                currency: appCurrencyCode,
                notes: notes.trimmingCharacters(in: .whitespaces),
                investedAmount: accountType == .investment ? investedAmount : nil,
                marketValue: accountType == .investment ? marketValue : nil,
                marketValueUpdatedAt: accountType == .investment ? Date() : nil
            )
            modelContext.insert(newAccount)

            if accountType == .investment {
                upsertTodayInvestmentSnapshot(
                    for: newAccount,
                    investedAmount: investedAmount,
                    marketValue: marketValue
                )
            }
        }

        dismiss()
    }

    private func upsertTodayInvestmentSnapshot(
        for account: BankAccount,
        investedAmount: Decimal,
        marketValue: Decimal
    ) {
        let today = Calendar.current.startOfDay(for: Date())

        if let existing = (account.investmentSnapshots ?? []).first(where: {
            Calendar.current.isDate($0.snapshotDate, inSameDayAs: today)
        }) {
            existing.investedAmount = investedAmount
            existing.marketValue = marketValue
            existing.updatedAt = Date()
            return
        }

        let snapshot = InvestmentSnapshot(
            snapshotDate: today,
            investedAmount: investedAmount,
            marketValue: marketValue,
            account: account
        )
        modelContext.insert(snapshot)
    }
}

// MARK: - Sheet para crear un nuevo banco

/// Formulario modal para crear un banco nuevo con nombre, icono y color.
struct CreateBankSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var bankName: String
    @Binding var selectedIcon: BankIcon
    @Binding var selectedColor: BankColor

    /// Callback que devuelve el banco recién creado.
    var onCreated: (Bank) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre del banco") {
                    TextField("Nombre", text: $bankName)
                        .textInputAutocapitalization(.words)
                }

                Section("Icono") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(BankIcon.allCases) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon.systemName)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(selectedIcon == icon ? .white : .primary)
                                    .background(selectedIcon == icon ? selectedColor.color : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
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
                        ForEach(BankColor.allCases) { bankColor in
                            Button {
                                selectedColor = bankColor
                            } label: {
                                Circle()
                                    .fill(bankColor.color)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: selectedColor == bankColor ? 3 : 0)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(bankColor.color, lineWidth: selectedColor == bankColor ? 1 : 0)
                                            .padding(-2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Vista previa
                Section("Vista previa") {
                    HStack(spacing: 10) {
                        Image(systemName: selectedIcon.systemName)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(selectedColor.color)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(bankName.isEmpty ? "Nombre del banco" : bankName)
                            .fontWeight(.medium)
                    }
                }
            }
            .navigationTitle("Nuevo banco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        createBank()
                    }
                    .fontWeight(.semibold)
                    .disabled(bankName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func createBank() {
        let trimmedName = bankName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        let bank = Bank(
            name: trimmedName,
            icon: selectedIcon,
            bankColor: selectedColor
        )
        modelContext.insert(bank)
        onCreated(bank)
        dismiss()
    }
}
