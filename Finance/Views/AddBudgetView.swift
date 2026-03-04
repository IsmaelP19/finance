//
//  AddBudgetView.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import SwiftUI
import SwiftData

/// Formulario para crear o editar un presupuesto mensual por categoría.
struct AddBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]

    private let budgetToEdit: Budget?

    @State private var selectedCategory: MovementCategory?
    @State private var limitText: String = ""
    @State private var isActive: Bool = true
    @State private var notifyAt80: Bool = true
    @State private var notifyAt100: Bool = true
    @State private var showingValidationAlert = false
    @State private var validationMessage = ""

    init(budgetToEdit: Budget? = nil) {
        self.budgetToEdit = budgetToEdit
    }

    private var isEditing: Bool { budgetToEdit != nil }

    private var parsedLimit: Decimal? {
        let normalized = limitText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Categoría") {
                    if categories.isEmpty {
                        Text("No hay categorías disponibles. Crea una en Ajustes > Gestionar categorías.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Categoría", selection: $selectedCategory) {
                            Text("Seleccionar…").tag(Optional<MovementCategory>.none)
                            ForEach(categories) { cat in
                                Label(cat.name, systemImage: cat.iconName)
                                    .tag(Optional(cat))
                            }
                        }
                    }
                }

                Section("Límite mensual") {
                    HStack {
                        TextField("0,00", text: $limitText)
                            .keyboardType(.decimalPad)
                        Text("€")
                            .foregroundStyle(.secondary)
                    }
                    Text("Importe máximo de gasto en esta categoría durante el mes en curso.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Notificaciones") {
                    Toggle("Aviso al 80 %", isOn: $notifyAt80)
                    Toggle("Aviso al 100 %", isOn: $notifyAt100)
                    Text("Recibirás una notificación cuando el gasto real de la categoría alcance estos umbrales.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Estado") {
                    Toggle("Presupuesto activo", isOn: $isActive)
                }
            }
            .navigationTitle(isEditing ? "Editar presupuesto" : "Nuevo presupuesto")
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
        guard let b = budgetToEdit else { return }
        selectedCategory  = b.category
        limitText         = "\(b.limitAmount)"
        isActive          = b.isActive
        notifyAt80        = b.notifyAt80Percent
        notifyAt100       = b.notifyAt100Percent
    }

    private func save() {
        guard let category = selectedCategory else {
            validationMessage = "Selecciona una categoría para el presupuesto."
            showingValidationAlert = true
            return
        }
        guard let limit = parsedLimit, limit > 0 else {
            validationMessage = "Introduce un límite mensual mayor que 0."
            showingValidationAlert = true
            return
        }

        if let b = budgetToEdit {
            b.category         = category
            b.limitAmount      = limit
            b.isActive         = isActive
            b.notifyAt80Percent  = notifyAt80
            b.notifyAt100Percent = notifyAt100
            b.updatedAt        = Date()
        } else {
            let budget = Budget(
                limitAmount: limit,
                category: category,
                isActive: isActive,
                notifyAt80Percent: notifyAt80,
                notifyAt100Percent: notifyAt100
            )
            modelContext.insert(budget)
        }
        dismiss()
    }
}
