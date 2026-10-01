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
@MainActor
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingAddExpense = false
    var walletExpenseDraftRevision = 0

    func notifyWalletExpenseDraftAvailable() {
        walletExpenseDraftRevision += 1
    }

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
