import SwiftUI

struct RecurringMovementRowContent: View {
    let type: MovementType
    let concept: String
    let categoryName: String?
    let categoryIconName: String?
    let categoryColor: Color?
    let accountName: String
    let amountText: String
    let statusTitle: String
    let statusColor: Color
    let dueDateText: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(type.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(concept)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let categoryName, let categoryIconName, let categoryColor {
                    HStack(spacing: 6) {
                        CategoryChipView(
                            name: categoryName,
                            iconName: categoryIconName,
                            color: categoryColor
                        )
                    }
                }

                Text(accountName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(type == .expense ? .red : .green)

                Text(statusTitle)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())

                Text(dueDateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
