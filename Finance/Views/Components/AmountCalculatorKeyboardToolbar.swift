//
//  AmountCalculatorKeyboardToolbar.swift
//  Finance
//

import SwiftUI

struct AmountCalculatorKeyboardToolbar: View {
    @Binding var expression: String
    @Binding var displayAmount: String
    @Binding var errorMessage: String?
    var onDone: () -> Void
    var onKeepFocus: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @State private var errorHapticTrigger = 0

    private let operators: [(symbol: String, accessibilityLabel: String)] = [
        ("+", "Sumar"),
        ("−", "Restar"),
        ("×", "Multiplicar"),
        ("÷", "Dividir")
    ]

    var body: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .accessibilityLabel(errorMessage)
            }

            operatorRow
        }
        .padding(.top, errorMessage == nil ? 8 : 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background { accessoryGlassBackground }
        .sensoryFeedback(.error, trigger: errorHapticTrigger)
    }

    private var operatorRow: some View {
        HStack(spacing: 2) {
            ForEach(operators, id: \.symbol) { item in
                Button {
                    insertOperator(item.symbol)
                } label: {
                    Text(item.symbol)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AmountCalculatorOperatorButtonStyle(isAccent: false))
                .accessibilityLabel(item.accessibilityLabel)
            }

            Button("Listo") {
                onDone()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.financeAccent)
            .frame(minWidth: 52, minHeight: 44)
            .accessibilityLabel("Listo")
            .accessibilityHint("Calcula la expresión y cierra el teclado")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var accessoryGlassBackground: some View {
        if #available(iOS 26, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(colorScheme == .dark ? 0.07 : 0.12), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 1)
                        .allowsHitTesting(false)
                }
        } else {
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }

    private func insertOperator(_ symbol: String) {
        errorMessage = nil

        if expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !displayAmount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expression = displayAmount
        }

        guard let updated = AmountCalculatorInput.appendOperator(symbol, to: expression) else { return }
        expression = updated
        restoreKeyboardFocus()
    }

    private func restoreKeyboardFocus() {
        Task { @MainActor in
            onKeepFocus()
        }
    }
}

private struct AmountCalculatorOperatorButtonStyle: ButtonStyle {
    let isAccent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isAccent ? Color.financeAccent : .primary)
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
