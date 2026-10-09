import SwiftUI

private struct PendingReimbursementSelection: Identifiable {
    let id: UUID
    let movement: Movement
}

private struct PendingReimbursementRow: View {
    @AppStorage(HideBalances.storageKey) private var hideBalances = false

    let movement: Movement
    let pendingAmount: Decimal
    let currencyCode: String

    private var iconName: String {
        movement.category?.iconName ?? "person.2.fill"
    }

    private var iconColor: Color {
        movement.category?.color ?? .orange
    }

    private var accountDisplayText: String? {
        guard let account = movement.account else { return nil }
        guard let bankName = account.bank?.name, !bankName.isEmpty else { return account.name }
        return "\(account.name) (\(bankName))"
    }

    var body: some View {
        HStack(spacing: 14) {
            if movement.category?.emoji != nil {
                CategoryIconView(iconRaw: movement.category?.iconRaw, color: iconColor, size: 46)
            } else {
                FinanceGlassIconBadge(systemName: iconName, tint: iconColor, size: 46)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(movement.concept)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(movement.occurredAt.asSpanishShortDate())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let accountDisplayText {
                    Text(accountDisplayText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(pendingAmount.masked(hideBalances, code: currencyCode))
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.orange)
                    .lineLimit(1)

                Text("Pendiente")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .financeElevatedRow()
        .padding(.vertical, 2)
    }
}

struct PendingReimbursementsListView: View {
    @Environment(\.dismiss) private var dismiss

    let movements: [Movement]
    let recoveredReimbursementAmountsByExpenseID: [UUID: Decimal]
    let currencyCode: String

    @State private var selectedMovement: PendingReimbursementSelection?

    private func makeEntries() -> [(movement: Movement, pendingAmount: Decimal)] {
        movements
            .map { movement in
                (
                    movement: movement,
                    pendingAmount: movement.pendingReimbursementAmount(
                        recoveredAmount: recoveredReimbursementAmountsByExpenseID[movement.id] ?? 0
                    )
                )
            }
            .filter { $0.pendingAmount > 0 }
            .sorted { lhs, rhs in
                if lhs.pendingAmount == rhs.pendingAmount {
                    return lhs.movement.occurredAt > rhs.movement.occurredAt
                }

                return lhs.pendingAmount > rhs.pendingAmount
            }
    }

    var body: some View {
        let entries = makeEntries()
        let totalPendingAmount = entries.reduce(Decimal(0)) { $0 + $1.pendingAmount }

        NavigationStack {
            List {
                if entries.isEmpty {
                    FinanceEmptyStateContent(
                        "Sin saldo pendiente",
                        systemImage: "checkmark.circle",
                        description: Text("No hay movimientos compartidos con reembolsos pendientes.")
                    )
                    .financeGlassClearListRow()
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Total por recibir", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            Text(totalPendingAmount.asCurrency(code: currencyCode))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text(entries.count == 1 ? "1 movimiento con cobro pendiente" : "\(entries.count) movimientos con cobro pendiente")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                            .financeGlassCard()
                            .financeGlassClearListRow()
                    }

                    Section {
                        ForEach(entries, id: \.movement.id) { entry in
                            Button {
                                selectedMovement = PendingReimbursementSelection(id: entry.movement.id, movement: entry.movement)
                            } label: {
                                PendingReimbursementRow(
                                    movement: entry.movement,
                                    pendingAmount: entry.pendingAmount,
                                    currencyCode: currencyCode
                                )
                            }
                            .buttonStyle(.plain)
                            .financeGlassClearListRow()
                        }
                    } header: {
                        FinanceGlassSectionHeader(title: "Movimientos compartidos", systemImage: "person.2.fill", subtitle: "Toca para ver el detalle y registrar reembolso")
                    }
                }
            }
            .navigationTitle("Saldo pendiente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
            .financeGlassListContainer()
        }
        .sheet(item: $selectedMovement) { selection in
            MovementDetailView(
                movement: selection.movement,
                currencyCode: currencyCode
            )
        }
    }
}
