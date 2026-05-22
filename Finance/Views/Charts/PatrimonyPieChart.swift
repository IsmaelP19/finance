//
//  PatrimonyPieChart.swift
//  Finance
//
//  Created by Ismael Perez on 11/02/2026.
//

import SwiftUI
import Charts

struct PatrimonyPieChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let data: [TypeBalanceDatum]
    let currencyCode: String

    private var total: Double {
        data.reduce(0) { $0 + $1.amountDouble }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chartHeader

            if data.isEmpty || total <= 0 {
                FinanceEmptyStateContent(
                    "Sin valores positivos",
                    systemImage: "chart.pie",
                    description: Text("El grafico circular necesita saldos positivos.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 18) {
                        donutChart
                            .frame(width: 148, height: 148)

                        compactLegend
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        donutChart
                            .frame(maxWidth: .infinity)
                            .frame(height: 164)
                        compactLegend
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

    private var chartHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Patrimonio por tipo", systemImage: "chart.pie.fill")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(.primary.opacity(0.78))

                Text("Distribución de saldos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(data.count) \(data.count == 1 ? "tipo" : "tipos")")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var donutChart: some View {
        Chart(data) { item in
            SectorMark(
                angle: .value("Saldo", item.amountDouble),
                innerRadius: .ratio(0.62),
                angularInset: 1.8
            )
            .foregroundStyle(item.type.color.gradient)
            .cornerRadius(5)
        }
        .chartLegend(.hidden)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plotFrame = proxy.plotFrame {
                    let frame = geo[plotFrame]
                    VStack(spacing: 3) {
                        Text("Total")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(Decimal(total).asCurrency(code: currencyCode))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }
                    .frame(width: min(frame.width * 0.54, 88))
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .accessibilityLabel("Gráfico de patrimonio por tipo")
    }

    private var compactLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(data) { item in
                HStack(spacing: 9) {
                    Circle()
                        .fill(item.type.color)
                        .frame(width: 9, height: 9)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.type.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("\(Int((item.amountDouble / total) * 100))% · \(item.amount.asCurrency(code: currencyCode))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
