//
//  AmountCalculatorAmountField.swift
//  Finance
//

import SwiftUI
import UIKit

struct AmountCalculatorHeroAmountField: View {
    @Binding var displayAmount: String
    @Binding var expression: String
    @Binding var errorMessage: String?
    var placeholder: String
    var font: Font
    var tint: Color
    var accessibilityLabel: String
    var focus: FocusState<MovementDraftHeroField?>.Binding
    var onDone: () -> Void

    @State private var keyboardText = ""
    @State private var isSyncingField = false

    private var isComposingExpression: Bool {
        AmountExpressionEvaluator.containsExpression(expression)
    }

    private var expressionPreviewText: String? {
        guard isComposingExpression,
              let preview = AmountExpressionEvaluator.previewValue(for: expression) else {
            return nil
        }
        return preview.asEditableAmount()
    }

    private var isFieldFocused: Bool {
        focus.wrappedValue == .amount
    }

    private var uiFont: UIFont {
        UIFont.systemFont(ofSize: 36, weight: .bold)
    }

    private var previewFont: Font {
        .system(size: 22, weight: .medium, design: .rounded)
    }

    private var expressionPrefixText: String {
        AmountCalculatorInput.prefixBeforeTrailingOperand(expression)
    }

    private var operandFieldMinWidth: CGFloat {
        let digits = max(keyboardText.count, 1)
        return CGFloat(digits) * 22 + 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if isComposingExpression, !expressionPrefixText.isEmpty {
                    Text(expressionPrefixText)
                        .font(font)
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                }

                CalculatorDecimalPadTextField(
                    text: $keyboardText,
                    expression: $expression,
                    displayAmount: $displayAmount,
                    errorMessage: $errorMessage,
                    placeholder: isComposingExpression ? "" : placeholder,
                    font: uiFont,
                    textColor: UIColor.label,
                    textAlignment: .left,
                    tintColor: UIColor(tint),
                    isFocused: isFieldFocused,
                    locksCaretAtEnd: isComposingExpression,
                    onDone: handleDone,
                    onKeepFocus: {
                        focus.wrappedValue = .amount
                    },
                    onEditingEnded: handleEditingEnded,
                    onEmptyBackspace: handleEmptyBackspace
                )
                .id("hero-amount-calculator-field")
                .frame(
                    minWidth: isComposingExpression ? operandFieldMinWidth : 0,
                    maxWidth: isComposingExpression ? nil : .infinity,
                    alignment: .leading
                )
                .fixedSize(horizontal: isComposingExpression, vertical: false)
                .layoutPriority(isComposingExpression ? 0 : 1)
                .onChange(of: keyboardText) { oldValue, newValue in
                    handleKeyboardTextChange(oldValue: oldValue, newValue: newValue)
                }

                if isComposingExpression, let expressionPreviewText {
                    Text("= \(expressionPreviewText)")
                        .font(previewFont)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }

            if let errorMessage, !isFieldFocused {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .accessibilityLabel(errorMessage)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueLabel)
        .accessibilityHint(accessibilityHintLabel)
        .onChange(of: expression) { _, _ in
            guard !isSyncingField else { return }
            syncKeyboardTextFromExpression()
        }
        .onChange(of: displayAmount) { _, _ in
            guard !isSyncingField, !isComposingExpression, expression.isEmpty else { return }
            syncKeyboardTextFromExpression()
        }
        .onChange(of: focus.wrappedValue) { oldValue, newValue in
            if newValue == .amount {
                syncKeyboardTextFromExpression()
            } else if oldValue == .amount {
                commitExpressionIfNeeded()
                keyboardText = ""
            }
        }
        .onAppear {
            syncKeyboardTextFromExpression()
        }
    }

    private var accessibilityValueLabel: String {
        let amount = displayAmount.isEmpty ? placeholder : displayAmount
        guard isComposingExpression else { return amount }

        if let expressionPreviewText {
            return "\(amount). Resultado previsto: \(expressionPreviewText)"
        }
        return amount
    }

    private var accessibilityHintLabel: String {
        AmountCalculatorInput.floatingExpression(for: expression).map { "Expresión: \($0)" } ?? ""
    }

