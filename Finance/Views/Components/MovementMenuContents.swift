//
//  MovementMenuContents.swift
//  Finance
//
//  Created by OpenCode on 23/05/2026.
//

import SwiftUI

/// Grupo de cuentas por banco para menús de selección.
struct MovementAccountBankGroup: Identifiable {
    let id: String
    let bankName: String
    let accounts: [BankAccount]
}

/// Aplaza mutaciones de estado hasta después del cierre del `Menu` nativo para evitar
/// desincronía visual del label al hacer scroll (bug UIKit/SwiftUI).
enum MenuSelectionScheduler {
    static func afterDismiss(perform action: @escaping () -> Void) {
        DispatchQueue.main.async {
            action()
        }
    }
}

struct MovementTypeMenuContent: View {
    @Binding var selection: MovementType

    var body: some View {
        ForEach(MovementType.allCases) { option in
            Button {
                MenuSelectionScheduler.afterDismiss {
                    selection = option
                }
            } label: {
                Label(option.displayName, systemImage: option.icon)
            }
        }
    }
}

struct MovementAccountMenuContent: View {
    let accountGroups: [MovementAccountBankGroup]
    @Binding var selection: BankAccount?
    var excludingAccountID: UUID?

    var body: some View {
        ForEach(accountGroups) { group in
            let visibleAccounts = filteredAccounts(in: group)
            if !visibleAccounts.isEmpty {
                Section(group.bankName) {
                    ForEach(visibleAccounts, id: \.id) { account in
                        Button {
                            MenuSelectionScheduler.afterDismiss {
                                selection = account
                            }
                        } label: {
                            Label(
                                account.name,
                                systemImage: account.id == selection?.id ? "checkmark" : accountIconName(for: account)
                            )
                        }
                    }
                }
            }
        }
    }

    private func filteredAccounts(in group: MovementAccountBankGroup) -> [BankAccount] {
        guard let excludingAccountID else { return group.accounts }
        return group.accounts.filter { $0.id != excludingAccountID }
    }

    private func accountIconName(for account: BankAccount) -> String {
        account.isInvestmentAccount ? "chart.line.uptrend.xyaxis" : "building.columns"
    }
}

struct MovementCategoryMenuContent: View {
    let categories: [MovementCategory]
    @Binding var selection: MovementCategory?
    var showsCreateOption: Bool = true
    var onCreateCategory: () -> Void = {}

    var body: some View {
        ForEach(categories, id: \.id) { category in
            Button {
                MenuSelectionScheduler.afterDismiss {
                    selection = category
                }
            } label: {
                Label(
                    category.name,
                    systemImage: category.id == selection?.id ? "checkmark" : category.iconName
                )
            }
        }

        if showsCreateOption {
            Divider()

            Button {
                MenuSelectionScheduler.afterDismiss {
                    onCreateCategory()
                }
            } label: {
                Label("Crear categoría", systemImage: "plus.circle")
            }
        }
    }
}

struct AccountFilterMenuContent: View {
    let accountGroups: [MovementAccountBankGroup]
    @Binding var selectedAccountID: UUID?
    let allowsAllAccounts: Bool
    let allAccountsTitle: String

    var body: some View {
        if allowsAllAccounts {
            Button {
                MenuSelectionScheduler.afterDismiss {
                    selectedAccountID = nil
                }
            } label: {
                Label(allAccountsTitle, systemImage: selectedAccountID == nil ? "checkmark" : "building.2")
            }
        }

        ForEach(accountGroups) { group in
            Section(group.bankName) {
                ForEach(group.accounts, id: \.id) { account in
                    Button {
                        MenuSelectionScheduler.afterDismiss {
                            selectedAccountID = account.id
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: account.accountType.icon)
                                .foregroundStyle(account.accountType.color)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name)
                                Text(account.accountType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if selectedAccountID == account.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MovementDetailCategoryMenuContent: View {
    let categories: [MovementCategory]
    let selectedCategoryID: UUID?
    let onSelect: (MovementCategory) -> Void

    var body: some View {
        ForEach(categories, id: \.id) { category in
            Button {
                MenuSelectionScheduler.afterDismiss {
                    onSelect(category)
                }
            } label: {
                Label(
                    category.name,
                    systemImage: category.id == selectedCategoryID ? "checkmark" : category.iconName
                )
            }
        }
    }
}
