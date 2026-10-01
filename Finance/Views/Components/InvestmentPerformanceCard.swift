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
    let maximumReturnPercent: InvestmentPeakMetric?
    let currencyCode: String

    private struct PreparedMetrics {
        let profit: Decimal
        let returnPercent: Decimal?
    }

    private var preparedMetrics: PreparedMetrics {
        let profit = totalMarketValue - totalInvested
        let returnPercent = totalInvested > 0 ? (profit / totalInvested) * 100 : nil
        return PreparedMetrics(profit: profit, returnPercent: returnPercent)
    }

    var body: some View {
        let metrics = preparedMetrics

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 34, height: 34)
                    .background(Color.green.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Rentabilidad global")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Resumen de tus inversiones")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                InvestmentMetricTile(
                    title: "Invertido",
                    value: totalInvested.masked(hideBalances, code: currencyCode),
                    systemImage: "tray.and.arrow.down.fill",
                    tint: .purple
                )

                InvestmentMetricTile(
                    title: "Mercado",
                    value: totalMarketValue.masked(hideBalances, code: currencyCode),
                    systemImage: "chart.line.uptrend.xyaxis",
                    tint: .blue
                )
            }

            HStack(spacing: 10) {
                InvestmentMetricTile(
                    title: "Resultado",
                    value: metrics.profit.masked(hideBalances, code: currencyCode),
                    systemImage: metrics.profit.isNegative ? "arrow.down.right" : "arrow.up.right",
                    tint: metrics.profit.isNegative ? .red : .green,
                    valueColor: metrics.profit.isNegative ? .red : .green
                )

                InvestmentMetricTile(
                    title: "Rentabilidad %",
                    value: metrics.returnPercent.map { $0.asPercentString() } ?? "—",
                    systemImage: "percent",
                    tint: (metrics.returnPercent ?? 0).isNegative ? .red : .green,
                    valueColor: (metrics.returnPercent ?? 0).isNegative ? .red : .green
                )
            }

            if let maximumReturnPercent {
                InvestmentMetricTile(
                    title: "Máxima rentabilidad",
                    value: hideBalances ? "••••" : maximumReturnPercent.value.asPercentString(),
                    systemImage: "percent",
                    tint: maximumReturnPercent.value.isNegative ? .red : .green,
                    valueColor: maximumReturnPercent.value.isNegative ? .red : .green,
                    secondarySubtitle: maximumReturnPercent.monetaryValue.map {
                        "Equivale a \($0.masked(hideBalances, code: currencyCode))"
                    },
                    subtitle: "Registrada el \(maximumReturnPercent.date.asSpanishShortDate())",
                    emphasized: true
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct InvestmentMetricTile: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let valueColor: Color
    let secondarySubtitle: String?
    let subtitle: String?
    let emphasized: Bool

    init(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        valueColor: Color? = nil,
        secondarySubtitle: String? = nil,
        subtitle: String? = nil,
        emphasized: Bool = false
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tint = tint
        self.valueColor = valueColor ?? .primary
        self.secondarySubtitle = secondarySubtitle
        self.subtitle = subtitle
        self.emphasized = emphasized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(value)
                    .font(emphasized ? .title2.weight(.bold) : .headline.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if let secondarySubtitle {
                    Text(secondarySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            tint.opacity(colorScheme == .dark ? (emphasized ? 0.14 : 0.10) : (emphasized ? 0.10 : 0.06)),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    tint.opacity(colorScheme == .dark ? (emphasized ? 0.36 : 0.20) : (emphasized ? 0.28 : 0.14)),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
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
