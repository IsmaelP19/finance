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

enum RecurringMovementRowContentStyle {
    case compact
    case movementListCard
}

struct RecurringMovementRowContent: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    let type: MovementType
    let concept: String
    let badges: [MovementRowBadge]
    let detailLines: [String]
    let amountText: String
    let amountColor: Color
    let trailingInfoText: String?
    let trailingPill: MovementTrailingPill?
    let dateText: String
    let style: RecurringMovementRowContentStyle

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
        dateText: String,
        style: RecurringMovementRowContentStyle = .compact
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
        self.style = style
    }

    @ViewBuilder
    var body: some View {
        switch style {
        case .compact:
            compactBody
        case .movementListCard:
            movementListCardBody
        }
    }

    private var compactBody: some View {
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

                badgesContent

                detailLinesContent
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
        .financeCompactRow(cornerRadius: 14)
        .padding(.vertical, isCompactLayout ? 1 : 2)
    }

    private var movementListCardBody: some View {
        HStack(alignment: .top, spacing: isCompactLayout ? 12 : 14) {
            Image(systemName: type.icon)
                .font(isCompactLayout ? .body.weight(.semibold) : .title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(type.color)
                .frame(width: isCompactLayout ? 40 : 44, height: isCompactLayout ? 40 : 44)
                .background(type.color.opacity(colorScheme == .dark ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: isCompactLayout ? 5 : 6) {
                Text(concept)
                    .font(isCompactLayout ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                badgesContent

                detailLinesContent
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: isCompactLayout ? 5 : 6) {
                Text(amountText)
                    .font(isCompactLayout ? .headline : .body)
                    .fontWeight(.semibold)
                    .foregroundStyle(amountColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                if let trailingInfoText {
                    Text(trailingInfoText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let trailingPill {
                    Text(trailingPill.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(trailingPill.color.opacity(colorScheme == .dark ? 0.20 : 0.13), in: Capsule())
                        .foregroundStyle(trailingPill.color)
                }

                Text(dateText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, isCompactLayout ? 12 : 14)
        .padding(.horizontal, isCompactLayout ? 14 : 16)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.038), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), lineWidth: 1)
        )
        .padding(.vertical, isCompactLayout ? 2 : 3)
    }

    @ViewBuilder
    private var badgesContent: some View {
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
    }

    private var detailLinesContent: some View {
        ForEach(detailLines, id: \.self) { line in
            Text(line)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
