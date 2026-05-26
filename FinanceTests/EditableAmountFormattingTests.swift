//
//  EditableAmountFormattingTests.swift
//  FinanceTests
//

import Foundation
import Testing
@testable import Finance

struct EditableAmountFormattingTests {

    @Test func asEditableAmount_formatsThousandsAndDecimals() {
        let value = Decimal(string: "2426.83")!
        #expect(value.asEditableAmount() == "2.426,83")
    }

    @Test func asEditableAmount_formatsSmallAmounts() {
        let value = Decimal(string: "13.20")!
        #expect(value.asEditableAmount() == "13,20")
    }

    @Test func parse_withThousandsSeparatorAndDecimalComma() {
        let parsed = EditableAmount.parse("2.426,83")
        #expect(parsed == Decimal(string: "2426.83"))
    }

    @Test func parse_withoutThousandsSeparator() {
        let parsed = EditableAmount.parse("2426,83")
        #expect(parsed == Decimal(string: "2426.83"))
    }

    @Test func parse_smallAmount() {
        let parsed = EditableAmount.parse("13,20")
        #expect(parsed == Decimal(string: "13.20"))
    }

    @Test func parse_thousandsWithoutDecimalComma() {
        let parsed = EditableAmount.parse("1.000")
        #expect(parsed == Decimal(string: "1000"))
    }

    @Test func sanitize_preservesGroupedEditableAmount() {
        let sanitized = EditableAmount.sanitizeInput("2.426,83")
        #expect(sanitized == "2.426,83")
    }

    @Test func sanitize_doesNotCorruptGroupedAmountOnChange() {
        let initial = Decimal(string: "2426.83")!.asEditableAmount()
        #expect(initial == "2.426,83")
        let afterSanitize = EditableAmount.sanitizeInput(initial)
        #expect(afterSanitize == "2.426,83")
        #expect(EditableAmount.parse(afterSanitize) == Decimal(string: "2426.83"))
    }

    @Test func parse_emptyReturnsNil() {
        #expect(EditableAmount.parse("") == nil)
        #expect(EditableAmount.parse("   ") == nil)
    }
}
