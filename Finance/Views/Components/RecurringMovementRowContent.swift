import SwiftUI

struct MovementRowBadge: Identifiable, Hashable {
    let id: String
    let name: String
    let iconName: String
    let color: Color
}

struct MovementTrailingPill {
    let title: String
    let color: Color
}

struct RecurringMovementRowContent: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let type: MovementType
    let concept: String
    let badges: [MovementRowBadge]
    let detailLines: [String]
    let amountText: String
    let amountColor: Color
    let trailingInfoText: String?
    let trailingPill: MovementTrailingPill?
    let dateText: String

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    init(
        type: MovementType,
        concept: String,
        badges: [MovementRowBadge] = [],
        detailLines: [String],
        amountText: String,
        amountColor: Color? = nil,
        trailingInfoText: String? = nil,
        trailingPill: MovementTrailingPill? = nil,
        dateText: String
    ) {
        self.type = type
        self.concept = concept
        self.badges = badges
        self.detailLines = detailLines
        self.amountText = amountText
        self.amountColor = amountColor ?? {
            switch type {
            case .expense:
                return .red
            case .income:
                return .green
            case .transfer:
                return .blue
            }
        }()
        self.trailingInfoText = trailingInfoText
        self.trailingPill = trailingPill
        self.dateText = dateText
    }

    var body: some View {
        HStack(spacing: isCompactLayout ? 10 : 12) {
            Image(systemName: type.icon)
                .font(isCompactLayout ? .body : .title3)
                .foregroundStyle(.white)
                .frame(width: isCompactLayout ? 34 : 36, height: isCompactLayout ? 34 : 36)
                .background(type.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: isCompactLayout ? 2 : 3) {
                Text(concept)
                    .font(isCompactLayout ? .subheadline : .body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if !badges.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            ForEach(badges) { badge in
                                CategoryChipView(name: badge.name, iconName: badge.iconName, color: badge.color)
                                    .fixedSize()
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let firstBadge = badges.first {
                                CategoryChipView(name: firstBadge.name, iconName: firstBadge.iconName, color: firstBadge.color)
                            }

                            if badges.count > 1 {
                                HStack(spacing: 6) {
                                    ForEach(Array(badges.dropFirst())) { badge in
                                        CategoryChipView(name: badge.name, iconName: badge.iconName, color: badge.color)
                                            .fixedSize()
                                    }
                                }
                            }
                        }
                    }
                }

                ForEach(detailLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: isCompactLayout ? 2 : 3) {
                Text(amountText)
                    .font(isCompactLayout ? .headline : .body)
                    .fontWeight(.semibold)
                    .foregroundStyle(amountColor)

                if let trailingInfoText {
                    Text(trailingInfoText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trailingPill {
                    Text(trailingPill.title)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(trailingPill.color.opacity(0.15))
                        .foregroundStyle(trailingPill.color)
                        .clipShape(Capsule())
                }

                Text(dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, isCompactLayout ? 2 : 4)
    }
}
