//
//  CalculatorDecimalPadTextField.swift
//  Finance
//

import SwiftUI
import UIKit

struct CalculatorDecimalPadTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var expression: String
    @Binding var displayAmount: String
    @Binding var errorMessage: String?
    var placeholder: String
    var font: UIFont
    var textColor: UIColor
    var textAlignment: NSTextAlignment
    var tintColor: UIColor
    var isFocused: Bool
    var locksCaretAtEnd: Bool
    var onDone: () -> Void
    var onKeepFocus: () -> Void
    var onEditingEnded: () -> Void
    var onEmptyBackspace: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = CalculatorAmountTextField()
        textField.keyboardType = .decimalPad
        textField.borderStyle = .none
        textField.font = font
        textField.textColor = textColor
        textField.tintColor = tintColor
        textField.textAlignment = textAlignment
        textField.placeholder = placeholder
        textField.locksCaretAtEnd = locksCaretAtEnd
        textField.onDeleteBackwardWhenEmpty = { [coordinator = context.coordinator] in
            coordinator.handleEmptyBackspace()
        }
        textField.delegate = context.coordinator
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )

        let accessory = CalculatorInputAccessoryContainer()
        context.coordinator.accessoryContainer = accessory
        context.coordinator.textField = textField
        textField.inputAccessoryView = accessory
        context.coordinator.updateAccessory(forceReload: true)

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self

        if let calculatorField = uiView as? CalculatorAmountTextField {
            calculatorField.locksCaretAtEnd = locksCaretAtEnd
            calculatorField.onDeleteBackwardWhenEmpty = { [coordinator = context.coordinator] in
                coordinator.handleEmptyBackspace()
            }
        }

        if uiView.text != text {
            uiView.text = text
            if locksCaretAtEnd, let calculatorField = uiView as? CalculatorAmountTextField {
                calculatorField.moveCursorToEndIfNeeded()
            }
        }

        uiView.font = font
        uiView.textAlignment = textAlignment
        uiView.tintColor = tintColor
        uiView.placeholder = placeholder
        uiView.textColor = textColor

        context.coordinator.updateAccessoryIfNeeded()

        let focusChanged = context.coordinator.previousIsFocused != isFocused
        context.coordinator.previousIsFocused = isFocused

        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder, focusChanged {
            context.coordinator.isProgrammaticallyResigning = true
            uiView.resignFirstResponder()
            context.coordinator.isProgrammaticallyResigning = false
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CalculatorDecimalPadTextField
        weak var textField: UITextField?
        fileprivate weak var accessoryContainer: CalculatorInputAccessoryContainer?
        var isProgrammaticallyResigning = false
        var previousIsFocused: Bool?

        private var hasConfiguredAccessory = false
        private var lastAccessoryWidth: CGFloat = 0
        private var lastExpression = ""
        private var lastDisplayAmount = ""
        private var lastErrorMessage: String?
        private var lastHadErrorMessage: Bool?

        init(parent: CalculatorDecimalPadTextField) {
            self.parent = parent
        }

        @objc func textDidChange(_ sender: UITextField) {
            parent.text = sender.text ?? ""
            if let calculatorField = sender as? CalculatorAmountTextField, calculatorField.locksCaretAtEnd {
                calculatorField.moveCursorToEndIfNeeded()
            }
        }

        func handleEmptyBackspace() {
            parent.onEmptyBackspace()
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onKeepFocus()
            if let calculatorField = textField as? CalculatorAmountTextField {
                calculatorField.moveCursorToEndIfNeeded()
            }
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            guard let calculatorField = textField as? CalculatorAmountTextField, calculatorField.locksCaretAtEnd else {
                return
            }
            calculatorField.moveCursorToEndIfNeeded()
        }

        func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
            !parent.isFocused || isProgrammaticallyResigning
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard !isProgrammaticallyResigning else { return }
            parent.onEditingEnded()
            guard parent.isFocused else { return }
            DispatchQueue.main.async { [weak textField] in
                textField?.becomeFirstResponder()
            }
        }

        func updateAccessoryIfNeeded(forceReload: Bool = false) {
            guard let textField, let accessoryContainer else { return }

            let expressionChanged = parent.expression != lastExpression
            let displayChanged = parent.displayAmount != lastDisplayAmount
            let errorChanged = parent.errorMessage != lastErrorMessage

            guard forceReload || expressionChanged || displayChanged || errorChanged else { return }

            lastExpression = parent.expression
            lastDisplayAmount = parent.displayAmount
            lastErrorMessage = parent.errorMessage

            let width = accessoryWidth(for: textField)
            let hasErrorMessage = parent.errorMessage != nil

            let toolbar = AmountCalculatorKeyboardToolbar(
                expression: parent.$expression,
                displayAmount: parent.$displayAmount,
                errorMessage: parent.$errorMessage,
                onDone: parent.onDone,
                onKeepFocus: { [self] in
                    self.parent.onKeepFocus()
                    textField.becomeFirstResponder()
                }
            )

            _ = accessoryContainer.setContent(toolbar, width: width)

            let widthChanged = abs(width - lastAccessoryWidth) > 1
            let errorVisibilityChanged = lastHadErrorMessage != hasErrorMessage

            let needsReload = forceReload
                || !hasConfiguredAccessory
                || widthChanged
                || errorVisibilityChanged

            if needsReload {
                let shouldRestoreFirstResponder = textField.isFirstResponder
                textField.reloadInputViews()
                hasConfiguredAccessory = true
                lastAccessoryWidth = width
                lastHadErrorMessage = hasErrorMessage
                if shouldRestoreFirstResponder {
                    DispatchQueue.main.async { [weak textField] in
                        textField?.becomeFirstResponder()
                    }
                }
            }
        }

        func updateAccessory(forceReload: Bool = false) {
            updateAccessoryIfNeeded(forceReload: forceReload)
        }

        private func accessoryWidth(for textField: UITextField) -> CGFloat {
            if let windowWidth = textField.window?.bounds.width, windowWidth > 0 {
                return windowWidth
            }
            if let screenWidth = textField.window?.windowScene?.screen.bounds.width, screenWidth > 0 {
                return screenWidth
            }
            return max(textField.bounds.width, 320)
        }
    }
}

private final class CalculatorAmountTextField: UITextField {
    var locksCaretAtEnd = false
    var onDeleteBackwardWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if text?.isEmpty ?? true {
            onDeleteBackwardWhenEmpty?()
        } else {
            super.deleteBackward()
        }
    }

    func moveCursorToEndIfNeeded() {
        let end = endOfDocument
        selectedTextRange = textRange(from: end, to: end)
    }
}

fileprivate final class CalculatorInputAccessoryContainer: UIView {
    private var hostingController: UIHostingController<AmountCalculatorKeyboardToolbar>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        autoresizingMask = [.flexibleHeight]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @discardableResult
    func setContent(_ content: AmountCalculatorKeyboardToolbar, width: CGFloat) -> CGFloat {
        if let hostingController {
            hostingController.rootView = content
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
        } else {
            let hosting = UIHostingController(rootView: content)
            hosting.safeAreaRegions = []
            hosting.view.backgroundColor = .clear
            hostingController = hosting

            addSubview(hosting.view)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.view.topAnchor.constraint(equalTo: topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        let targetWidth = max(width, 1)
        let fittedHeight = hostingController?.sizeThatFits(
            in: CGSize(width: targetWidth, height: UIView.layoutFittingExpandedSize.height)
        ).height ?? 120

        frame.size = CGSize(width: targetWidth, height: fittedHeight)
        invalidateIntrinsicContentSize()
        return fittedHeight
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: frame.height)
    }
}
