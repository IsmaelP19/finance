//
//  CategoryPieChart.swift
//  Finance
//
//  Created by OpenCode on 12/02/2026.
//

import SwiftUI
import Charts

struct CategoryPieChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let emptyTitle: String
    let emptyDescription: String
    let data: [CategoryAmountDatum]
    let currencyCode: String

    private var total: Double {
        data.reduce(0) { $0 + $1.amountDouble }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "chart.pie.fill")
                .font(.headline)
                .foregroundStyle(colorScheme == .dark ? .white : .primary)

            if data.isEmpty || total <= 0 {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "chart.pie",
                    description: Text(emptyDescription)
                )
            } else {
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Importe", item.amountDouble),
                        innerRadius: .ratio(0.56),
                        angularInset: 1.6
                    )
                    .foregroundStyle(item.color.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 230)
                .chartLegend(.hidden)
                .chartBackground { proxy in
                    GeometryReader { geo in
                        let frame = geo[proxy.plotFrame!]
                        VStack(spacing: 3) {
                            Text("Total")
                                .font(.caption)
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .secondary)
                            Text(Decimal(total).asCurrency(code: currencyCode))
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
                            Image(systemName: item.iconName)
                                .foregroundStyle(item.color)
                                .frame(width: 14)

                            Text(item.name)
                                .font(.subheadline)
                                .foregroundStyle(colorScheme == .dark ? .white : .primary)

                            Spacer()

                            Text("\(Int((item.amountDouble / total) * 100))%")
                                .font(.caption)
                                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.65) : .secondary)

                            Text(item.amount.asCurrency(code: currencyCode))
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
