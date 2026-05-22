//
//  CategoryAmountBarChart.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import Charts

struct CategoryAmountDatum: Identifiable {
    let id: String
    let name: String
    let iconName: String
    let color: Color
    let amount: Decimal
    let movementCount: Int

    var amountDouble: Double {
        (amount as NSDecimalNumber).doubleValue
    }
}

struct CategoryAmountBarChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let emptyTitle: String
    let emptyDescription: String
    let data: [CategoryAmountDatum]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "chart.bar.fill")
                .font(.headline)
                .foregroundStyle(colorScheme == .dark ? .white : .primary)

            if data.isEmpty {
                FinanceEmptyStateContent(
                    emptyTitle,
                    systemImage: "chart.bar.xaxis",
                    description: Text(emptyDescription)
                )
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Importe", item.amountDouble),
                        y: .value("Categoría", item.name)
                    )
                    .foregroundStyle(item.color.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(item.amount.asCurrency(code: currencyCode))
                            .font(.caption)
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.72) : .secondary)
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
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.88) : .primary)
                    }
                }
                .frame(height: max(230, CGFloat(data.count) * 52))
                .padding(12)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 8) {
                    ForEach(data) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.iconName)
                                .foregroundStyle(item.color)
                                .frame(width: 16)

                            Text(item.name)
                                .font(.subheadline)
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)

                            Spacer()

                            Text("\(item.movementCount)")
                                .font(.caption)
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.70) : .secondary)
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
