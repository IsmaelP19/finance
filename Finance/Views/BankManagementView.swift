//
//  BankManagementView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

private enum BankManagementRoute: Hashable {
    case bank(UUID)
}

/// Pantalla para gestionar bancos guardados: crear, editar y eliminar.
struct BankManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Query(sort: \Bank.name) private var banks: [Bank]

    @State private var editingBank: Bank?
    @State private var showingCreateBank = false
    @State private var navigationPath: [BankManagementRoute] = []
    @State private var hasShownSwipeHint = false
    @State private var hintedBankID: UUID?
    @State private var swipeHintOffset: CGFloat = 0

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if banks.isEmpty {
                    FinanceCenteredEmptyState(
                        "Sin bancos",
                        systemImage: "building.columns",
                        description: Text("Pulsa + para crear tu primer banco")
                    )
                } else {
                    List {
                        HStack(alignment: .center, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gestionar bancos")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text("Toca un banco para ver sus cuentas. Deslízalo a la derecha para editarlo o a la izquierda para eliminarlo.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Text("\(banks.count)")
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                                .frame(minWidth: 48, minHeight: 48)
                                .background(.primary.opacity(0.08), in: Circle())
                                .accessibilityLabel("\(banks.count) \(banks.count == 1 ? "banco" : "bancos")")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
                        .financeGlassClearListRow(insets: EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))

                        FinanceGlassSectionHeader(title: "Tus bancos", systemImage: "building.2")
                            .financeGlassClearListRow(insets: EdgeInsets(top: 0, leading: 20, bottom: 10, trailing: 20))

                        ForEach(banks, id: \.id) { bank in
                            bankRow(bank)
                        }
                    }
                    .financeGlassListContainer()
                    .task {
                        await showSwipeHintIfNeeded()
                    }
                }
            }
            .navigationTitle("Bancos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateBank = true
                    } label: {
                        Image(systemName: "plus")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Crear banco")
                }
            }
            .sheet(item: $editingBank) { (bank: Bank) in
                BankEditorSheet(bank: bank)
            }
            .sheet(isPresented: $showingCreateBank) {
                BankEditorSheet()
            }
            .navigationDestination(for: BankManagementRoute.self) { route in
                switch route {
                case .bank(let bankID):
                    if let bank = banks.first(where: { $0.id == bankID }) {
                        BankDetailView(bank: bank)
                    } else {
                        FinanceCenteredEmptyState(
                            "Banco no disponible",
                            systemImage: "building.columns",
                            description: Text("Este banco ya no está disponible")
                        )
                    }
                }
            }
        }
    }

    private func bankRow(_ bank: Bank) -> some View {
        Button {
            navigationPath.append(.bank(bank.id))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: bank.iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(bank.color)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(bank.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(accountCountText(for: bank))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .background { bankRowBackground(bank) }
            .overlay(alignment: .bottom) {
                if bank.id != banks.last?.id {
                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(height: 1)
                        .padding(.leading, 72)
                        .padding(.trailing, 16)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ver cuentas de \(bank.name), \(accountCountText(for: bank))")
        .accessibilityHint("Acciones disponibles: Editar y Eliminar.")
        .offset(x: bank.id == hintedBankID ? swipeHintOffset : 0)
        .financeGlassClearListRow(insets: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editingBank = bank
            } label: {
                Label("Editar", systemImage: "pencil")
            }
            .tint(.financeAccent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteBank(bank)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func bankRowBackground(_ bank: Bank) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: bank.id == banks.first?.id ? FinanceGlassTokens.Radius.card : 0,
            bottomLeadingRadius: bank.id == banks.last?.id ? FinanceGlassTokens.Radius.card : 0,
            bottomTrailingRadius: bank.id == banks.last?.id ? FinanceGlassTokens.Radius.card : 0,
            topTrailingRadius: bank.id == banks.first?.id ? FinanceGlassTokens.Radius.card : 0,
            style: .continuous
        )
        .fill(.thinMaterial)
    }

    @MainActor
    private func showSwipeHintIfNeeded() async {
        guard !hasShownSwipeHint, !accessibilityReduceMotion, let firstBank = banks.first else { return }
        hasShownSwipeHint = true
        hintedBankID = firstBank.id

        do {
            try await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = 22 }
            try await Task.sleep(for: .milliseconds(560))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = 0 }
            try await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = -22 }
            try await Task.sleep(for: .milliseconds(560))
            withAnimation(.easeInOut(duration: 0.42)) { swipeHintOffset = 0 }
        } catch {
            swipeHintOffset = 0
        }
    }

    private func accountCountText(for bank: Bank) -> String {
        let count = (bank.accounts ?? []).count
        return "\(count) \(count == 1 ? "cuenta" : "cuentas")"
    }

    private func deleteBank(_ bank: Bank) {
        withAnimation {
            modelContext.delete(bank)
        }
    }
}

