import SwiftUI

struct RecurringMonthlySummaryCard: View {
    let monthDate: Date
    let expenseTotal: Decimal
    let incomeTotal: Decimal
    let occurrenceCount: Int
    let currencyCode: String
    let hideBalances: Bool

    private var monthTitle: String {
        monthDate.formatted(
            .dateTime
                .month(.wide)
                .year()
                .locale(Locale(identifier: "es_ES"))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(monthTitle.capitalized)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)

                Spacer()

                Text(occurrenceCount == 1 ? "1 cargo" : "\(occurrenceCount) cargos")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.16))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(expenseTotal.masked(hideBalances, code: currencyCode))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(occurrenceCount == 0 ? "No hay gastos recurrentes previstos en este mes" : "Total previsto en gastos recurrentes del mes visible")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.82))
            }

            HStack(spacing: 10) {
                recurringMetricCard(
                    title: "Gastos",
                    value: expenseTotal.masked(hideBalances, code: currencyCode),
                    systemImage: "arrow.up.circle.fill"
                )

                recurringMetricCard(
                    title: "Ingresos",
                    value: incomeTotal.masked(hideBalances, code: currencyCode),
                    systemImage: "arrow.down.circle.fill"
                )
            }
        }
        .financeGlassColorCard(
            gradient: LinearGradient(
                colors: [Color(red: 0.16, green: 0.32, blue: 0.62), Color(red: 0.08, green: 0.52, blue: 0.60)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            cornerRadius: 28
        )
    }

    @ViewBuilder
    private func recurringMetricCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
