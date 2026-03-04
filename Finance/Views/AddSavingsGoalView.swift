//
//  AddSavingsGoalView.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import SwiftUI
import SwiftData

/// Formulario para crear o editar un objetivo de ahorro.
struct AddSavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]

    private let goalToEdit: SavingsGoal?

    @State private var name: String = ""
    @State private var targetText: String = ""
    @State private var hasTargetDate: Bool = false
    @State private var targetDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var selectedAccount: BankAccount?
    @State private var selectedColor: SavingsGoalColor = .blue
    @State private var selectedIcon: String = "star.fill"
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    private let iconOptions: [String] = [
        "star.fill", "house.fill", "car.fill", "airplane", "heart.fill",
        "graduationcap.fill", "briefcase.fill", "gift.fill", "umbrella.fill",
        "laptopcomputer", "fork.knife", "figure.run", "leaf.fill", "globe"
    ]

    init(goalToEdit: SavingsGoal? = nil) {
        self.goalToEdit = goalToEdit
    }

    private var isEditing: Bool { goalToEdit != nil }

    private var parsedTarget: Decimal? {
        let normalized = targetText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre del objetivo") {
                    TextField("Ej. Vacaciones de verano", text: $name)
                }

                Section("Importe objetivo") {
                    HStack {
                        TextField("0,00", text: $targetText)
                            .keyboardType(.decimalPad)
                        Text("€")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Cuenta vinculada") {
                    if accounts.isEmpty {
                        Text("No hay cuentas disponibles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Cuenta", selection: $selectedAccount) {
                            Text("Seleccionar…").tag(Optional<BankAccount>.none)
                            ForEach(accounts) { account in
                                Text(account.name).tag(Optional(account))
                            }
                        }
                        Text("El saldo actual de esta cuenta representará tu progreso.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Fecha límite") {
                    Toggle("Tiene fecha límite", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Fecha", selection: $targetDate, displayedComponents: .date)
                    }
                }

                Section("Personalización") {
                    Picker("Color", selection: $selectedColor) {
                        ForEach(SavingsGoalColor.allCases) { color in
                            HStack {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 14, height: 14)
                                Text(color.displayName)
                            }
                            .tag(color)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icono")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button {
                                    selectedIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .foregroundStyle(selectedIcon == icon ? selectedColor.color : .secondary)
                                        .frame(width: 38, height: 38)
                                        .background(selectedIcon == icon ? selectedColor.color.opacity(0.15) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(selectedIcon == icon ? selectedColor.color : Color.clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "Editar objetivo" : "Nuevo objetivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                }
            }
            .onAppear { loadExistingData() }
            .alert("Campos requeridos", isPresented: $showingValidationAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    // MARK: - Actions

    private func loadExistingData() {
        guard let g = goalToEdit else { return }
        name            = g.name
        targetText      = "\(g.targetAmount)"
        hasTargetDate   = g.targetDate != nil
        targetDate      = g.targetDate ?? targetDate
        selectedAccount = g.account
        selectedIcon    = g.iconName
        selectedColor   = SavingsGoalColor(rawValue: g.colorRaw) ?? .blue
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Introduce un nombre para el objetivo."
            showingValidationAlert = true
            return
        }
        guard let target = parsedTarget, target > 0 else {
            validationMessage = "Introduce un importe objetivo mayor que 0."
            showingValidationAlert = true
            return
        }

        if let g = goalToEdit {
            g.name         = trimmedName
            g.targetAmount = target
            g.targetDate   = hasTargetDate ? targetDate : nil
            g.account      = selectedAccount
            g.iconName     = selectedIcon
            g.colorRaw     = selectedColor.rawValue
            g.updatedAt    = Date()
        } else {
            let goal = SavingsGoal(
                name: trimmedName,
                targetAmount: target,
                targetDate: hasTargetDate ? targetDate : nil,
                iconName: selectedIcon,
                colorRaw: selectedColor.rawValue,
                account: selectedAccount
            )
            modelContext.insert(goal)
        }
        dismiss()
    }
}
