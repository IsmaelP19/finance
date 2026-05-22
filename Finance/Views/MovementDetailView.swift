//
//  MovementDetailView.swift
//  Finance
//
//  Created by OpenCode on 06/03/2026.
//

import SwiftUI
import SwiftData

private struct RelatedMovementSelection: Identifiable {
    let id: UUID
    let movement: Movement
}

struct MovementDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]

    let movement: Movement
    let currencyCode: String

    @State private var showingQuickReimbursementSheet = false
    @State private var showingEditSheet = false
    @State private var relatedMovementToView: RelatedMovementSelection?
    @State private var hasAnimatedIn = false
    @State private var showingArchivedAccountAlert = false

    private var linkedReimbursements: [Movement] {
        guard movement.type == .expense else { return [] }
        return movements
            .filter { $0.type == .income && $0.reimbursementForId == movement.id }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var reimbursementSourceExpense: Movement? {
        guard movement.isReimbursementIncome, let reimbursementForId = movement.reimbursementForId else { return nil }
        return movements.first(where: { $0.id == reimbursementForId && $0.type == .expense })
    }

    private var displayAmount: Decimal {
        movement.type == .transfer ? movement.amount : movement.signedAmount
    }

    private var amountColor: Color {
        movement.type.color
    }

    private var movementIconName: String {
        movement.category?.iconName ?? movement.type.icon
    }

    private var movementIconColor: Color {
        movement.category?.color ?? movement.type.color
    }

    private var accountName: String {
        movement.account?.name ?? "Cuenta eliminada"
    }

    private var accountBankName: String {
        movement.account?.bankDisplayName ?? "Cuenta eliminada"
    }

    private var expectedReimbursement: Decimal {
        movement.expectedReimbursementAmount
    }

    private var recoveredReimbursement: Decimal {
        linkedReimbursements.reduce(Decimal(0)) { $0 + $1.amount }
    }

    private var pendingReimbursement: Decimal {
        movement.pendingReimbursementAmount(recoveredAmount: recoveredReimbursement)
    }

    private var reimbursementOverage: Decimal {
        movement.reimbursementOverageAmount(recoveredAmount: recoveredReimbursement)
    }

    private var isFullyRecovered: Bool {
        expectedReimbursement > 0 && recoveredReimbursement >= expectedReimbursement
    }

    private var shouldShowReimbursementTracking: Bool {
        guard expectedReimbursement > 0 else { return false }
        return movement.personalAmount != 0 || !linkedReimbursements.isEmpty
    }

    private var activeAccounts: [BankAccount] {
        accounts.filter(\.isActive)
    }

    private var touchesArchivedAccount: Bool {
        if movement.account?.isArchived == true || movement.destinationAccount?.isArchived == true {
            return true
        }

        guard movement.type == .income, let reimbursementForId = movement.reimbursementForId else { return false }
        return movements.first(where: { $0.id == reimbursementForId })?.account?.isArchived == true
    }

    private var quickReimbursementAccount: BankAccount? {
        activeAccounts.first { account in
            guard movement.account?.isArchived == true else { return true }
            guard let expenseAccountID = movement.account?.id else { return true }
            return account.id != expenseAccountID
        }
    }

    private var statusBadge: (title: String, color: Color) {
        if movement.type == .expense, expectedReimbursement > 0 {
            return isFullyRecovered
                ? ("Reembolso completado", .green)
                : ("Reembolso pendiente", .orange)
        }
        if movement.isReimbursementIncome {
            return ("Reembolso recibido", .green)
        }
        return ("Registrado", .secondary)
    }

    private var isExcludedFromMyExpenses: Binding<Bool> {
        Binding(
            get: { movement.type == .expense && movement.personalAmount == 0 },
            set: { enabled in
                guard movement.type == .expense else { return }
                movement.personalAmount = enabled ? 0 : nil
                movement.updatedAt = Date()
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                        .revolutReveal(index: 0, shown: hasAnimatedIn)

                    detailsCard
                        .revolutReveal(index: 1, shown: hasAnimatedIn)

                    if movement.type != .transfer {
                        accountCard
                            .revolutReveal(index: 2, shown: hasAnimatedIn)
                    }

                    if movement.type == .transfer {
                        transferCard
                            .revolutReveal(index: 2, shown: hasAnimatedIn)
                    }

                    if movement.type == .expense {
                        ownershipCard
                            .revolutReveal(index: 3, shown: hasAnimatedIn)
                    }

                    if movement.isReimbursementIncome {
                        reimbursementSourceCard
                            .revolutReveal(index: 4, shown: hasAnimatedIn)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .financeGlassPageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .financeToolbarIconStyle()
                    }
                    .accessibilityLabel("Cerrar")
                }

                if !touchesArchivedAccount {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .financeToolbarIconStyle()
                        }
                        .accessibilityLabel("Editar")
                    }
                }
            }
            .sheet(isPresented: $showingQuickReimbursementSheet) {
                AddMovementView(
                    preselectedType: .income,
                    preselectedAccountID: quickReimbursementAccount?.id,
                    prefilledConcept: "Reembolso: \(movement.concept)",
                    linkedReimbursementExpenseID: movement.id
                )
            }
            .sheet(isPresented: $showingEditSheet) {
                AddMovementView(movementToEdit: movement)
            }
            .sheet(item: $relatedMovementToView) { selection in
                MovementDetailView(
                    movement: selection.movement,
                    currencyCode: currencyCode
                )
            }
            .alert("No se puede registrar el reembolso", isPresented: $showingArchivedAccountAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text("Necesitas otra cuenta activa distinta para registrar el ingreso del reembolso.")
            }
            .onAppear {
                guard !hasAnimatedIn else { return }
                hasAnimatedIn = true
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            HStack {
                Label(statusBadge.title.uppercased(), systemImage: "circle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusBadge.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusBadge.color.opacity(0.14))
                    .clipShape(Capsule())

                Spacer()
            }

            Circle()
                .fill(movementIconColor.opacity(0.2))
                .frame(width: 82, height: 82)
                .overlay {
                    Image(systemName: movementIconName)
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(movementIconColor)
                }

            Text(movement.concept)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Text(displayAmount.asCurrency(code: currencyCode))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(amountColor)

            Text(movement.occurredAt.asSpanishDateTime())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(
            LinearGradient(
                colors: heroGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.25))
                .blur(radius: 30)
                .offset(x: 100, y: -70)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.65), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 20, x: 0, y: 12)
    }

    private var detailsCard: some View {
        detailCard {
            sectionTitle("Detalles")

            if movement.type != .transfer {
                HStack {
                    Text("Categoría")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 10)

                    Menu {
                        ForEach(categories, id: \.id) { category in
                            Button {
                                movement.category = category
                                movement.updatedAt = Date()
                            } label: {
                                Label(category.name, systemImage: category.iconName)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            CategoryChipView(
                                name: movement.category?.name ?? "Sin categoría",
                                iconName: movement.category?.iconName ?? "tag",
                                color: movement.category?.color ?? .secondary
                            )
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            infoRow(title: "Tipo", value: movement.type.displayName)

            if !movement.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notas")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(movement.notes)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var accountCard: some View {
        detailCard {
            sectionTitle("Cuenta")

            infoRow(title: "Cuenta", value: accountName)
            infoRow(title: "Banco", value: accountBankName)

            if let resultingBalance = movement.resultingBalance {
                infoRow(title: "Saldo tras", value: resultingBalance.asCurrency(code: currencyCode))
            }
        }
    }

    private var transferCard: some View {
        detailCard {
            sectionTitle("Transferencia")

            infoRow(title: "Desde", value: movement.account?.name ?? "Cuenta eliminada")
            infoRow(title: "Hacia", value: movement.destinationAccount?.name ?? "Cuenta eliminada")
            infoRow(title: "Importe", value: movement.amount.asCurrency(code: currencyCode), valueColor: .blue)
        }
    }

    private var ownershipCard: some View {
        detailCard {
            sectionTitle("Mis gastos")

            Toggle("Quitar de mis gastos", isOn: isExcludedFromMyExpenses)
                .font(.subheadline)

            Text("Cuando está activado, este gasto no contará en estadísticas ni presupuestos.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let myPart = movement.normalizedPersonalAmount {
                infoRow(title: "Mi gasto", value: myPart.asCurrency(code: currencyCode))
            }

            if shouldShowReimbursementTracking {
                infoRow(title: "Reembolso esperado", value: expectedReimbursement.asCurrency(code: currencyCode), valueColor: .orange)
                infoRow(title: "Pendiente", value: pendingReimbursement.asCurrency(code: currencyCode), valueColor: pendingReimbursement == 0 ? .green : .secondary)

                ProgressView(
                    value: min((recoveredReimbursement as NSDecimalNumber).doubleValue, (expectedReimbursement as NSDecimalNumber).doubleValue),
                    total: max((expectedReimbursement as NSDecimalNumber).doubleValue, 0.0001)
                )
                .tint(isFullyRecovered ? .green : .blue)

                Text("Recuperado: \(recoveredReimbursement.asCurrency(code: currencyCode)) de \(expectedReimbursement.asCurrency(code: currencyCode))")
                    .font(.caption)
                    .foregroundStyle(isFullyRecovered ? .green : .secondary)

                if reimbursementOverage > 0 {
                    Text("Extra recibido: \(reimbursementOverage.asCurrency(code: currencyCode))")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                actionButton(
                    title: "Registrar reembolso",
                    systemImage: "plus.circle.fill",
                    tint: .blue
                ) {
                    if quickReimbursementAccount == nil {
                        showingArchivedAccountAlert = true
                    } else {
                        showingQuickReimbursementSheet = true
                    }
                }
            }

            if !linkedReimbursements.isEmpty {
                VStack(spacing: 8) {
                    ForEach(linkedReimbursements, id: \.id) { reimbursement in
                        Button {
                            relatedMovementToView = RelatedMovementSelection(
                                id: reimbursement.id,
                                movement: reimbursement
                            )
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reimbursement.concept)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Text(reimbursement.occurredAt.asSpanishShortDate())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(reimbursement.amount.asCurrency(code: currencyCode))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.green)
                            }
                            .padding(10)
                            .background(Color.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var reimbursementSourceCard: some View {
        detailCard {
            sectionTitle("Reembolso de")

            if let reimbursementSourceExpense {
                Button {
                    relatedMovementToView = RelatedMovementSelection(
                        id: reimbursementSourceExpense.id,
                        movement: reimbursementSourceExpense
                    )
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reimbursementSourceExpense.concept)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)

                            Text(reimbursementSourceExpense.occurredAt.asSpanishShortDate())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(reimbursementSourceExpense.amount.asCurrency(code: currencyCode))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                Text("Este reembolso está vinculado a un gasto que ya no se encuentra.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var heroGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.23, green: 0.24, blue: 0.28),
                Color(red: 0.09, green: 0.10, blue: 0.13)
            ]
        }

        return [
            Color(red: 0.94, green: 0.96, blue: 1.0),
            Color.white
        ]
    }

    private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeGlassCard(cornerRadius: FinanceGlassTokens.Radius.card)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .tracking(0.8)
    }

    private func infoRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 10)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private func actionButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .financeGlassSecondaryAction(tint: tint)
    }

}

private extension View {
    func revolutReveal(index: Int, shown: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : CGFloat(16 + (index * 3)))
            .animation(.spring(response: 0.42, dampingFraction: 0.88).delay(Double(index) * 0.035), value: shown)
    }
}
