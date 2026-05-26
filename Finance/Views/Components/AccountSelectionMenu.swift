//
//  AccountSelectionMenu.swift
//  Finance
//
//  Created by OpenCode on 28/04/2026.
//

import SwiftUI

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

    @State private var isShowingAccountPicker = false
    @State private var selectedTitleLabel: String = ""
    @State private var selectedBankLabel: String = ""
    @State private var labelIcon: String = "building.columns.fill"
    @State private var labelTint: Color = .financeAccent

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
        _labelIcon = State(initialValue: leadingSystemImage)
        _labelTint = State(initialValue: leadingTint)
    }

    private var selectedAccount: BankAccount? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    var body: some View {
        Button {
            isShowingAccountPicker = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                MovementAccountPickerPill(
                    accountName: selectedTitleLabel,
                    bankName: selectedBankLabel,
                    systemImage: labelIcon,
                    tint: labelTint
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(selectedTitleLabel), \(selectedBankLabel)")
        .accessibilityHint("Abre el selector de cuenta")
        .sheet(isPresented: $isShowingAccountPicker) {
            MovementAccountPickerSheet(
                selection: Binding(
                    get: { selectedAccount },
                    set: { newAccount in
                        selectedAccountID = newAccount?.id
                    }
                ),
                navigationTitle: title,
                allowsAllAccounts: allowsAllAccounts,
                allAccountsTitle: allAccountsTitle
            )
        }
        .onAppear(perform: syncLabels)
        .onChange(of: selectedAccountID) { _, _ in
            syncLabels()
        }
    }

    private func syncLabels() {
        if let selectedAccount {
            selectedTitleLabel = selectedAccount.name
            selectedBankLabel = selectedAccount.bankDisplayName
            labelIcon = selectedAccount.accountType.icon
            labelTint = selectedAccount.accountType.color
            return
        }

        if allowsAllAccounts {
            selectedTitleLabel = allAccountsTitle.replacingOccurrences(of: " las cuentas", with: "")
            selectedBankLabel = "Todas las cuentas activas"
            labelIcon = leadingSystemImage
            labelTint = leadingTint
            return
        }

        selectedTitleLabel = placeholder
        selectedBankLabel = "Pulsa para elegir"
        labelIcon = leadingSystemImage
        labelTint = leadingTint
    }
}