private struct BankDetailView: View {
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let bank: Bank

    private var accounts: [BankAccount] {
        (bank.accounts ?? []).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if accounts.isEmpty {
                FinanceCenteredEmptyState(
                    "Sin cuentas",
                    systemImage: "creditcard",
                    description: Text("Este banco todavía no tiene cuentas")
                )
            } else {
                List(accounts, id: \.id) { account in
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: account.accountType.icon)
                                .font(.title3)
                                .foregroundStyle(bank.color)
                                .frame(width: 38, height: 38)
                                .background(bank.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(account.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)

                                    if account.isArchived {
                                        Text("Archivada")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(.secondary.opacity(0.12), in: Capsule())
                                    }
                                }

                                Text(account.accountType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Text(account.balance.masked(hideBalances, code: account.currency))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Color.clear)
                }
                .financeGlassListContainer()
            }
        }
        .navigationTitle(bank.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    hideBalances.toggle()
                } label: {
                    Image(systemName: hideBalances ? "eye.slash" : "eye")
                        .financeToolbarIconStyle()
                }
                .accessibilityLabel(hideBalances ? "Mostrar saldos" : "Ocultar saldos")
            }
        }
    }
}

/// Formulario para crear o editar un banco.
struct BankEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Bank.name) private var banks: [Bank]

    var bank: Bank?

    init(bank: Bank? = nil) {
        self.bank = bank
    }

    @State private var bankName: String = ""
    @State private var selectedIcon: BankIcon = .buildingColumns
    @State private var selectedColor: BankColor = .blue
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    private var isEditing: Bool { bank != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre del banco", text: $bankName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
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
                        ForEach(BankColor.allCases) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 36, height: 36)
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
                } header: {
                    FinanceGlassSectionHeader(title: "Color", systemImage: "paintpalette.fill")
                }
                .financeGlassFormSection()

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
            .navigationTitle(isEditing ? "Editar banco" : "Nuevo banco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Guardar" : "Crear") {
                        saveBank()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear(perform: loadData)
            .alert("Error", isPresented: $showingValidationAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func loadData() {
        guard let bank else { return }
        bankName = bank.name
        selectedIcon = bank.icon
        selectedColor = bank.bankColor
    }

    private func saveBank() {
        let trimmedName = bankName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "El nombre del banco es obligatorio."
            showingValidationAlert = true
            return
        }

        let duplicateExists = banks.contains { existing in
            guard let current = bank else {
                return existing.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
            }

            return existing.id != current.id && existing.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame
        }

        guard !duplicateExists else {
            validationMessage = "Ya existe un banco con ese nombre."
            showingValidationAlert = true
            return
        }

        if let bank {
            bank.name = trimmedName
            bank.icon = selectedIcon
            bank.bankColor = selectedColor
        } else {
            let newBank = Bank(name: trimmedName, icon: selectedIcon, bankColor: selectedColor)
            modelContext.insert(newBank)
        }

        dismiss()
    }
}
