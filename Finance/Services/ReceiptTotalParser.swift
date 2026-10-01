//
//  ReceiptTotalParser.swift
//  Finance
//

import Foundation

/// Pure parser for OCR text. It deliberately has no Vision or UIKit dependency.
struct ReceiptTotalParser: Sendable {
    private struct Candidate {
        let amount: Decimal
        let currencyCode: String?
        let score: Int
        let lineIndex: Int
        let hasPositiveTotalLabel: Bool
    }

    nonisolated private static let amountPattern = #"(?<![\d])(?:[€$£]|EUR|USD|GBP)?\s*[-+]?\s*(?:\d{1,3}(?:[.,\s]\d{3})+|\d+)(?:[.,]\d{2})?(?!\d)"#
    nonisolated private static let receiptLabelPattern = #"\b(?:TOTAL|IMPORTE|A\s*PAGAR|PAGO|AMOUNT|GRAND\s+TOTAL|BALANCE\s+DUE|SUBTOTAL|IVA|VAT|TAX|IMPUESTOS?|SIN\s+IVA|SIN\s+IMPUESTOS?|NETO|DESCUENTO|DISCOUNT|CAMBIO|CHANGE|CASH)\b"#
    nonisolated private static let positiveTotalPattern = #"\b(?:TOTAL(?!\s*(?:SIN\s+IVA|SIN\s+IMPUESTOS?|NETO|SUBTOTAL|IVA|VAT|TAX))|IMPORTE|A\s*PAGAR|PAGO|AMOUNT|GRAND\s+TOTAL|BALANCE\s+DUE)\b"#
    nonisolated private static let negativeTotalPattern = #"\b(?:SUBTOTAL|IVA|VAT|TAX|IMPUESTOS?|SIN\s+IVA|SIN\s+IMPUESTOS?|NETO|DESCUENTO|DISCOUNT|CAMBIO|CHANGE|CASH)\b"#
    nonisolated private static let datePatterns = [
        (#"\b(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})\b"#, ["dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "dd.MM.yyyy", "d.M.yyyy"]),
        (#"\b(\d{4})[./-](\d{1,2})[./-](\d{1,2})\b"#, ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd"])
    ]

    nonisolated func parse(_ text: String, referenceDate: Date = Date()) -> ReceiptScanDraft {
        let lines = text.components(separatedBy: .newlines).map(cleanLine).filter { !$0.isEmpty }
        var candidates: [Candidate] = []
        for (index, line) in lines.enumerated() where !isDateLike(line) {
            let previousLine = index > 0 ? lines[index - 1] : nil
            candidates.append(contentsOf: amounts(in: line).compactMap { amount, range in
                guard hasAmountEvidence(in: line, amountRange: range) else { return nil }
                let hasPreviousTotalLabel = previousLine.map {
                    amounts(in: $0).isEmpty && hasPositiveTotalLabel(in: $0)
                } ?? false
                return Candidate(
                    amount: amount,
                    currencyCode: currencyCode(in: line),
                    score: score(line: line, amountRange: range, hasPreviousTotalLabel: hasPreviousTotalLabel),
                    lineIndex: index,
                    hasPositiveTotalLabel: hasPositiveTotalLabel(in: line, amountRange: range) || hasPreviousTotalLabel
                )
            })
        }
        let best = candidates.max { lhs, rhs in
            lhs.score == rhs.score ? lhs.lineIndex < rhs.lineIndex : lhs.score < rhs.score
        }
        let reliableBest = best.flatMap { $0.score >= 0 ? $0 : nil }
        let tied = candidates.filter { candidate in
            guard let reliableBest else { return false }
            return candidate.score == reliableBest.score && candidate.amount != reliableBest.amount
        }
        let status: ReceiptAmountStatus = reliableBest == nil
            ? .missing
            : (reliableBest?.hasPositiveTotalLabel == true && tied.isEmpty ? .detected : .ambiguous)
        let amount = reliableBest?.amount
        let currency = reliableBest?.currencyCode ?? currencyCode(in: text)
        var warnings: [String] = []
        if status == .missing { warnings.append("No se ha detectado el importe total.") }
        if status == .ambiguous { warnings.append("Hay varios importes candidatos; revísalos antes de guardar.") }
        if currency == nil && amount != nil { warnings.append("No se ha detectado la moneda.") }
        return ReceiptScanDraft(amount: amount, currencyCode: currency, merchant: merchant(from: lines), occurredAt: date(from: lines, referenceDate: referenceDate), amountStatus: status, warnings: warnings)
    }

    nonisolated private func score(line: String, amountRange: Range<String.Index>, hasPreviousTotalLabel: Bool) -> Int {
        let normalized = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
        let beforeAmount = String(line[..<amountRange.lowerBound]).folding(options: .diacriticInsensitive, locale: .current).uppercased()
        let afterAmount = String(line[amountRange.upperBound...]).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
        let beforeLabelContext = relevantLabelContext(in: beforeAmount)
        let labelContext = beforeAmount.range(of: Self.receiptLabelPattern, options: .regularExpression) != nil
            ? beforeLabelContext
            : relevantLabelContext(in: afterAmount)
        var score = 0
        let hasPositiveLabel = hasPositiveTotalLabel(in: labelContext) || hasPreviousTotalLabel
        if hasPositiveLabel { score += 100 }
        let hasNegativeLabel = labelContext.range(of: Self.negativeTotalPattern, options: .regularExpression) != nil
        if hasNegativeLabel || (!hasPositiveLabel && normalized.range(of: Self.negativeTotalPattern, options: .regularExpression) != nil) { score -= 80 }
        if labelContext.range(of: #"\b(?:TOTAL|IMPORTE)\b"#, options: .regularExpression) != nil { score += 15 }
        if currencyCode(in: line) != nil { score += 5 }
        return score
    }

    nonisolated private func relevantLabelContext(in beforeAmount: String) -> String {
        guard let labelRange = beforeAmount.range(of: Self.receiptLabelPattern, options: [.regularExpression, .backwards]) else {
            return beforeAmount
        }
        return String(beforeAmount[labelRange.lowerBound...])
    }

    nonisolated private func amounts(in line: String) -> [(Decimal, Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: Self.amountPattern) else { return [] }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: nsRange).compactMap { match in
            guard let range = Range(match.range, in: line) else { return nil }
            return parseAmount(String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)).map { ($0, range) }
        }
    }

    nonisolated private func hasAmountEvidence(in line: String, amountRange: Range<String.Index>) -> Bool {
        if currencyCode(in: line) != nil {
            return true
        }

        let normalized = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
        if normalized.range(of: #"\b(TOTAL|IMPORTE|A\s*PAGAR|PAGO|AMOUNT|GRAND\s*TOTAL|BALANCE\s*DUE)\b"#, options: .regularExpression) != nil {
            return true
        }

        // A decimal separator is useful evidence for item prices, while
        // integer-only metadata (dates, phone numbers and invoice IDs) is not.
        let candidateText = line[amountRange]
        return candidateText.contains(",") || candidateText.contains(".")
    }

    nonisolated private func hasPositiveTotalLabel(in line: String) -> Bool {
        let normalized = line.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).uppercased()
        return normalized.range(of: Self.positiveTotalPattern, options: .regularExpression) != nil
    }