    private func handleKeyboardTextChange(oldValue: String, newValue: String) {
        guard !isSyncingField else { return }

        isSyncingField = true
        if isComposingExpression {
            if newValue.count < oldValue.count, newValue.isEmpty, oldValue.isEmpty {
                expression = AmountCalculatorInput.deleteBackward(in: expression)
                exitExpressionModeIfNeeded()
            } else {
                expression = AmountCalculatorInput.expressionByReplacingTrailingOperand(
                    in: expression,
                    operand: newValue
                )
            }
        } else {
            displayAmount = newValue
            expression = ""
        }
        isSyncingField = false
    }

    private func exitExpressionModeIfNeeded() {
        guard !AmountExpressionEvaluator.containsExpression(expression) else { return }

        let remaining = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        displayAmount = remaining
        expression = ""
        syncKeyboardTextFromExpression()
    }

    private func syncKeyboardTextFromExpression() {
        isSyncingField = true
        keyboardText = AmountCalculatorAmountFieldSupport.keyboardText(
            expression: expression,
            displayAmount: displayAmount,
            isComposingExpression: isComposingExpression
        )
        isSyncingField = false
    }

    private func commitExpressionIfNeeded() {
        guard AmountExpressionEvaluator.containsExpression(expression) else {
            expression = ""
            return
        }

        switch AmountExpressionEvaluator.evaluate(expression) {
        case .success(let value):
            displayAmount = value.asEditableAmount()
            expression = ""
            errorMessage = nil
            syncKeyboardTextFromExpression()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleDone() {
        commitExpressionIfNeeded()
        onDone()
    }

    private func handleEditingEnded() {
        commitExpressionIfNeeded()
    }

    private func handleEmptyBackspace() {
        guard !isSyncingField else { return }

        isSyncingField = true
        if isComposingExpression {
            expression = AmountCalculatorInput.deleteBackward(in: expression)
            exitExpressionModeIfNeeded()
        } else if !displayAmount.isEmpty {
            displayAmount = String(displayAmount.dropLast())
            expression = ""
        }
        syncKeyboardTextFromExpression()
        isSyncingField = false
    }
}

struct AmountCalculatorInlineAmountField: View {
    @Binding var displayAmount: String
    @Binding var expression: String
    @Binding var errorMessage: String?
    var placeholder: String
    var font: Font
    var tint: Color
    var focus: FocusState<Bool>.Binding
    var onDone: () -> Void

    @State private var keyboardText = ""
    @State private var isSyncingField = false

    private var isComposingExpression: Bool {
        AmountExpressionEvaluator.containsExpression(expression)
    }

    private var expressionPreviewText: String? {
        guard isComposingExpression,
              let preview = AmountExpressionEvaluator.previewValue(for: expression) else {
            return nil
        }
        return preview.asEditableAmount()
    }

    private var uiFont: UIFont {
        UIFont.systemFont(ofSize: 20, weight: .bold)
    }

    private var previewFont: Font {
        .system(size: 13, weight: .medium, design: .rounded)
    }

    private var expressionPrefixText: String {
        AmountCalculatorInput.prefixBeforeTrailingOperand(expression)
    }

    private var operandFieldMinWidth: CGFloat {
        let digits = max(keyboardText.count, 1)
        return CGFloat(digits) * 14 + 8
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .center, spacing: 4) {
                if isComposingExpression, !expressionPrefixText.isEmpty {
                    Text(expressionPrefixText)
                        .font(font)
                        .foregroundStyle(.primary)
                        .allowsHitTesting(false)
                }

                CalculatorDecimalPadTextField(
                    text: $keyboardText,
                    expression: $expression,
                    displayAmount: $displayAmount,
                    errorMessage: $errorMessage,
                    placeholder: isComposingExpression ? "" : placeholder,
                    font: uiFont,
                    textColor: UIColor.label,
                    textAlignment: isComposingExpression ? .left : .right,
                    tintColor: UIColor(tint),
                    isFocused: focus.wrappedValue,
                    locksCaretAtEnd: isComposingExpression,
                    onDone: handleDone,
                    onKeepFocus: {
                        focus.wrappedValue = true
                    },
                    onEditingEnded: handleEditingEnded,
                    onEmptyBackspace: handleEmptyBackspace
                )
                .id("inline-amount-calculator-field")
                .frame(
                    minWidth: isComposingExpression ? operandFieldMinWidth : 0,
                    maxWidth: isComposingExpression ? nil : .infinity,
                    alignment: .trailing
                )
                .fixedSize(horizontal: isComposingExpression, vertical: false)
                .layoutPriority(isComposingExpression ? 0 : 1)
                .onChange(of: keyboardText) { oldValue, newValue in
                    handleKeyboardTextChange(oldValue: oldValue, newValue: newValue)
                }

                if isComposingExpression, let expressionPreviewText {
                    Text("= \(expressionPreviewText)")
                        .font(previewFont)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }

            if let errorMessage, !focus.wrappedValue {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel(errorMessage)
            }
        }
        .onChange(of: expression) { _, _ in
            guard !isSyncingField else { return }
            syncKeyboardTextFromExpression()
        }
        .onChange(of: displayAmount) { _, _ in
            guard !isSyncingField, !isComposingExpression, expression.isEmpty else { return }
            syncKeyboardTextFromExpression()
        }
        .onChange(of: focus.wrappedValue) { wasFocused, isFocused in
            if isFocused {
                syncKeyboardTextFromExpression()
            } else if wasFocused {
                commitExpressionIfNeeded()
                keyboardText = ""
            }
        }
        .onAppear {
            syncKeyboardTextFromExpression()
        }
    }

    private func handleKeyboardTextChange(oldValue: String, newValue: String) {
        guard !isSyncingField else { return }

        isSyncingField = true
        if isComposingExpression {
            if newValue.count < oldValue.count, newValue.isEmpty, oldValue.isEmpty {
                expression = AmountCalculatorInput.deleteBackward(in: expression)
                exitExpressionModeIfNeeded()
            } else {
                expression = AmountCalculatorInput.expressionByReplacingTrailingOperand(
                    in: expression,
                    operand: newValue
                )
            }
        } else {
            displayAmount = newValue
            expression = ""
        }
        isSyncingField = false
    }

    private func exitExpressionModeIfNeeded() {
        guard !AmountExpressionEvaluator.containsExpression(expression) else { return }

        let remaining = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        displayAmount = remaining
        expression = ""
        syncKeyboardTextFromExpression()
    }

    private func syncKeyboardTextFromExpression() {
        isSyncingField = true
        keyboardText = AmountCalculatorAmountFieldSupport.keyboardText(
            expression: expression,
            displayAmount: displayAmount,
            isComposingExpression: isComposingExpression
        )
        isSyncingField = false
    }

    private func commitExpressionIfNeeded() {
        guard AmountExpressionEvaluator.containsExpression(expression) else {
            expression = ""
            return
        }

        switch AmountExpressionEvaluator.evaluate(expression) {
        case .success(let value):
            displayAmount = value.asEditableAmount()
            expression = ""
            errorMessage = nil
            syncKeyboardTextFromExpression()
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleDone() {
        commitExpressionIfNeeded()
        onDone()
    }

    private func handleEditingEnded() {
        commitExpressionIfNeeded()
    }

    private func handleEmptyBackspace() {
        guard !isSyncingField else { return }

        isSyncingField = true
        if isComposingExpression {
            expression = AmountCalculatorInput.deleteBackward(in: expression)
            exitExpressionModeIfNeeded()
        } else if !displayAmount.isEmpty {
            displayAmount = String(displayAmount.dropLast())
            expression = ""
        }
        syncKeyboardTextFromExpression()
        isSyncingField = false
    }
}

private enum AmountCalculatorAmountFieldSupport {
    static func keyboardText(
        expression: String,
        displayAmount: String,
        isComposingExpression: Bool
    ) -> String {
        if isComposingExpression {
            return AmountCalculatorInput.trailingOperand(in: expression)
        }
        return displayAmount
    }
}
