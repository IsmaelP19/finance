//
//  AddAccountView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Formulario para crear una nueva cuenta bancaria o editar una existente.
struct AddAccountView: View {
    private static let bankLookbackDays = 30

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query private var recentMovements: [Movement]

    /// Si se pasa una cuenta existente, se edita. Si es nil, se crea una nueva.
    var existingAccount: BankAccount?

    @State private var name: String = ""
    @State private var selectedBank: Bank?
    @State private var newBankName: String = ""
    @State private var newBankIcon: BankIcon = .buildingColumns
    @State private var newBankColor: BankColor = .blue
    @State private var accountType: AccountType = .checking
    @State private var balanceText: String = ""
    @State private var investedAmountText: String = ""
    @State private var marketValueText: String = ""
    @State private var notes: String = ""
    @State private var activeSheet: AccountFormSheet?
    @State private var pendingCreateBankName: String?

    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    init(existingAccount: BankAccount? = nil) {
        self.existingAccount = existingAccount

        let lookbackStart = Calendar.current.date(
            byAdding: .day,
            value: -Self.bankLookbackDays,
            to: Date()
        ) ?? .distantPast

        _recentMovements = Query(filter: #Predicate<Movement> { movement in
            movement.occurredAt >= lookbackStart
        })
    }

    private var isEditing: Bool { existingAccount != nil }

    private var navigationTitle: String {
        isEditing ? "Editar cuenta" : "Nueva cuenta"
    }

    private var selectedAccent: Color {
        selectedBank?.color ?? accountType.color
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AccountDraftHero(
                        name: $name,
                        placeholder: navigationTitle,
                        selectedBank: selectedBank,
                        type: accountType,
                        accent: selectedAccent,
                        appCurrencyCode: appCurrencyCode,
                        balanceText: $balanceText,
                        investedAmountText: $investedAmountText,
                        marketValueText: $marketValueText,
                        onSelectBank: { activeSheet = .bankPicker },
                        onSelectType: { activeSheet = .typePicker }
                    )
                }
                .financeGlassClearListRow()

                // Notas opcionales
                Section {
                    AccountEditableNotesCard(notes: $notes)
                }
                .financeGlassClearListRow()
            }
            .financeGlassListContainer()
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
            .sheet(item: $activeSheet, onDismiss: presentPendingCreateBankIfNeeded) { sheet in
                switch sheet {
                case .bankPicker:
                    AccountBankPickerSheet(
                        banks: banks,
                        recentMovements: recentMovements,
                        selection: $selectedBank,
                        lookbackDays: Self.bankLookbackDays
                    ) { suggestedName in
                        pendingCreateBankName = suggestedName
                    }
                case .typePicker:
                    AccountTypePickerSheet(selection: $accountType)
                case .createBank:
                    CreateBankSheet(
                        bankName: $newBankName,
                        selectedIcon: $newBankIcon,
                        selectedColor: $newBankColor
                    ) { createdBank in
                        selectedBank = createdBank
                    }
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
        balanceText = account.balance.asEditableAmount()
        investedAmountText = account.effectiveInvestedAmount.asEditableAmount()
        marketValueText = account.effectiveMarketValue.asEditableAmount()
        notes = account.notes
    }

    private func parseDecimal(_ text: String) -> Decimal {
        EditableAmount.parse(text) ?? 0
    }

    /// Parsea el texto del saldo a Decimal, soportando separador de miles español.
    private func parseBalance() -> Decimal {
        EditableAmount.parse(balanceText) ?? 0
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

    private func presentPendingCreateBankIfNeeded() {
        guard let pendingCreateBankName else { return }
        self.pendingCreateBankName = nil
        newBankName = pendingCreateBankName
        activeSheet = .createBank
    }
}

private enum AccountFormSheet: String, Identifiable {
    case bankPicker
    case typePicker
    case createBank

    var id: String { rawValue }
}

private struct AccountDraftHero: View {
    @Binding var name: String
    let placeholder: String
    let selectedBank: Bank?
    let type: AccountType
    let accent: Color
    let appCurrencyCode: String
    @Binding var balanceText: String
    @Binding var investedAmountText: String
    @Binding var marketValueText: String
    let onSelectBank: () -> Void
    let onSelectType: () -> Void

    private var iconName: String { selectedBank?.iconName ?? type.icon }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Button(action: onSelectType) {
                        HStack(spacing: 6) {
                            Text(type.displayName)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(type.color.opacity(0.16), in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(type.color.opacity(0.34), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cambiar tipo de cuenta")
                    .accessibilityValue(type.displayName)
                    .accessibilityHint("Abre la pantalla de selección de tipo")

                    TextField(placeholder, text: $name, axis: .vertical)
                        .textInputAutocapitalization(.words)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1...2)
                        .tint(accent)
                        .accessibilityLabel("Nombre de la cuenta")

                    Button(action: onSelectBank) {
                        HStack(spacing: 5) {
                            Text(selectedBank?.name ?? "Elegir banco")
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selectedBank == nil ? "Elegir banco" : "Cambiar banco")
                    .accessibilityValue(selectedBank?.name ?? "Sin banco")
                    .accessibilityHint("Abre la pantalla de selección de banco")
                }
                Spacer(minLength: 0)
            }

            if type == .investment {
                VStack(spacing: 12) {
                    HeroAmountField(
                        title: "Cantidad invertida",
                        placeholder: "0,00",
                        systemImage: "tray.and.arrow.down.fill",
                        tint: .purple,
                        text: $investedAmountText,
                        currencyCode: appCurrencyCode
                    )

                    HeroAmountField(
                        title: "Valor de mercado",
                        placeholder: "0,00",
                        systemImage: "chart.line.uptrend.xyaxis",
                        tint: .blue,
                        text: $marketValueText,
                        currencyCode: appCurrencyCode
                    )
                }
            } else {
                HeroAmountField(
                    title: "Saldo inicial",
                    placeholder: "0,00",
                    systemImage: "creditcard",
                    tint: type.color,
                    text: $balanceText,
                    currencyCode: appCurrencyCode
                )
            }
        }
        .financeGlassColorCard(
            gradient: LinearGradient(
                colors: [accent.opacity(0.18), type.color.opacity(0.08), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            cornerRadius: FinanceGlassTokens.Radius.hero
        )
    }
}

private struct HeroSelectorButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(tint, in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HeroAmountField: View {
    let title: String
    let placeholder: String
    let systemImage: String
    let tint: Color
    @Binding var text: String
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField(placeholder, text: $text)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                        .tint(tint)
                        .accessibilityLabel(title)
                    CurrencySymbolLabel(code: currencyCode, companion: .title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct AccountEditableNotesCard: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("Notas")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Text("Opcional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Añade notas sobre esta cuenta...", text: $notes, axis: .vertical)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2...6)
                .textFieldStyle(.plain)
                .accessibilityLabel("Notas")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct AccountBankPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let banks: [Bank]
    let recentMovements: [Movement]
    @Binding var selection: Bank?
    let lookbackDays: Int
    let onCreateBank: (String) -> Void

    @State private var searchText = ""
    @State private var draftSelectionID: UUID?

    private var usageCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for movement in recentMovements {
            if let bankID = movement.account?.bank?.id {
                counts[bankID, default: 0] += 1
            }
            if let bankID = movement.destinationAccount?.bank?.id {
                counts[bankID, default: 0] += 1
            }
        }
        return counts
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreateBank: Bool {
        guard !trimmedSearch.isEmpty else { return false }
        return !banks.contains { $0.name.localizedCaseInsensitiveCompare(trimmedSearch) == .orderedSame }
    }

    private var filteredBanks: [Bank] {
        let source = sortedBanks
        guard !trimmedSearch.isEmpty else { return source }
        return source.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private var sortedBanks: [Bank] {
        let counts = usageCounts
        return banks.sorted { lhs, rhs in
            let leftCount = counts[lhs.id, default: 0]
            let rightCount = counts[rhs.id, default: 0]
            if leftCount != rightCount {
                return leftCount > rightCount
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.large) {
                    FinanceGlassSectionHeader(
                        title: "Elige banco",
                        systemImage: "building.columns.fill",
                        subtitle: lookbackDays == 30 ? "Usados en el último mes primero" : "Usados recientemente primero"
                    )

                    searchField

                    if canCreateBank {
                        createBankButton
                    }

                    VStack(spacing: 0) {
                        ForEach(filteredBanks) { bank in
                            Button {
                                draftSelectionID = bank.id
                            } label: {
                                BankPickerRow(
                                    bank: bank,
                                    usageCount: usageCounts[bank.id, default: 0],
                                    isSelected: draftSelectionID == bank.id
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(bank.name)
                            .accessibilityValue(draftSelectionID == bank.id ? "Seleccionado" : "No seleccionado")
                            .accessibilityHint("Selecciona este banco para la cuenta")
                            .accessibilityAddTraits(draftSelectionID == bank.id ? .isSelected : [])

                            if bank.id != filteredBanks.last?.id {
                                Divider()
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
                }
                .padding(.horizontal, FinanceGlassTokens.Spacing.large)
                .padding(.top, FinanceGlassTokens.Spacing.small)
                .padding(.bottom, FinanceGlassTokens.Spacing.xLarge)
            }
            .financeGlassPageBackground()
            .navigationTitle("Banco")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Cerrar sin guardar")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyDraftSelectionAndDismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(draftSelectionID == nil)
                    .accessibilityLabel("Confirmar banco")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            draftSelectionID = selection?.id
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar banco", text: $searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityLabel("Buscar banco")
        }
        .padding(14)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var createBankButton: some View {
        Button {
            let suggestedName = trimmedSearch
            onCreateBank(suggestedName)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.financeAccent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crear \"\(trimmedSearch)\"")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Añadir nuevo banco")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, FinanceGlassTokens.Spacing.medium)
            .padding(.vertical, FinanceGlassTokens.Spacing.small)
            .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Crear banco \(trimmedSearch)")
        .accessibilityHint("Abre el formulario para crear un banco nuevo")
    }

    private func applyDraftSelectionAndDismiss() {
        guard let draftSelectionID,
              let bank = banks.first(where: { $0.id == draftSelectionID }) else { return }
        selection = bank
        dismiss()
    }
}

private struct BankPickerRow: View {
    let bank: Bank
    let usageCount: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bank.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(bank.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(bank.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if usageCount > 0 {
                    Text("Usado recientemente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.financeAccent)
            }
        }
        .padding(.horizontal, FinanceGlassTokens.Spacing.medium)
        .padding(.vertical, FinanceGlassTokens.Spacing.small)
        .contentShape(Rectangle())
    }
}

private struct AccountTypePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: AccountType
    @State private var draftSelection: AccountType

    init(selection: Binding<AccountType>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.large) {
                    FinanceGlassSectionHeader(
                        title: "Tipo de cuenta",
                        systemImage: "square.grid.2x2.fill",
                        subtitle: "Elige el producto financiero"
                    )

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(AccountType.allCases) { type in
                            Button {
                                draftSelection = type
                            } label: {
                                AccountTypeChoice(type: type, isSelected: draftSelection == type)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(type.displayName)
                            .accessibilityValue(draftSelection == type ? "Seleccionado" : "No seleccionado")
                            .accessibilityHint("Selecciona este tipo de cuenta")
                            .accessibilityAddTraits(draftSelection == type ? .isSelected : [])
                        }
                    }
                    .padding(FinanceGlassTokens.Spacing.medium)
                    .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
                }
                .padding(.horizontal, FinanceGlassTokens.Spacing.large)
                .padding(.top, FinanceGlassTokens.Spacing.small)
                .padding(.bottom, FinanceGlassTokens.Spacing.xLarge)
            }
            .financeGlassPageBackground()
            .navigationTitle("Tipo")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Cerrar sin guardar")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        selection = draftSelection
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel("Confirmar tipo de cuenta")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct AccountTypeChoice: View {
    let type: AccountType
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(type.color, in: Circle())
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.financeAccent : Color.secondary.opacity(0.35))
            }

            Text(type.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(isSelected ? type.color.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? type.color.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
        )
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
                Section {
                    TextField("Nombre", text: $bankName)
                        .textInputAutocapitalization(.words)
                } header: {
                    FinanceGlassSectionHeader(title: "Nombre", systemImage: "textformat")
                }
                .financeGlassFormSection()

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(BankIcon.allCases) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                Image(systemName: icon.systemName)
                                    .font(.system(size: 17, weight: .semibold))
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
                } header: {
                    FinanceGlassSectionHeader(title: "Icono", systemImage: "square.grid.3x3.fill")
                }
                .financeGlassFormSection()

                Section {
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
                } header: {
                    FinanceGlassSectionHeader(title: "Color", systemImage: "paintpalette.fill")
                }
                .financeGlassFormSection()

                // Vista previa
                Section {
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
                } header: {
                    FinanceGlassSectionHeader(title: "Vista previa", systemImage: "eye.fill")
                }
                .financeGlassFormSection()
            }
            .financeGlassListContainer()
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
