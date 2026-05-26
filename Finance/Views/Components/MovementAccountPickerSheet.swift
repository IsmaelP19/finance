//
//  MovementAccountPickerSheet.swift
//  Finance
//
//  Created by OpenCode on 23/05/2026.
//

import SwiftUI
import SwiftData

/// Sección de banco con cuentas; orden congelado al abrir el sheet.
struct MovementAccountPickerBankSection: Identifiable {
    let id: String
    let bankName: String
    let accounts: [BankAccount]
}

/// Selector de cuenta a pantalla completa, agrupado por banco.
struct MovementAccountPickerSheet: View {
    private static let accountLookbackDays = 30

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query private var recentMovements: [Movement]

    @Binding var selection: BankAccount?

    var navigationTitle: String
    var excludingAccountID: UUID?
    var allowsAllAccounts: Bool
    var allAccountsTitle: String

    @State private var draftSelectionID: UUID?
    @State private var draftSelectsAllAccounts = false
    @State private var frozenBankSections: [MovementAccountPickerBankSection] = []
    @State private var hasFrozenLayout = false

    init(
        selection: Binding<BankAccount?>,
        navigationTitle: String = "Cuenta",
        excludingAccountID: UUID? = nil,
        allowsAllAccounts: Bool = false,
        allAccountsTitle: String = "Todas las cuentas"
    ) {
        _selection = selection
        self.navigationTitle = navigationTitle
        self.excludingAccountID = excludingAccountID
        self.allowsAllAccounts = allowsAllAccounts
        self.allAccountsTitle = allAccountsTitle

        let lookbackStart = Calendar.current.date(
            byAdding: .day,
            value: -Self.accountLookbackDays,
            to: Date()
        ) ?? .distantPast

        _recentMovements = Query(filter: #Predicate<Movement> { movement in
            movement.occurredAt >= lookbackStart
        })
    }

    private var lookbackSubtitle: String {
        Self.accountLookbackDays == 14
            ? "Bancos ordenados por uso en las últimas 2 semanas"
            : "Bancos ordenados por uso en el último mes"
    }

    private var activeAccounts: [BankAccount] {
        accounts.filter(\.isActive)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.large) {
                    FinanceGlassSectionHeader(
                        title: "Elige una cuenta",
                        systemImage: "building.columns.fill",
                        subtitle: lookbackSubtitle
                    )

                    if allowsAllAccounts {
                        allAccountsRow
                    }

                    ForEach(frozenBankSections) { section in
                        bankSection(section)
                    }
                }
                .padding(.horizontal, FinanceGlassTokens.Spacing.large)
                .padding(.top, FinanceGlassTokens.Spacing.small)
                .padding(.bottom, FinanceGlassTokens.Spacing.xLarge)
            }
            .financeGlassPageBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Cerrar sin guardar")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        applyDraftSelectionAndDismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canConfirmSelection)
                    .accessibilityLabel("Confirmar cuenta")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: freezeLayoutIfNeeded)
        .onChange(of: accounts.count) { _, _ in
            freezeLayoutIfNeeded()
        }
    }

    private var canConfirmSelection: Bool {
        draftSelectsAllAccounts || draftSelectionID != nil
    }

    private func freezeLayoutIfNeeded() {
        guard !hasFrozenLayout, !activeAccounts.isEmpty else { return }

        let accountUsage = accountUsageCounts(from: recentMovements)
        frozenBankSections = buildFrozenBankSections(accountUsage: accountUsage)

        if allowsAllAccounts, selection == nil {
            draftSelectsAllAccounts = true
            draftSelectionID = nil
        } else {
            draftSelectionID = selection?.id
            draftSelectsAllAccounts = false
        }

        hasFrozenLayout = true
    }

    private func accountUsageCounts(from movements: [Movement]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for movement in movements {
            if let accountID = movement.account?.id {
                counts[accountID, default: 0] += 1
            }
            if let destinationID = movement.destinationAccount?.id {
                counts[destinationID, default: 0] += 1
            }
        }
        return counts
    }

    private func buildFrozenBankSections(accountUsage: [UUID: Int]) -> [MovementAccountPickerBankSection] {
        let eligibleAccounts = activeAccounts.filter { account in
            guard let excludingAccountID else { return true }
            return account.id != excludingAccountID
        }

        let grouped = Dictionary(grouping: eligibleAccounts) { account in
            account.bank?.id.uuidString ?? "no-bank"
        }

        let sections = grouped.compactMap { key, bankAccounts -> (section: MovementAccountPickerBankSection, bankUsage: Int)? in
            guard let first = bankAccounts.first else { return nil }
            let sortedAccounts = bankAccounts.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            let bankUsage = sortedAccounts.reduce(0) { partial, account in
                partial + accountUsage[account.id, default: 0]
            }
            let section = MovementAccountPickerBankSection(
                id: key,
                bankName: first.bankDisplayName,
                accounts: sortedAccounts
            )
            return (section, bankUsage)
        }

        return sections
            .sorted { lhs, rhs in
                if lhs.bankUsage != rhs.bankUsage {
                    return lhs.bankUsage > rhs.bankUsage
                }
                return lhs.section.bankName.localizedCaseInsensitiveCompare(rhs.section.bankName) == .orderedAscending
            }
            .map(\.section)
    }

    private func applyDraftSelectionAndDismiss() {
        if draftSelectsAllAccounts {
            selection = nil
        } else if let draftSelectionID {
            selection = activeAccounts.first { $0.id == draftSelectionID }
        }
        dismiss()
    }

    private var allAccountsRow: some View {
        Button {
            draftSelectsAllAccounts = true
            draftSelectionID = nil
        } label: {
            MovementAccountPickerRow(
                accountName: allAccountsTitle,
                bankName: "Ver movimientos de todas las cuentas",
                systemImage: "building.2",
                tint: .financeAccent,
                isSelected: draftSelectsAllAccounts
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(allAccountsTitle)
        .accessibilityAddTraits(draftSelectsAllAccounts ? .isSelected : [])
    }

    private func bankSection(_ section: MovementAccountPickerBankSection) -> some View {
        VStack(alignment: .leading, spacing: FinanceGlassTokens.Spacing.small) {
            Text(section.bankName.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(section.accounts, id: \.id) { account in
                    Button {
                        draftSelectsAllAccounts = false
                        draftSelectionID = account.id
                    } label: {
                        MovementAccountPickerRow(
                            accountName: account.name,
                            bankName: account.accountType.displayName,
                            systemImage: account.accountType.icon,
                            tint: account.accountType.color,
                            isSelected: !draftSelectsAllAccounts && draftSelectionID == account.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(account.name), \(section.bankName)")
                    .accessibilityAddTraits(
                        !draftSelectsAllAccounts && draftSelectionID == account.id ? .isSelected : []
                    )

                    if account.id != section.accounts.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
            .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.card)
        }
    }
}

private struct MovementAccountPickerRow: View {
    let accountName: String
    let bankName: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tint, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(accountName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(bankName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.financeAccent)
            }
        }
        .padding(.horizontal, FinanceGlassTokens.Spacing.medium)
        .padding(.vertical, FinanceGlassTokens.Spacing.small)
        .contentShape(Rectangle())
    }
}
