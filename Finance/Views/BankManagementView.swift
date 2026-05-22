//
//  BankManagementView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Pantalla para gestionar bancos guardados: crear, editar y eliminar.
struct BankManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Bank.name) private var banks: [Bank]

    @State private var editingBank: Bank?
    @State private var showingCreateBank = false

    var body: some View {
        NavigationStack {
            Group {
                if banks.isEmpty {
                    FinanceCenteredEmptyState(
                        "Sin bancos",
                        systemImage: "building.columns",
                        description: Text("Pulsa + para crear tu primer banco")
                    )
                } else {
                    List {
                        ForEach(banks, id: \.id) { bank in
                            Button {
                                editingBank = bank
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: bank.iconName)
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .frame(width: 34, height: 34)
                                        .background(bank.color)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bank.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)

                                        Text("\((bank.accounts ?? []).count) \((bank.accounts ?? []).count == 1 ? "cuenta" : "cuentas")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .financeElevatedRow()
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    editingBank = bank
                                } label: {
                                    Label("Editar", systemImage: "pencil")
                                }
                                .tint(.financeAccent)
                            }
                        }
                        .onDelete(perform: deleteBanks)
                    }
                    .financeGlassListContainer()
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
        }
    }

    private func deleteBanks(at offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(banks[index])
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
