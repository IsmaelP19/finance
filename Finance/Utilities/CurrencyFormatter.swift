//
//  CurrencyFormatter.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import Foundation

private enum AppNumberFormatter {
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = 3
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()

    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        formatter.groupingSize = 3
        formatter.secondaryGroupingSize = 3
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    static func currencySymbol(for code: String) -> String {
        AppCurrency.symbol(for: code)
    }
}

// MARK: - Hide balances

/// Clave compartida de AppStorage para ocultar saldos.
enum HideBalances {
    static let storageKey = "hideBalances"
    /// Texto de sustitución cuando los saldos están ocultos.
    static let mask = "••••••"
}

// MARK: - Decimal extensions

/// Extensión para formatear valores Decimal como moneda.
extension Decimal {
    /// Formatea el valor como moneda (por defecto la moneda global de la app).
    /// Ejemplo: 1234.56 -> "1.234,56 €"
    func asCurrency(code: String = AppCurrency.currentCode()) -> String {
        if UserDefaults.standard.bool(forKey: HideBalances.storageKey) {
            return HideBalances.mask
        }
        let amount = AppNumberFormatter.decimal.string(from: self as NSDecimalNumber) ?? "0,00"
        return "\(amount) \(AppNumberFormatter.currencySymbol(for: code))"
    }

    /// Devuelve `HideBalances.mask` si `hidden` es true, o el importe formateado si es false.
    func masked(_ hidden: Bool, code: String = AppCurrency.currentCode()) -> String {
        hidden ? HideBalances.mask : asCurrency(code: code)
    }

    /// Devuelve true si el valor es negativo.
    var isNegative: Bool {
        return self < 0
    }
}

extension Int {
    func grouped() -> String {
        let number = NSNumber(value: self)
        return AppNumberFormatter.integer.string(from: number) ?? "\(self)"
    }
}
