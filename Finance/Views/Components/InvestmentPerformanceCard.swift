//
//  InvestmentPerformanceCard.swift
//  Finance
//
//  Created by OpenCode on 14/02/2026.
//

import SwiftUI
import Foundation

struct InvestmentPerformanceCard: View {
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
                .foregroundStyle(.white.opacity(0.85))

            HStack {
                MetricItem(title: "Invertido", value: totalInvested.masked(hideBalances, code: currencyCode))
                MetricItem(title: "Mercado", value: totalMarketValue.masked(hideBalances, code: currencyCode))
            }

            HStack {
                Text("Resultado")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

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
                        .foregroundStyle(.white.opacity(0.7))

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
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.25, blue: 0.17),
                    Color(red: 0.06, green: 0.20, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
                .foregroundStyle(.white.opacity(0.7))

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
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
