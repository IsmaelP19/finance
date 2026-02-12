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

    private var total: Double {
        data.reduce(0) { $0 + $1.amountDouble }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Patrimonio por tipo", systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            if data.isEmpty || total <= 0 {
                ContentUnavailableView(
                    "Sin valores positivos",
                    systemImage: "chart.pie",
                    description: Text("El grafico circular necesita saldos positivos.")
                )
            } else {
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Saldo", item.amountDouble),
                        innerRadius: .ratio(0.56),
                        angularInset: 1.6
                    )
                    .foregroundStyle(item.type.color.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 220)
                .chartLegend(.hidden)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        let frame = geo[proxy.plotFrame!]
                        VStack(spacing: 3) {
                            Text("Total")
                                .font(.caption)
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .secondary)
                            Text(Decimal(total).asCurrency())
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                                .minimumScaleFactor(0.8)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
                .padding(12)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 8) {
                    ForEach(data) { item in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(item.type.color)
                                .frame(width: 10, height: 10)

                            Text(item.type.displayName)
                                .font(.subheadline)
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)

                            Spacer()

                            Text("\(Int((item.amountDouble / total) * 100))%")
                                .font(.subheadline)
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .secondary)

                            Text(item.amount.asCurrency())
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.blue.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 8)
    }
}
