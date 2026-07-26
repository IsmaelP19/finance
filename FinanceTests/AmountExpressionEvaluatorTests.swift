//
//  AmountExpressionEvaluatorTests.swift
//  FinanceTests
//

import Foundation
import Testing
@testable import Finance

struct AmountExpressionEvaluatorTests {

    @Test func containsExpression_detectsOperators() {
        #expect(AmountExpressionEvaluator.containsExpression("10 + 5"))
        #expect(AmountExpressionEvaluator.containsExpression("10−3"))
        #expect(!AmountExpressionEvaluator.containsExpression("15,00"))
        #expect(!AmountExpressionEvaluator.containsExpression("2.426,83"))
    }

    @Test func evaluate_simpleAddition() {
        let result = AmountExpressionEvaluator.evaluate("10 + 5")
        #expect(result == .success(Decimal(15)))
    }

    @Test func evaluate_subtractionLeftToRight() {
        let result = AmountExpressionEvaluator.evaluate("10 - 3 - 2")
        #expect(result == .success(Decimal(5)))
    }

    @Test func evaluate_pemdasMultiplicationBeforeAddition() {
        let result = AmountExpressionEvaluator.evaluate("2 + 3 × 4")
        #expect(result == .success(Decimal(14)))
    }

    @Test func evaluate_pemdasDivisionBeforeSubtraction() {
        let result = AmountExpressionEvaluator.evaluate("10 - 8 ÷ 2")
        #expect(result == .success(Decimal(6)))
    }

    @Test func evaluate_spanishDecimalNumbers() {
        let result = AmountExpressionEvaluator.evaluate("10,5 + 2,3")
        #expect(result == .success(Decimal(string: "12.8")!))
    }

    @Test func evaluate_spanishThousandsSeparator() {
        let result = AmountExpressionEvaluator.evaluate("1.000 + 500")
        #expect(result == .success(Decimal(1500)))
    }

    @Test func evaluate_groupedAmountWithAddition() {
        let result = AmountExpressionEvaluator.evaluate("2.426,83 + 100")
        #expect(result == .success(Decimal(string: "2526.83")!))
    }

    @Test func evaluate_withoutSpaces() {
        let result = AmountExpressionEvaluator.evaluate("10+5×2")
        #expect(result == .success(Decimal(20)))
    }

    @Test func evaluate_plainNumberWithoutOperators() {
        let result = AmountExpressionEvaluator.evaluate("13,20")
        #expect(result == .success(Decimal(string: "13.20")!))
    }

    @Test func evaluate_divisionByZero() {
        let result = AmountExpressionEvaluator.evaluate("10 ÷ 0")
        #expect(result == .failure(.divisionByZero))
    }

    @Test func evaluate_negativeResult() {
        let result = AmountExpressionEvaluator.evaluate("5 - 10")
        #expect(result == .failure(.negativeResult))
    }

    @Test func evaluate_incompleteExpression() {
        let result = AmountExpressionEvaluator.evaluate("10 +")
        #expect(result == .failure(.incompleteExpression))
    }

    @Test func evaluate_invalidSyntax() {
        let result = AmountExpressionEvaluator.evaluate("abc + 1")
        #expect(result == .failure(.invalidSyntax))
    }

    @Test func previewValue_incompleteExpressionUsesEvaluablePrefix() {
        let preview = AmountExpressionEvaluator.previewValue(for: "5 × 3 − ")
        #expect(preview == Decimal(15))
    }

    @Test func previewValue_completeExpressionMatchesEvaluate() {
        let preview = AmountExpressionEvaluator.previewValue(for: "5 × 3 − 1")
        #expect(preview == Decimal(14))
    }

    @Test func appendOperator_seedsFromCommittedAmount() {
        let expression = AmountCalculatorInput.appendOperator("×", to: "23,50")
        #expect(expression == "23,50 × ")
    }

    @Test func appendOperator_rejectsEmptyBase() {
        #expect(AmountCalculatorInput.appendOperator("+", to: "") == nil)
        #expect(AmountCalculatorInput.appendOperator("+", to: "   ") == nil)
    }

    @Test func appendOperator_replacesTrailingOperator() {
        #expect(AmountCalculatorInput.appendOperator("×", to: "10 + ") == "10 × ")
        #expect(AmountCalculatorInput.appendOperator("−", to: "10 ÷ ") == "10 − ")
    }

    @Test func floatingExpression_onlyWhenOperatorsPresent() {
        #expect(AmountCalculatorInput.floatingExpression(for: "23 × 2") == "23 × 2")
        #expect(AmountCalculatorInput.floatingExpression(for: "23,50") == nil)
    }

    @Test func previewValue_liveMultiplicationPreview() {
        let preview = AmountExpressionEvaluator.previewValue(for: "23 × 2")
        #expect(preview == Decimal(46))
    }

    @Test func deleteBackward_exitsExpressionModeToPlainNumber() {
        let afterDelete = AmountCalculatorInput.deleteBackward(in: "23 × ")
        #expect(afterDelete == "23")
        #expect(!AmountExpressionEvaluator.containsExpression(afterDelete))
    }

    @Test func previewValue_incompleteAdditionUsesCommittedPrefix() {
        let preview = AmountExpressionEvaluator.previewValue(for: "100 + ")
        #expect(preview == Decimal(100))
    }

    @Test func previewValue_invalidExpressionReturnsNil() {
        #expect(AmountExpressionEvaluator.previewValue(for: "abc + 1") == nil)
    }
}
