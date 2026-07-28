//
//  AmountExpressionEvaluator.swift
//  Finance
//

import Foundation

enum AmountExpressionError: Equatable, LocalizedError {
    case invalidSyntax
    case divisionByZero
    case negativeResult
    case incompleteExpression

    var errorDescription: String? {
        switch self {
        case .invalidSyntax:
            return "La expresión no es válida."
        case .divisionByZero:
            return "No se puede dividir entre cero."
        case .negativeResult:
            return "El importe no puede ser negativo."
        case .incompleteExpression:
            return "La expresión está incompleta."
        }
    }
}

/// Evalúa expresiones aritméticas en campos de importe con formato español.
enum AmountExpressionEvaluator {
    nonisolated private static let operatorCharacters: Set<Character> = ["+", "-", "−", "×", "÷", "*", "/"]

    nonisolated static func containsExpression(_ text: String) -> Bool {
        text.contains { operatorCharacters.contains($0) }
    }

    nonisolated static func previewValue(for text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !containsExpression(trimmed) {
            return EditableAmount.parse(trimmed)
        }

        var evaluable = trimmed.trimmingTrailingWhitespace()
        while let last = evaluable.last {
            if last.isWhitespace {
                evaluable.removeLast()
                continue
            }
            if operatorCharacters.contains(last) {
                evaluable.removeLast()
                evaluable = evaluable.trimmingTrailingWhitespace()
                continue
            }
            break
        }

        guard !evaluable.isEmpty else { return nil }

        if case .success(let value) = evaluate(evaluable) {
            return value
        }

        return EditableAmount.parse(evaluable)
    }

    nonisolated static func evaluate(_ text: String) -> Result<Decimal, AmountExpressionError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.invalidSyntax) }
        guard containsExpression(trimmed) else {
            guard let value = EditableAmount.parse(trimmed) else {
                return .failure(.invalidSyntax)
            }
            guard value >= 0 else { return .failure(.negativeResult) }
            return .success(value)
        }

        guard let tokens = tokenize(trimmed), !tokens.isEmpty else {
            return .failure(.invalidSyntax)
        }

        if case .op = tokens.last {
            return .failure(.incompleteExpression)
        }

        switch evaluateTokens(tokens) {
        case .success(let value):
            guard value >= 0 else { return .failure(.negativeResult) }
            return .success(value)
        case .failure(let error):
            return .failure(error)
        }
    }

    // MARK: - Tokenization

    private enum Token: Equatable {
        case number(Decimal)
        case op(ArithmeticOperator)
    }

    private enum ArithmeticOperator: Character {
        case add = "+"
        case subtract = "-"
        case multiply = "*"
        case divide = "/"

        nonisolated var precedence: Int {
            switch self {
            case .add, .subtract: return 1
            case .multiply, .divide: return 2
            }
        }
    }

    nonisolated private static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]

            if character.isWhitespace {
                index = text.index(after: index)
                continue
            }

            if let op = normalizedOperator(character) {
                tokens.append(.op(op))
                index = text.index(after: index)
                continue
            }

            if isNumberCharacter(character) {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, isNumberCharacter(text[index]) {
                    index = text.index(after: index)
                }

                let numberText = String(text[start..<index])
                guard let value = EditableAmount.parse(numberText), value >= 0 else {
                    return nil
                }
                tokens.append(.number(value))
                continue
            }

            return nil
        }

        return tokens
    }

    nonisolated private static func isNumberCharacter(_ character: Character) -> Bool {
        character.isWholeNumber || character == "." || character == ","
    }

    nonisolated private static func normalizedOperator(_ character: Character) -> ArithmeticOperator? {
        switch character {
        case "+": return .add
        case "-", "−": return .subtract
        case "×", "*": return .multiply
        case "÷", "/": return .divide
        default: return nil
        }
    }

    // MARK: - Evaluation (PEMDAS via shunting-yard)

    nonisolated private static func evaluateTokens(_ tokens: [Token]) -> Result<Decimal, AmountExpressionError> {
        var output: [Decimal] = []
        var operators: [ArithmeticOperator] = []

        for token in tokens {
            switch token {
            case .number(let value):
                output.append(value)
            case .op(let op):
                while let last = operators.last,
                      last.precedence >= op.precedence {
                    guard let rhs = output.popLast(),
                          let lhs = output.popLast() else {
                        return .failure(.invalidSyntax)
                    }
                    switch apply(last, lhs: lhs, rhs: rhs) {
                    case .success(let result):
                        output.append(result)
                    case .failure(let error):
                        return .failure(error)
                    }
                    operators.removeLast()
                }
                operators.append(op)
            }
        }

        while let op = operators.popLast() {
            guard let rhs = output.popLast(),
                  let lhs = output.popLast() else {
                return .failure(.invalidSyntax)
            }
            switch apply(op, lhs: lhs, rhs: rhs) {
            case .success(let result):
                output.append(result)
            case .failure(let error):
                return .failure(error)
            }
        }

        guard output.count == 1, let result = output.first else {
            return .failure(.invalidSyntax)
        }

        return .success(result)
    }

    nonisolated private static func apply(
        _ op: ArithmeticOperator,
        lhs: Decimal,
        rhs: Decimal
    ) -> Result<Decimal, AmountExpressionError> {
        switch op {
        case .add:
            return .success(lhs + rhs)
        case .subtract:
            return .success(lhs - rhs)
        case .multiply:
            return .success(lhs * rhs)
        case .divide:
            guard rhs != 0 else { return .failure(.divisionByZero) }
            return .success(lhs / rhs)
        }
    }
}

