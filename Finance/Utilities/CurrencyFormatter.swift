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

    /// Formatea el valor para campos de edición (sin símbolo de moneda).
    /// Ejemplo: 13.20 -> "13,20" · 1000 -> "1.000,00"
    nonisolated func asEditableAmount() -> String {
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
        return formatter.string(from: self as NSDecimalNumber) ?? "0,00"
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

// MARK: - Editable amounts

/// Parseo y sanitización de importes en campos de texto (`.` miles, `,` decimales).
enum EditableAmount {
    /// Convierte texto de campo editable a `Decimal`.
    /// Ejemplos: `"2.426,83"` → 2426.83 · `"13,20"` → 13.20 · `"1.000"` → 1000
    nonisolated static func parse(_ text: String) -> Decimal? {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        if cleaned.contains(",") {
            let withoutThousands = cleaned.replacingOccurrences(of: ".", with: "")
            let normalized = withoutThousands.replacingOccurrences(of: ",", with: ".")
            return Decimal(string: normalized)
        }

        if cleaned.contains(".") {
            let withoutThousands = cleaned.replacingOccurrences(of: ".", with: "")
            return Decimal(string: withoutThousands)
        }

        return Decimal(string: cleaned)
    }

    /// Limita la entrada a dígitos, separador de miles `.` y una coma decimal.
    /// No convierte `.` en `,` para evitar corromper valores como `"2.426,83"`.
    nonisolated static func sanitizeInput(_ text: String) -> String {
        let trimmed = text.replacingOccurrences(of: " ", with: "")
        var output = ""
        var hasDecimalSeparator = false

        for character in trimmed {
            if character.isWholeNumber {
                output.append(character)
            } else if character == ".", !hasDecimalSeparator {
                output.append(character)
            } else if character == ",", !hasDecimalSeparator {
                hasDecimalSeparator = true
                output.append(character)
            }
        }

        if output.first == "," {
            output = "0" + output
        }

        return output
    }
}
