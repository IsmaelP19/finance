//
//  AppDateFormatter.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import Foundation

enum AppDateFormatter {
    static let spanishDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d 'de' MMMM 'de' yyyy, HH:mm"
        return formatter
    }()

    static let spanishShortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}

extension Date {
    func asSpanishDateTime() -> String {
        AppDateFormatter.spanishDateTime.string(from: self)
    }

    func asSpanishShortDate() -> String {
        AppDateFormatter.spanishShortDate.string(from: self)
    }
}
