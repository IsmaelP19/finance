//
//  RecurringOccurrenceConfirmationSheet.swift
//  Finance
//

import SwiftUI

/// Editor específico para cambiar el importe de una ocurrencia pendiente.
struct RecurringOccurrenceAmountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAmountFocused: Bool

    let concept: String
    let scheduledDate: Date
    let suggestedAmount: Decimal
    let currencyCode: String
    let onSave: (Decimal, Bool) throws -> Void

    @State private var amountText: String
    @State private var amountExpression = ""
    @State private var applyToFuture = false
    @State private var errorMessage: String?

    init(
        concept: String,
        scheduledDate: Date,
        suggestedAmount: Decimal,
        currencyCode: String,
        onSave: @escaping (Decimal, Bool) throws -> Void
    ) {
        self.concept = concept
        self.scheduledDate = scheduledDate
        self.suggestedAmount = suggestedAmount
        self.currencyCode = currencyCode
        self.onSave = onSave
        _amountText = State(initialValue: suggestedAmount.asEditableAmount())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(concept)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    FinanceGlassSectionHeader(title: "Concepto", systemImage: "arrow.triangle.2.circlepath")
                }
                .financeGlassFormSection()

                Section {
                    LabeledContent("Programada") {
                        Text(scheduledDate.asSpanishDateTime())
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    FinanceGlassSectionHeader(title: "Fecha", systemImage: "calendar")
                }
                .financeGlassFormSection()

                Section {
                    HStack {
                        AmountCalculatorInlineAmountField(
                            displayAmount: $amountText,
                            expression: $amountExpression,
                            errorMessage: $errorMessage,
                            placeholder: "0,00",
                            font: .title3.weight(.bold),
                            tint: .financeAccent,
                            focus: $isAmountFocused,
                            onDone: { isAmountFocused = false }
                        )

                        CurrencySymbolLabel(code: currencyCode, companion: .inline)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Importe de la ocurrencia")
                } header: {
                    FinanceGlassSectionHeader(title: "Importe", systemImage: "eurosign.circle.fill")
                } footer: {
                    Text("Puedes usar operaciones aritméticas para calcular el nuevo importe.")
                }
                .financeGlassFormSection()

                Section {
                    Picker("Aplicar cambio a", selection: $applyToFuture) {
                        Text("Solo esta ocurrencia").tag(false)
                        Text("Esta ocurrencia y futuras").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    FinanceGlassSectionHeader(title: "Aplicar cambio a", systemImage: "repeat")
                }
                .financeGlassFormSection()
            }
            .financeGlassListContainer()
            .navigationTitle("Editar importe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onChange(of: amountText) { _, _ in errorMessage = nil }
            .onChange(of: amountExpression) { _, _ in errorMessage = nil }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func save() {
        let amount: Decimal?
        if AmountExpressionEvaluator.containsExpression(amountExpression) {
            amount = try? AmountExpressionEvaluator.evaluate(amountExpression).get()
        } else {
            amount = EditableAmount.parse(amountText)
        }

        guard let amount, amount > 0 else {
            errorMessage = "Introduce un importe válido mayor que cero."
            isAmountFocused = true
            return
        }

        do {
            try onSave(amount, applyToFuture)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription.isEmpty
                ? "No se pudo actualizar la ocurrencia. Inténtalo de nuevo."
                : error.localizedDescription
        }
    }
}