enum AmountCalculatorInput {
    nonisolated static func appendOperator(_ symbol: String, to expression: String) -> String? {
        let base = expression.trimmingTrailingWhitespace()
        guard !base.isEmpty else { return nil }

        if endsWithOperator(base) {
            let withoutOperator = dropTrailingOperator(from: base)
            guard !withoutOperator.isEmpty else { return nil }
            return withoutOperator + " \(symbol) "
        }

        return base + " \(symbol) "
    }

    nonisolated static func expressionByReplacingTrailingOperand(in expression: String, operand: String) -> String {
        prefixBeforeTrailingOperand(expression) + operand
    }

    nonisolated static func prefixBeforeTrailingOperand(_ expression: String) -> String {
        let trimmed = expression.trimmingTrailingWhitespace()
        guard !trimmed.isEmpty else { return "" }
        guard AmountExpressionEvaluator.containsExpression(trimmed) else { return "" }

        var index = trimmed.endIndex

        while index > trimmed.startIndex {
            let before = trimmed.index(before: index)
            let character = trimmed[before]

            if character.isWhitespace || character.isWholeNumber || character == "." || character == "," {
                index = before
                continue
            }

            if isOperator(character) {
                index = trimmed.index(after: before)
                while index < trimmed.endIndex, trimmed[index].isWhitespace {
                    index = trimmed.index(after: index)
                }
                return String(trimmed[..<index])
            }

            return ""
        }

        return ""
    }

    nonisolated static func trailingOperand(in expression: String) -> String {
        let trimmed = expression.trimmingTrailingWhitespace()
        guard !trimmed.isEmpty else { return "" }

        if !AmountExpressionEvaluator.containsExpression(trimmed) {
            return trimmed
        }

        let prefix = prefixBeforeTrailingOperand(trimmed)
        return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func deleteBackward(in expression: String) -> String {
        let trimmed = expression.trimmingTrailingWhitespace()
        guard !trimmed.isEmpty else { return "" }

        let operand = trailingOperand(in: trimmed)
        if !operand.isEmpty {
            let shortenedOperand = String(operand.dropLast())
            return expressionByReplacingTrailingOperand(in: trimmed, operand: shortenedOperand)
        }

        let withoutTrailingOperator = dropTrailingOperator(from: trimmed)
        return withoutTrailingOperator.trimmingTrailingWhitespace()
    }

    nonisolated static func displayAmount(for expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let preview = AmountExpressionEvaluator.previewValue(for: trimmed) {
            return preview.asEditableAmount()
        }

        return trimmed
    }

    nonisolated static func floatingExpression(for expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AmountExpressionEvaluator.containsExpression(trimmed) else { return nil }
        return trimmed
    }

    nonisolated static func endsWithOperator(_ value: String) -> Bool {
        guard let last = value.trimmingTrailingWhitespace().last else { return false }
        return isOperator(last)
    }

    nonisolated private static func dropTrailingOperator(from expression: String) -> String {
        var value = expression.trimmingTrailingWhitespace()
        guard let last = value.last, isOperator(last) else { return value }

        value.removeLast()
        return value.trimmingTrailingWhitespace()
    }

    nonisolated private static func isOperator(_ character: Character) -> Bool {
        ["+", "−", "×", "÷", "-", "*", "/"].contains(character)
    }
}

private extension String {
    nonisolated func trimmingTrailingWhitespace() -> String {
        var copy = self
        while let last = copy.last, last.isWhitespace {
            copy.removeLast()
        }
        return copy
    }
}
