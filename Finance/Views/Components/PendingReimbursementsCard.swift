import SwiftUI

struct PendingReimbursementsCard: View {
    let totalPending: Decimal
    let movementCount: Int
    let currencyCode: String
    let hideBalances: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.uturn.left.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Saldo pendiente")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)

                    Text(totalPending.masked(hideBalances, code: currencyCode))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)

                    Text(movementCount == 1 ? "1 movimiento pendiente de reembolso" : "\(movementCount) movimientos pendientes de reembolso")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Text("\(movementCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.20))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.44, blue: 0.41), Color(red: 0.08, green: 0.30, blue: 0.54)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
