//
//  AccountSelectionMenu.swift
//  Finance
//
//  Created by OpenCode on 28/04/2026.
//

import SwiftUI

private struct AccountSelectionBankGroup: Identifiable {
    let id: String
    let bankName: String
    let accounts: [BankAccount]
}

/// Selector reutilizable de cuentas con agrupación por banco e iconografía de tipo de cuenta.
struct AccountSelectionMenu: View {
    let title: String
    let accounts: [BankAccount]
    @Binding var selectedAccountID: UUID?
    let allowsAllAccounts: Bool
    let allAccountsTitle: String
    let placeholder: String
    let leadingSystemImage: String
    let leadingTint: Color
    let accessibilityLabel: String

    init(
        title: String = "Cuenta",
        accounts: [BankAccount],
        selectedAccountID: Binding<UUID?>,
        allowsAllAccounts: Bool = false,
        allAccountsTitle: String = "Todas las cuentas",
        placeholder: String = "Selecciona una cuenta",
        leadingSystemImage: String = "building.columns.fill",
        leadingTint: Color = .financeAccent,
        accessibilityLabel: String = "Seleccionar cuenta"
    ) {
        self.title = title
        self.accounts = accounts
        self._selectedAccountID = selectedAccountID
        self.allowsAllAccounts = allowsAllAccounts
        self.allAccountsTitle = allAccountsTitle
        self.placeholder = placeholder
        self.leadingSystemImage = leadingSystemImage
        self.leadingTint = leadingTint
        self.accessibilityLabel = accessibilityLabel
    }

    private var sortedAccounts: [BankAccount] {
        accounts.sorted { lhs, rhs in
            let bankComparison = lhs.bankDisplayName.localizedCaseInsensitiveCompare(rhs.bankDisplayName)
            if bankComparison != .orderedSame {
                return bankComparison == .orderedAscending
            }

            let accountComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if accountComparison != .orderedSame {
                return accountComparison == .orderedAscending
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var groupedAccountsByBank: [AccountSelectionBankGroup] {
        let grouped = Dictionary(grouping: sortedAccounts) { account in
            account.bank?.id.uuidString ?? "no-bank"
        }

        return grouped
            .compactMap { key, groupedAccounts in
                guard let first = groupedAccounts.first else { return nil }
                return AccountSelectionBankGroup(id: key, bankName: first.bankDisplayName, accounts: groupedAccounts)
            }
            .sorted { lhs, rhs in
                lhs.bankName.localizedCaseInsensitiveCompare(rhs.bankName) == .orderedAscending
            }
    }

    private var selectedAccount: BankAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    private var selectedTitle: String {
        if let selectedAccount {
            return selectedAccount.name
        }

        return allowsAllAccounts ? allAccountsTitle.replacingOccurrences(of: " las cuentas", with: "") : placeholder
    }

    private var labelIcon: String {
        selectedAccount?.accountType.icon ?? leadingSystemImage
    }

    private var labelTint: Color {
        selectedAccount?.accountType.color ?? leadingTint
    }

    var body: some View {
        Menu {
            if allowsAllAccounts {
                Button {
                    selectedAccountID = nil
                } label: {
                    Label(allAccountsTitle, systemImage: selectedAccountID == nil ? "checkmark" : "building.2")
                }
            }

            ForEach(groupedAccountsByBank) { bankGroup in
                Section(bankGroup.bankName) {
                    ForEach(bankGroup.accounts, id: \.id) { account in
                        Button {
                            selectedAccountID = account.id
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
        } label: {
            HStack(spacing: 10) {
                Image(systemName: labelIcon)
                    .font(.footnote.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(labelTint)
                    .frame(width: 28, height: 28)
                    .background(labelTint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(selectedTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.34), lineWidth: 0.75)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selectedTitle)
    }
}
