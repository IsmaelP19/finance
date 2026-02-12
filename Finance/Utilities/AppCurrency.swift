//
//  AppCurrency.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import Foundation

enum AppCurrency {
    static let storageKey = "appCurrencyCode"
    static let fallbackCode = "EUR"

    static let supported: [(code: String, name: String)] = [
        ("EUR", "Euro"),
        ("USD", "Dólar estadounidense"),
        ("GBP", "Libra esterlina"),
        ("CHF", "Franco suizo"),
        ("JPY", "Yen japonés")
    ]

    static func currentCode() -> String {
        let saved = UserDefaults.standard.string(forKey: storageKey) ?? fallbackCode
        return supported.contains(where: { $0.code == saved }) ? saved : fallbackCode
    }

    static func displayName(for code: String) -> String {
        supported.first(where: { $0.code == code })?.name ?? code
    }

    static func symbol(for code: String) -> String {
        switch code {
        case "EUR": return "€"
        case "USD": return "$"
        case "GBP": return "£"
        case "CHF": return "CHF"
        case "JPY": return "¥"
        default:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = code
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.currencySymbol ?? code
        }
    }
}
