//
//  FinanceGlassTheme.swift
//  Finance
//
//  Created by OpenCode on 06/03/2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum FinanceGlassTokens {
    enum Spacing {
        static let xxSmall: CGFloat = 4
        static let xSmall: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 14
        static let large: CGFloat = 18
        static let xLarge: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 10
        static let chip: CGFloat = 12
        static let row: CGFloat = 16
        static let card: CGFloat = 20
        static let hero: CGFloat = 24
    }

    enum Shadow {
        static let softRadius: CGFloat = 12
        static let cardRadius: CGFloat = 18
        static let yOffset: CGFloat = 8
    }

    enum Typography {
        static let appDesign: Font.Design = .rounded

        static let sectionHeadingSize: CGFloat = 48
        static let sectionHeadingTracking: CGFloat = -0.48
        static let subHeadingSize: CGFloat = 40
        static let subHeadingTracking: CGFloat = -0.4
        static let cardTitleSize: CGFloat = 32
        static let cardTitleTracking: CGFloat = -0.32
        static let navTitleSize: CGFloat = 20
        static let bodyLargeSize: CGFloat = 18
        static let bodyLargeTracking: CGFloat = -0.09
        static let bodySize: CGFloat = 16
        static let bodyTracking: CGFloat = 0.24

        static var appDefaultFont: Font {
            body(size: bodySize)
        }

        static func display(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: appDesign)
        }

        static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: appDesign)
        }

#if canImport(UIKit)
        static func appUIFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = font.fontDescriptor.withDesign(.rounded) else {
                return font
            }

            return UIFont(descriptor: descriptor, size: size)
        }

        static func displayUIFont(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
            appUIFont(size: size, weight: weight)
        }

        static func navigationLargeTitleUIFont() -> UIFont {
            displayUIFont(size: cardTitleSize, weight: .semibold)
        }

        static func navigationInlineTitleUIFont() -> UIFont {
            displayUIFont(size: navTitleSize, weight: .semibold)
        }
#endif
    }
}

extension Color {
    static let financeAccent = Color.accentColor
}

private struct FinanceGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    var opacity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.thinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.045 * opacity) : Color.white.opacity(0.66 * opacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.62), lineWidth: 1)
            }
    }
}

struct FinanceGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.015, green: 0.018, blue: 0.028), Color(red: 0.07, green: 0.08, blue: 0.12)]
                    : [Color(red: 0.94, green: 0.965, blue: 1.0), Color(red: 0.985, green: 0.99, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.22 : 0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: -150, y: -260)

            Circle()
                .fill(Color.indigo.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 170, y: -120)

            Circle()
                .fill(Color.teal.opacity(colorScheme == .dark ? 0.10 : 0.09))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: 120, y: 360)
        }
    }
}

struct FinanceEmptyStateContent: View {
    let title: Text
    let systemImage: String
    let description: Text

    init(_ title: String, systemImage: String, description: Text) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.description = description
    }

    init(title: Text, systemImage: String, description: Text) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            title
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            description
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }
}

struct FinanceCenteredEmptyState: View {
    let title: Text
    let systemImage: String
    let description: Text

    init(_ title: LocalizedStringKey, systemImage: String, description: Text) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.description = description
    }

    var body: some View {
        ZStack {
            FinanceGlassBackground()
                .ignoresSafeArea()

            FinanceEmptyStateContent(
                title: title,
                systemImage: systemImage,
                description: description
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FinanceGlassListContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 48)
            .background(FinanceGlassBackground().ignoresSafeArea())
#else
        content
            .scrollContentBackground(.hidden)
            .background(FinanceGlassBackground().ignoresSafeArea())
#endif
    }
}

private struct FinanceGlassFormSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(
                FinanceGlassSurface(cornerRadius: FinanceGlassTokens.Radius.row)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            )
    }
}

private struct FinanceGlassClearListRowModifier: ViewModifier {
    let insets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .listRowInsets(insets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct FinanceGlassHeroListRowModifier: ViewModifier {
    let insets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct FinanceGlassCenteredEmptyListRowModifier: ViewModifier {
    let minHeight: CGFloat
    let insets: EdgeInsets

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight, alignment: .center)
            .listRowInsets(insets)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private struct FinanceGlassPrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(
                LinearGradient(
                    colors: isEnabled
                        ? [tint, tint.opacity(colorScheme == .dark ? 0.72 : 0.86)]
                        : [Color.secondary.opacity(0.45), Color.secondary.opacity(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.row, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.row, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: isEnabled ? tint.opacity(colorScheme == .dark ? 0.24 : 0.18) : .clear, radius: 14, x: 0, y: 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.65)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct FinanceGlassSecondaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(FinanceGlassSurface(cornerRadius: FinanceGlassTokens.Radius.row))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct FinanceGlassSectionHeader: View {
    let title: String
    var systemImage: String? = nil
    var subtitle: String? = nil
    var tint: Color = .financeAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.primary.opacity(0.82))
            }

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct FinanceGlassField<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = .financeAccent
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                FinanceGlassIconBadge(systemName: systemImage, tint: tint, size: 34)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                content
            }
        }
        .financeInsetCard(cornerRadius: FinanceGlassTokens.Radius.row)
    }
}

struct FinanceGlassIconBadge: View {
    let systemName: String
    var tint: Color = .financeAccent
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: max(15, size * 0.45), weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(tint.opacity(0.20), lineWidth: 1)
            )
    }
}

