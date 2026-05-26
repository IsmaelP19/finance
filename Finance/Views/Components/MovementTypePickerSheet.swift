//
//  MovementTypePickerSheet.swift
//  Finance
//
//  Created by OpenCode on 26/05/2026.
//

import SwiftUI

/// Selector dedicado para evitar `Menu` nativo en el tipo de movimiento.
struct MovementTypePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: MovementType
    @State private var draftSelection: MovementType

    init(selection: Binding<MovementType>) {
        _selection = selection
        _draftSelection = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.large) {
                    FinanceGlassSectionHeader(
                        title: "Tipo de movimiento",
                        systemImage: "arrow.up.arrow.down.circle.fill",
                        subtitle: "Al cambiarlo, algunos campos del formulario pueden ajustarse automáticamente"
                    )

                    VStack(spacing: 10) {
                        ForEach(MovementType.allCases) { option in
                            Button {
                                draftSelection = option
                            } label: {
                                MovementTypePickerRow(
                                    type: option,
                                    description: description(for: option),
                                    isSelected: draftSelection == option
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.displayName)
                            .accessibilityHint(description(for: option))
                            .accessibilityValue(draftSelection == option ? "Seleccionado" : "No seleccionado")
                            .accessibilityAddTraits(draftSelection == option ? .isSelected : [])
                        }
                    }
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
                    .accessibilityLabel("Confirmar tipo de movimiento")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func description(for type: MovementType) -> String {
        switch type {
        case .expense:
            return "Registra una salida de dinero desde una cuenta."
        case .income:
            return "Registra dinero recibido en una cuenta."
        case .transfer:
            return "Mueve dinero entre dos cuentas propias."
        }
    }
}

private struct MovementTypePickerRow: View {
    let type: MovementType
    let description: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: type.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(type.color, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(type.displayName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? type.color : Color.secondary.opacity(0.35))
                .accessibilityHidden(true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? type.color.opacity(0.14) : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? type.color.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
