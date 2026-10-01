//
//  ReceiptTotalParserTests.swift
//  FinanceTests
//

import Foundation
import Testing
@testable import Finance

struct ReceiptTotalParserTests {
    private let parser = ReceiptTotalParser()

    @Test func parsesEuropeanTotalAndMerchantAndDate() {
        let draft = parser.parse("MERCADONA\nAv. España 12\n12/08/2026\nSubtotal 10,00 €\nIVA 2,10 €\nTOTAL 12,10 €", referenceDate: date("2026-08-12"))
        #expect(draft.amount == Decimal(string: "12.10"))
        #expect(draft.currencyCode == "EUR")
        #expect(draft.merchant == "MERCADONA")
        #expect(draft.amountStatus == .detected)
        #expect(draft.occurredAt != nil)
    }

    @Test func prefersRetailerLineOverAdjacentSentence() {
        let draft = parser.parse("Emilio, que conste en acta:\nMERCADONA, S.A.\nAvda. de la Igualdad, 1\nTOTAL 8,00 €")

        #expect(draft.merchant == "MERCADONA, S.A.")
    }

    @Test func ignoresGenericAgendaHeadingNearRetailer() {
        let draft = parser.parse("AGENDA\nMERCADONA\nAvda. de la Igualdad, 1\nTOTAL 8,00 €")

        #expect(draft.merchant == "MERCADONA")
    }

    @Test func parsesInternationalThousandsAndDecimalSeparators() {
        let draft = parser.parse("ACME STORE\nGrand Total USD 1,234.56", referenceDate: date("2026-08-12"))
        #expect(draft.amount == Decimal(string: "1234.56"))
        #expect(draft.currencyCode == "USD")
        #expect(draft.amountStatus == .detected)
    }

    @Test func parsesPlainInternationalAmountWithFourDigits() {
        let draft = parser.parse("STORE\nTOTAL 1234.56 EUR")

        #expect(draft.amount == Decimal(string: "1234.56"))
        #expect(draft.currencyCode == "EUR")
        #expect(draft.amountStatus == .detected)
    }

    @Test func parsesThousandsSeparatorWithoutDecimalPart() {
        let european = parser.parse("STORE\nTOTAL 1.234 €")
        let international = parser.parse("STORE\nTOTAL 1,234 USD")

        #expect(european.amount == Decimal(string: "1234"))
        #expect(international.amount == Decimal(string: "1234"))
    }

    @Test func penalizesSubtotalTaxDiscountAndChange() {
        let draft = parser.parse("SHOP\nSubtotal 20,00 €\nIVA 4,20 €\nDescuento 2,00 €\nCambio 0,00 €\nA PAGAR 22,20 €")
        #expect(draft.amount == Decimal(string: "22.20"))
        #expect(draft.amountStatus == .detected)
    }

    @Test func prefersFinalTotalOverTotalWithoutVAT() {
        let draft = parser.parse("SHOP\nTOTAL EUR 52.50\nTOTAL SIN IVA 43.39 EUR")

        #expect(draft.amount == Decimal(string: "52.50"))
        #expect(draft.amountStatus == .detected)
    }

    @Test func associatesOCRAmountWithTotalLabelOnPreviousLine() {
        let draft = parser.parse("SHOP\nTOTAL EUR\n52.50\nTOTAL SIN IVA\n43.39 EUR")

        #expect(draft.amount == Decimal(string: "52.50"))
        #expect(draft.amountStatus == .detected)
    }

    @Test func reportsMissingAmount() {
        let draft = parser.parse("CAFETERIA\n12/08/2026\nGracias por su visita")
        #expect(draft.amount == nil)
        #expect(draft.amountStatus == .missing)
        #expect(!draft.warnings.isEmpty)
    }

    @Test func ignoresDatesAndIntegerMetadataWhenNoMoneyEvidence() {
        let draft = parser.parse("MERCADONA, S.A.\nFecha: 12/08/2026\nAvda. de la Igualdad, 1\nTeléfono: 955746884\nFactura simplificada: 3485-014-265296")

        #expect(draft.amount == nil)
        #expect(draft.amountStatus == .missing)
    }

    @Test func doesNotTreatSubtotalTaxOrChangeAsTheReceiptTotal() {
        let draft = parser.parse("SHOP\nSubtotal 20,00 €\nIVA 4,20 €\nCambio 5,00 €")

        #expect(draft.amount == nil)
        #expect(draft.amountStatus == .missing)
    }

    @Test func treatsUnlabelledProductPriceAsAmbiguousWithoutATotalLabel() {
        let draft = parser.parse("SHOP\nSubtotal 20,00 €\nProducto 5,00")

        #expect(draft.amount == Decimal(string: "5.00"))
        #expect(draft.amountStatus == .ambiguous)
    }

    @Test func reportsAmbiguousEqualPriorityTotals() {
        let draft = parser.parse("TIENDA\nTOTAL 10,00 €\nTOTAL 12,00 €")
        #expect(draft.amount == Decimal(string: "12.00"))
        #expect(draft.amountStatus == .ambiguous)
        #expect(draft.warnings.contains("Hay varios importes candidatos; revísalos antes de guardar."))
    }

    @Test func avoidsAmbiguousDateAndStillFindsMerchant() {
        let draft = parser.parse("PANADERIA\nFecha 01/02/03\nTOTAL 4,50 €")
        #expect(draft.merchant == "PANADERIA")
        #expect(draft.occurredAt == nil)
        #expect(draft.amount == Decimal(string: "4.50"))
    }

    @Test func extractsDateWhenItIsPrefixedByALabel() {
        let draft = parser.parse("PANADERIA\nFecha: 12/08/2026\nTOTAL 4,50 €", referenceDate: date("2026-08-12"))

        #expect(draft.occurredAt != nil)
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value)!
    }
}
