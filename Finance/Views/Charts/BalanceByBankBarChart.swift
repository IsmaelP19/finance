//
//  BalanceByBankBarChart.swift
//  Finance
//
//  Created by Ismael Perez on 11/02/2026.
//

import SwiftUI
import Charts

struct BalanceByBankBarChart: View {
    @Environment(\.colorScheme) private var colorScheme
    let data: [BankBalanceDatum]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Saldo por banco", systemImage: "building.columns.fill")
                .font(.headline)
                .foregroundStyle(colorScheme == .dark ? .white : .primary)

            Chart(data) { item in
                BarMark(
                    x: .value("Saldo", item.amountDouble),
                    y: .value("Banco", item.name)
                )
                .foregroundStyle(item.color.gradient)
                .cornerRadius(5)
                .annotation(position: .trailing) {
                    Text(item.amount.asCurrency())
                        .font(.caption)
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.secondary.opacity(0.22))
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisTick()
                    AxisValueLabel()
                        .font(.caption)
                        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.85) : .primary)
                }
            }
            .frame(height: max(230, CGFloat(data.count) * 52))
            .padding(12)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 8) {
                ForEach(data) { item in
                    HStack {
                        Image(systemName: item.iconName)
                            .foregroundStyle(item.color)
                            .frame(width: 16)
                        Text(item.name)
                            .font(.subheadline)
                            .foregroundStyle(colorScheme == .dark ? .white : .primary)
                        Spacer()
                        Text("\(item.count) \(item.count == 1 ? "cuenta" : "cuentas")")
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .secondary)
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
