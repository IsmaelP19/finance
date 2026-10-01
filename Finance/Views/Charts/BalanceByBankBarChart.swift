//
//  BalanceByBankBarChart.swift
//  Finance
//
//  Created by Ismael Perez on 11/02/2026.
//

import SwiftUI

struct BalanceByBankBarChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let data: [BankBalanceDatum]
    let currencyCode: String

    private struct PreparedData {
        let sorted: [BankBalanceDatum]
        let maxMagnitude: Double
        let hasNegatives: Bool
    }

    private func makePreparedData() -> PreparedData {
        var maxMagnitude = 0.0
        var hasNegatives = false
        for datum in data {
            maxMagnitude = max(maxMagnitude, abs(datum.amountDouble))
            hasNegatives = hasNegatives || datum.amountDouble < 0
        }

        return PreparedData(
            sorted: data.sorted { abs($0.amountDouble) > abs($1.amountDouble) },
            maxMagnitude: maxMagnitude,
            hasNegatives: hasNegatives
        )
    }

    var body: some View {
        let prepared = makePreparedData()

        VStack(alignment: .leading, spacing: 16) {
            chartHeader(hasNegatives: prepared.hasNegatives)

            if data.isEmpty {
                FinanceEmptyStateContent(
                    "Sin bancos",
                    systemImage: "building.columns",
                    description: Text("Añade cuentas para ver el saldo por banco.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(Array(prepared.sorted.enumerated()), id: \.element.id) { index, item in
                        BankBalanceRow(
                            item: item,
                            currencyCode: currencyCode,
                            maxMagnitude: prepared.maxMagnitude,
                            rank: index + 1
                        )
                    }
                }
            }
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func chartHeader(hasNegatives: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Saldo por banco", systemImage: "building.columns.fill")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle((colorScheme == .dark ? Color.white : Color.primary).opacity(0.78))

                Text("Ranking de tus entidades bancarias según saldo acumulado")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(data.count) \(data.count == 1 ? "banco" : "bancos")")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06), in: Capsule())

            if hasNegatives {
                Text("Incluye negativos")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.10), in: Capsule())
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

private struct BankBalanceRow: View {
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    let item: BankBalanceDatum
    let currencyCode: String
    let maxMagnitude: Double
    let rank: Int

    private var progress: Double {
        guard maxMagnitude > 0 else { return 0 }
        return min(abs(item.amountDouble) / maxMagnitude, 1)
    }

    private var isZero: Bool {
        item.amount == 0
    }

    private var isNegative: Bool {
        item.amount < 0
    }

    private var trackTint: Color {
        Color.primary.opacity(0.09)
    }

    private var fillTint: Color {
        isNegative ? .red : item.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text("#\(rank)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())

                HStack(spacing: 12) {
                    Image(systemName: item.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.color)
                        .frame(width: 34, height: 34)
                        .background(item.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("\(item.count) \(item.count == 1 ? "cuenta" : "cuentas")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(item.amount.masked(hideBalances, code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isNegative ? .red : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            GeometryReader { geometry in
                let barWidth = isZero ? 0 : max(8, geometry.size.width * progress)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackTint)

                    if !isZero {
                        Capsule()
                            .fill(fillTint)
                            .frame(width: barWidth)
                    }
                }
            }
            .frame(height: 7)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
