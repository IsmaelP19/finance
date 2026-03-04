//
//  DeepLinkRouter.swift
//  Finance
//
//  Created by OpenCode on 04/03/2026.
//

import SwiftUI
import Foundation

/// Handles deep link navigation triggered by widgets or URL schemes.
@Observable
final class DeepLinkRouter {
    var pendingAddExpense = false

    func handle(url: URL) {
        guard url.scheme == "finance" else { return }

        switch url.host {
        case "add-expense":
            pendingAddExpense = true
        default:
            break
        }
    }
}
