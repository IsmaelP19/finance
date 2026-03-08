//
//  FinanceGlassTheme.swift
//  Finance
//
//  Created by OpenCode on 06/03/2026.
//

import SwiftUI

struct FinanceGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.black, Color(red: 0.07, green: 0.08, blue: 0.11)]
                : [Color(red: 0.93, green: 0.95, blue: 0.99), Color.white],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct FinanceGlassListContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(FinanceGlassBackground().ignoresSafeArea())
#else
        content
            .scrollContentBackground(.hidden)
            .background(FinanceGlassBackground().ignoresSafeArea())
#endif
    }
}

private struct FinanceGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 14, x: 0, y: 8)
    }
}

private struct FinanceGlassColorCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let gradient: LinearGradient

    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.06), radius: 14, x: 0, y: 8)
    }
}

private struct FinanceInsetCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.40), lineWidth: 1)
            )
    }
}

extension View {
    func financeGlassListContainer() -> some View {
        modifier(FinanceGlassListContainerModifier())
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

    func financeToolbarIconStyle() -> some View {
        font(.system(size: 17, weight: .semibold))
    }
}