    nonisolated private func hasPositiveTotalLabel(in line: String, amountRange: Range<String.Index>) -> Bool {
        let beforeAmount = String(line[..<amountRange.lowerBound])
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        let afterAmount = String(line[amountRange.upperBound...])
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
        let labelContext = beforeAmount.range(of: Self.receiptLabelPattern, options: .regularExpression) != nil
            ? relevantLabelContext(in: beforeAmount)
            : relevantLabelContext(in: afterAmount)
        return hasPositiveTotalLabel(in: labelContext)
    }

    nonisolated private func parseAmount(_ raw: String) -> Decimal? {
        var value = raw.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive).replacingOccurrences(of: "USD", with: "", options: .caseInsensitive).replacingOccurrences(of: "GBP", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        let commaCount = value.filter { $0 == "," }.count
        let dotCount = value.filter { $0 == "." }.count
        let lastComma = value.lastIndex(of: ",")
        let lastDot = value.lastIndex(of: ".")

        if commaCount > 0, dotCount > 0 {
            // With both separators, the last one is the decimal separator.
            if let lastComma, let lastDot, lastComma > lastDot {
                value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        } else if commaCount + dotCount > 0 {
            let separator: Character = commaCount > 0 ? "," : "."
            let count = max(commaCount, dotCount)
            if count > 1 {
                let components = value.split(separator: separator, omittingEmptySubsequences: false)
                // A final two-digit group is a decimal part; otherwise every
                // separator is treated as thousands grouping.
                if components.last?.count == 2 {
                    value = components.dropLast().joined() + "." + (components.last ?? "")
                } else {
                    value = components.joined()
                }
            } else if let separatorIndex = value.firstIndex(of: separator) {
                let fractionalDigits = value.distance(from: value.index(after: separatorIndex), to: value.endIndex)
                if fractionalDigits == 3 {
                    // Receipts commonly print 1.234 / 1,234 as 1,234.
                    value.removeAll { $0 == separator }
                } else if separator == "," {
                    value = value.replacingOccurrences(of: ",", with: ".")
                }
            }
        }

        guard let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), amount > 0 else { return nil }
        return amount
    }