private struct FinanceGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(FinanceGlassTokens.Spacing.medium)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                (colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.72)),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.08), radius: 18, x: 0, y: 10)
    }
}

private struct FinanceGlassColorCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let gradient: LinearGradient

    func body(content: Content) -> some View {
        content
            .padding(FinanceGlassTokens.Spacing.medium)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.62), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(colorScheme == .dark ? 0.10 : 0.20), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .center
                        )
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 18, x: 0, y: 10)
    }
}

private struct FinanceInsetCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)
    }

    private var highlightColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.55)
    }

    func body(content: Content) -> some View {
        content
            .padding(FinanceGlassTokens.Spacing.small)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(highlightColor, lineWidth: 0.5)
            )
    }
}

private struct FinanceElevatedRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.vertical, FinanceGlassTokens.Spacing.small)
            .padding(.horizontal, FinanceGlassTokens.Spacing.medium)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                colorScheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.70),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.70), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.055), radius: 12, x: 0, y: 6)
    }
}

private struct FinanceCompactRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.58),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.55), lineWidth: 0.75)
            )
    }
}

private struct FinanceGlassPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? tint.opacity(colorScheme == .dark ? 0.24 : 0.16) : Color.secondary.opacity(colorScheme == .dark ? 0.14 : 0.10),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? tint.opacity(0.38) : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.45), lineWidth: 1)
            )
    }
}

private struct FinanceDisplayTitleModifier: ViewModifier {
    let size: CGFloat
    let tracking: CGFloat

    func body(content: Content) -> some View {
        content
            .font(FinanceGlassTokens.Typography.display(size: size))
            .tracking(tracking)
            .lineSpacing(0)
    }
}

private struct FinanceDisplaySubtitleModifier: ViewModifier {
    let size: CGFloat
    let tracking: CGFloat

    func body(content: Content) -> some View {
        content
            .font(FinanceGlassTokens.Typography.body(size: size))
            .tracking(tracking)
    }
}

extension View {
    func financeGlassListContainer() -> some View {
        modifier(FinanceGlassListContainerModifier())
    }

    func financeGlassFormSection() -> some View {
        modifier(FinanceGlassFormSectionModifier())
    }

    func financeGlassClearListRow(insets: EdgeInsets = EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)) -> some View {
        modifier(FinanceGlassClearListRowModifier(insets: insets))
    }

    func financeGlassHeroListRow(insets: EdgeInsets) -> some View {
        modifier(FinanceGlassHeroListRowModifier(insets: insets))
    }

    func financeGlassCenteredEmptyListRow(
        minHeight: CGFloat = 420,
        insets: EdgeInsets = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
    ) -> some View {
        modifier(FinanceGlassCenteredEmptyListRowModifier(minHeight: minHeight, insets: insets))
    }

    func financeGlassPageBackground() -> some View {
        background(FinanceGlassBackground().ignoresSafeArea())
    }

    func financeGlassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(FinanceGlassCardModifier(cornerRadius: cornerRadius))
    }

    func financeGlassColorCard(gradient: LinearGradient, cornerRadius: CGFloat = 18) -> some View {
        modifier(FinanceGlassColorCardModifier(cornerRadius: cornerRadius, gradient: gradient))
    }

    func financeInsetCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(FinanceInsetCardModifier(cornerRadius: cornerRadius))
    }

    func financeElevatedRow(cornerRadius: CGFloat = FinanceGlassTokens.Radius.row) -> some View {
        modifier(FinanceElevatedRowModifier(cornerRadius: cornerRadius))
    }

    func financeCompactRow(cornerRadius: CGFloat = FinanceGlassTokens.Radius.row) -> some View {
        modifier(FinanceCompactRowModifier(cornerRadius: cornerRadius))
    }

    func financeGlassPill(tint: Color, isSelected: Bool) -> some View {
        modifier(FinanceGlassPillModifier(tint: tint, isSelected: isSelected))
    }

    func financeDisplayTitle(
        size: CGFloat = FinanceGlassTokens.Typography.cardTitleSize,
        tracking: CGFloat = FinanceGlassTokens.Typography.cardTitleTracking
    ) -> some View {
        modifier(FinanceDisplayTitleModifier(size: size, tracking: tracking))
    }

    func financeDisplaySubtitle(
        size: CGFloat = FinanceGlassTokens.Typography.bodyLargeSize,
        tracking: CGFloat = FinanceGlassTokens.Typography.bodyLargeTracking
    ) -> some View {
        modifier(FinanceDisplaySubtitleModifier(size: size, tracking: tracking))
    }

    func financeToolbarIconStyle() -> some View {
        font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    func financeGlassPrimaryAction(tint: Color = .financeAccent) -> some View {
        buttonStyle(FinanceGlassPrimaryActionStyle(tint: tint))
    }

    func financeGlassSecondaryAction(tint: Color = .financeAccent) -> some View {
        buttonStyle(FinanceGlassSecondaryActionStyle(tint: tint))
    }
}
