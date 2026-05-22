//
//  InvestmentPerformanceCard.swift
//  Finance
//
//  Created by OpenCode on 14/02/2026.
//

import SwiftUI
import Foundation

struct InvestmentPerformanceCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(HideBalances.storageKey) private var hideBalances = false
    let totalInvested: Decimal
    let totalMarketValue: Decimal
    let currencyCode: String

    private var profit: Decimal {
        totalMarketValue - totalInvested
    }

    private var returnPercent: Decimal? {
        guard totalInvested > 0 else { return nil }
        return (profit / totalInvested) * 100
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("Rentabilidad global")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                MetricItem(title: "Invertido", value: totalInvested.masked(hideBalances, code: currencyCode))
                MetricItem(title: "Mercado", value: totalMarketValue.masked(hideBalances, code: currencyCode))
            }

            HStack {
                Text("Resultado")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(profit.masked(hideBalances, code: currencyCode))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(profit.isNegative ? .red : .green)
            }

            if let returnPercent {
                HStack {
                    Text("Rentabilidad")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(returnPercent.asPercentString())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(returnPercent.isNegative ? .red : .green)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .financeGlassColorCard(
            gradient: LinearGradient(
                colors: [
                    Color.green.opacity(colorScheme == .dark ? 0.24 : 0.16),
                    Color.teal.opacity(colorScheme == .dark ? 0.18 : 0.11),
                    Color.mint.opacity(colorScheme == .dark ? 0.12 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            cornerRadius: FinanceGlassTokens.Radius.hero
        )
        .padding(.horizontal)
    }
}

private struct MetricItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Decimal {
    func asPercentString() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "es_ES")
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        let formatted = formatter.string(from: self as NSDecimalNumber) ?? "0,00"
        return "\(formatted)%"
    }
}