    nonisolated private func currencyCode(in text: String) -> String? {
        let upper = text.uppercased()
        if upper.contains("€") || upper.contains("EUR") { return "EUR" }
        if upper.contains("$") || upper.contains("USD") { return "USD" }
        if upper.contains("£") || upper.contains("GBP") { return "GBP" }
        return nil
    }

    nonisolated private func merchant(from lines: [String]) -> String? {
        let candidates = lines.prefix(10).enumerated().compactMap { index, line -> (value: String, score: Int, index: Int)? in
            let upper = line.uppercased()
            guard line.count >= 2, line.range(of: #"\d{2,}"#, options: .regularExpression) == nil,
                  line.range(of: #"TOTAL|IMPORTE|FACTURA|TICKET|IVA|VAT|TEL[EÉ]FONO|WWW|HTTP|\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b"#, options: .regularExpression) == nil,
                  upper.range(of: #"^[\W_]+$"#, options: .regularExpression) == nil,
                  !line.contains(":"),
                  !isGenericNonMerchantLine(line),
                  !isSentenceLike(line) else { return nil }

            var score = 0
            if line.range(of: #"\bS\.?\s*(?:A|L)\.?\b|\bSLU\b|\bINC\.?\b|\bLTD\.?\b|\bLLC\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                score += 100
            }

            let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            let uppercaseLetters = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
            if !letters.isEmpty, Double(uppercaseLetters.count) / Double(letters.count) >= 0.65 {
                score += 25
            }
            if line.count <= 36 { score += 5 }
            return (line, score, index)
        }

        return candidates.max { lhs, rhs in
            lhs.score == rhs.score ? lhs.index > rhs.index : lhs.score < rhs.score
        }?.value
    }

    nonisolated private func isGenericNonMerchantLine(_ line: String) -> Bool {
        let normalized = line
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "AGENDA", "CALENDARIO", "DIARIO", "LIBRO", "NOVELA", "CAPITULO", "EPISODIO", "PAGINA"
        ].contains(normalized)
    }

    nonisolated private func isSentenceLike(_ line: String) -> Bool {
        let words = line.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 4 else { return false }
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let lowercaseLetters = letters.filter { CharacterSet.lowercaseLetters.contains($0) }
        guard !letters.isEmpty else { return false }
        return Double(lowercaseLetters.count) / Double(letters.count) > 0.45
    }

    nonisolated private func date(from lines: [String], referenceDate: Date) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        for line in lines {
            if line.range(of: #"\b\d{1,2}[./-]\d{1,2}[./-]\d{2}\b"#, options: .regularExpression) != nil { continue }
            for (pattern, formats) in Self.datePatterns {
                guard let dateRange = line.range(of: pattern, options: .regularExpression) else { continue }
                let rawDate = String(line[dateRange])
                guard rawDate.split(whereSeparator: { "/.-".contains($0) }).last?.count == 4 else { continue }
                for format in formats {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: rawDate), date <= referenceDate.addingTimeInterval(86_400) { return date }
                }
            }
        }
        return nil
    }

    nonisolated private func isDateLike(_ line: String) -> Bool {
        line.range(of: #"^\s*(?:FECHA|DATE)?\s*:?\s*\d{1,4}[./-]\d{1,2}[./-]\d{1,4}\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated private func cleanLine(_ line: String) -> String {
        line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
