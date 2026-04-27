//
//  MonthlyWrappedHistoryView.swift
//  Finance
//
//  Created by OpenCode on 03/03/2026.
//

import SwiftUI
import SwiftData
import Combine

struct MonthlyWrappedHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]

    let initialMonth: WrappedMonth?

    @State private var selectedMonthForStories: WrappedMonth?

    private var availableMonths: [WrappedMonth] {
        MonthlyWrappedService.closedMonths(from: movements)
    }

    private var latestMonth: WrappedMonth? {
        availableMonths.first
    }

    private var summariesByMonth: [WrappedMonth: WrappedSummary] {
        Dictionary(uniqueKeysWithValues: availableMonths.map { month in
            (month, MonthlyWrappedService.summary(for: month, movements: movements))
        })
    }

    var body: some View {
        NavigationStack {
            List {
                if let latestMonth, let latestSummary = summariesByMonth[latestMonth] {
                    Section("Último wrapped") {
                        Button {
                            openWrappedStories(for: latestMonth)
                        } label: {
                            WrappedLatestCard(
                                summary: latestSummary,
                                currencyCode: appCurrencyCode,
                                highlighted: isMonthPending(latestMonth)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                    }
                }

                Section("Historial") {
                    if availableMonths.isEmpty {
                        ContentUnavailableView(
                            "Sin wrappeds disponibles",
                            systemImage: "sparkles.rectangle.stack",
                            description: Text("Registra movimientos en varios meses para generar tu historial mensual.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(availableMonths) { month in
                            if let summary = summariesByMonth[month] {
                                Button {
                                    openWrappedStories(for: month)
                                } label: {
                                    WrappedHistoryRow(
                                        summary: summary,
                                        currencyCode: appCurrencyCode,
                                        showPendingBadge: isMonthPending(month)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wrapped mensual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }

                if let latestMonth {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            openWrappedStories(for: latestMonth)
                        } label: {
                            Label("Último", systemImage: "sparkles")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.09, blue: 0.14),
                        Color(red: 0.10, green: 0.13, blue: 0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        .sheet(item: $selectedMonthForStories) { month in
            MonthlyWrappedStoriesView(month: month, movements: movements)
        }
    }

    private func openWrappedStories(for month: WrappedMonth) {
        selectedMonthForStories = month
    }

    private func isMonthPending(_ month: WrappedMonth) -> Bool {
        guard let latestMonth else { return false }
        guard month == latestMonth else { return false }
        return !MonthlyWrappedService.hasSeen(month: month)
    }
}

private struct WrappedLatestCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let summary: WrappedSummary
    let currencyCode: String
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(summary.month.longLabel.capitalized, systemImage: "sparkles.rectangle.stack")
                    .font(.headline)

                Spacer()

                HStack(spacing: 8) {
                    if highlighted {
                        Text("NUEVO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    wrappedViewBadge
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                WrappedMetricPill(
                    title: "Balance",
                    value: summary.netBalance.asCurrency(code: currencyCode),
                    tint: summary.netBalance.isNegative ? .red : .green
                )
                WrappedMetricPill(
                    title: "Tasa ahorro",
                    value: summary.savingsRate.map { wrappedPercentString($0) } ?? "-",
                    tint: (summary.savingsRate ?? 0).isNegative ? .red : .green
                )
                WrappedMetricPill(
                    title: "Ingresos",
                    value: summary.incomeTotal.asCurrency(code: currencyCode),
                    tint: .green
                )
                WrappedMetricPill(
                    title: "Gastos",
                    value: summary.expenseTotal.asCurrency(code: currencyCode),
                    tint: .red
                )
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: highlighted
                    ? [Color.orange.opacity(0.34), Color.orange.opacity(0.18)]
                    : [Color.blue.opacity(0.24), Color.indigo.opacity(0.20)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    highlighted ? Color.orange.opacity(0.95) : (colorScheme == .dark ? Color.white.opacity(0.16) : Color.blue.opacity(0.20)),
                    lineWidth: 1.3
                )
        )
    }

    private var wrappedViewBadge: some View {
        HStack(spacing: 6) {
            Text("Ver")
            Image(systemName: "chevron.right")
                .font(.caption2)
        }
        .font(.caption)
        .fontWeight(.semibold)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(colorScheme == .dark ? Color.white.opacity(0.14) : Color.white.opacity(0.72))
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.black.opacity(0.75))
        .overlay(
            Capsule()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.14), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

private struct WrappedHistoryRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let summary: WrappedSummary
    let currencyCode: String
    let showPendingBadge: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(summary.month.longLabel.capitalized)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: 8) {
                    if showPendingBadge {
                        Text("Nuevo")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.22))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }

                    HStack(spacing: 6) {
                        Text("Ver")
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                Label(summary.expenseTotal.asCurrency(code: currencyCode), systemImage: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                Label(summary.incomeTotal.asCurrency(code: currencyCode), systemImage: "arrow.up.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)

                Label(summary.netBalance.asCurrency(code: currencyCode), systemImage: "equal.circle.fill")
                    .font(.caption)
                    .foregroundStyle(summary.netBalance.isNegative ? .red : .green)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(colorScheme == .dark ? Color.white.opacity(0.03) : Color.blue.opacity(0.04))
    }
}

private struct WrappedMetricPill: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private enum WrappedStoryPage: Int, CaseIterable {
    case overview
    case categories
    case highlights
    case savingsStreak
    case activeDay
    case savingsCategory
    case dailyAverageExpense
    case bestWeek
    case comparison
    case sharedExpenses
    case slowestReimbursement
    case closing
}

struct MonthlyWrappedStoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    let month: WrappedMonth
    private let summary: WrappedSummary

    private let storyDuration: Double = 5
    private let storyTick: Double = 0.05
    private let storyTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private let tapAsHoldThreshold: TimeInterval = 0.22
    private let holdActivationDelay: TimeInterval = 0.14
    private let dismissSwipeThreshold: CGFloat = 110

    @State private var currentStoryIndex = 0
    @State private var currentStoryProgress: Double = 0
    @State private var isHoldingTouch = false
    @State private var touchStartedAt: Date?
    @State private var holdActivationTask: DispatchWorkItem?
    @State private var didActivateHoldDuringTouch = false
    @State private var revealStep = 0
    @State private var revealSequenceID = UUID()

    init(month: WrappedMonth, movements: [Movement]) {
        self.month = month
        self.summary = MonthlyWrappedService.summary(for: month, movements: movements)
    }

    private var availableStories: [WrappedStoryPage] {
        var stories: [WrappedStoryPage] = [.overview]

        if !summary.topExpenseCategories.isEmpty {
            stories.append(.categories)
        }

        if summary.highestExpenseDay != nil || summary.mostExpensiveMovement != nil {
            stories.append(.highlights)
        }

        if summary.savingsStreakMonths > 0 {
            stories.append(.savingsStreak)
        }

        if summary.mostActiveWeekday != nil {
            stories.append(.activeDay)
        }

        if summary.bestSavingsCategory != nil {
            stories.append(.savingsCategory)
        }

        if summary.expenseTotal > 0 {
            stories.append(.dailyAverageExpense)
        }

        if summary.bestWeek != nil {
            stories.append(.bestWeek)
        }

        if summary.comparison != nil {
            stories.append(.comparison)
        }

        if summary.sharedExpenseSummary != nil {
            stories.append(.sharedExpenses)
            stories.append(.slowestReimbursement)
        }

        stories.append(.closing)

        return stories
    }

    private var storyCount: Int {
        availableStories.count
    }

    private var currentStory: WrappedStoryPage {
        guard availableStories.indices.contains(currentStoryIndex) else {
            return availableStories.first ?? .overview
        }
        return availableStories[currentStoryIndex]
    }

    private var storyBackground: LinearGradient {
        switch currentStory {
        case .overview:
            return LinearGradient(
                colors: [Color(red: 0.07, green: 0.10, blue: 0.20), Color(red: 0.12, green: 0.15, blue: 0.30), Color(red: 0.18, green: 0.18, blue: 0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .categories:
            return LinearGradient(
                colors: [Color(red: 0.06, green: 0.11, blue: 0.16), Color(red: 0.10, green: 0.16, blue: 0.22), Color(red: 0.15, green: 0.20, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .highlights:
            return LinearGradient(
                colors: [Color(red: 0.14, green: 0.09, blue: 0.17), Color(red: 0.21, green: 0.12, blue: 0.25), Color(red: 0.30, green: 0.17, blue: 0.31)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .savingsStreak:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.16, blue: 0.14), Color(red: 0.08, green: 0.24, blue: 0.21), Color(red: 0.13, green: 0.32, blue: 0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .activeDay:
            return LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.22), Color(red: 0.12, green: 0.18, blue: 0.33), Color(red: 0.16, green: 0.24, blue: 0.40)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .savingsCategory:
            return LinearGradient(
                colors: [Color(red: 0.15, green: 0.10, blue: 0.08), Color(red: 0.22, green: 0.14, blue: 0.12), Color(red: 0.30, green: 0.19, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dailyAverageExpense:
            return LinearGradient(
                colors: [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.11, green: 0.14, blue: 0.23), Color(red: 0.17, green: 0.19, blue: 0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .bestWeek:
            return LinearGradient(
                colors: [Color(red: 0.08, green: 0.14, blue: 0.18), Color(red: 0.12, green: 0.20, blue: 0.25), Color(red: 0.17, green: 0.28, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .comparison:
            return LinearGradient(
                colors: [Color(red: 0.07, green: 0.08, blue: 0.18), Color(red: 0.11, green: 0.12, blue: 0.25), Color(red: 0.16, green: 0.16, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sharedExpenses:
            return LinearGradient(
                colors: [Color(red: 0.05, green: 0.14, blue: 0.18), Color(red: 0.08, green: 0.21, blue: 0.28), Color(red: 0.11, green: 0.28, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .slowestReimbursement:
            return LinearGradient(
                colors: [Color(red: 0.12, green: 0.09, blue: 0.18), Color(red: 0.18, green: 0.13, blue: 0.26), Color(red: 0.26, green: 0.18, blue: 0.32)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .closing:
            return LinearGradient(
                colors: [Color(red: 0.08, green: 0.12, blue: 0.18), Color(red: 0.11, green: 0.19, blue: 0.28), Color(red: 0.16, green: 0.27, blue: 0.34)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var balanceNarrative: String {
        if summary.netBalance > 0 {
            return "Cerraste el mes en positivo. Mantén este ritmo."
        }
        if summary.netBalance < 0 {
            return "Mes en negativo. Te dejamos pistas para ajustar el próximo."
        }
        return "Mes equilibrado: ingresos y gastos prácticamente iguales."
    }

    private var ambientPrimaryColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.10)
    }

    private var ambientSecondaryColor: Color {
        Color.blue.opacity(colorScheme == .dark ? 0.16 : 0.12)
    }

    private var ambientTertiaryColor: Color {
        Color.white.opacity(colorScheme == .dark ? 0.04 : 0.06)
    }

    var body: some View {
        GeometryReader { geometry in
            let compactStoryLayout = geometry.size.height < 760

            ZStack {
                storyBackground
                    .ignoresSafeArea()

                ambientShapes(size: geometry.size)

                currentStoryView(compactLayout: compactStoryLayout)
                    .padding(.top, geometry.safeAreaInsets.top + (compactStoryLayout ? 66 : 76))
                    .padding(.horizontal, 16)
                    .padding(.bottom, compactStoryLayout ? 14 : 24)
            }
            .overlay(alignment: .top) {
                topOverlay(safeTop: geometry.safeAreaInsets.top)
            }
            .overlay {
                tapZonesOverlay(safeTop: geometry.safeAreaInsets.top)
            }
            .simultaneousGesture(dismissGesture)
            .onReceive(storyTimer) { _ in
                handleStoryTick()
            }
            .onAppear {
                MonthlyWrappedService.markSeen(month: month)
                restartStories()
                startRevealSequence()
            }
            .onChange(of: currentStoryIndex) { _, _ in
                startRevealSequence()
            }
        }
        .statusBar(hidden: true)
    }

    private func ambientShapes(size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(ambientPrimaryColor)
                .frame(width: size.width * 0.95)
                .blur(radius: 65)
                .offset(x: -size.width * 0.32, y: -size.height * 0.36)

            Circle()
                .fill(ambientSecondaryColor)
                .frame(width: size.width * 0.82)
                .blur(radius: 72)
                .offset(x: size.width * 0.30, y: size.height * 0.34)

            RoundedRectangle(cornerRadius: 220)
                .fill(ambientTertiaryColor)
                .frame(width: size.width * 0.60, height: size.height * 0.22)
                .rotationEffect(.degrees(-12))
                .offset(x: -size.width * 0.12, y: size.height * 0.05)
                .blur(radius: 12)
        }
        .allowsHitTesting(false)
    }

    private func topOverlay(safeTop: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(0..<storyCount, id: \.self) { index in
                    storyProgressSegment(index: index)
                }
            }
            .padding(.horizontal, 12)

            HStack {
                Label(month.longLabel.capitalized, systemImage: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.95))

                if isHoldingTouch {
                    Text("⏸")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.96))
                        .transition(.opacity)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.20))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.top, safeTop + 8)
        .padding(.horizontal, 16)
    }

    private func storyProgressSegment(index: Int) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color.white.opacity(0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progressValue(for: index))
            }
        }
        .frame(height: 3.5)
    }

    private func progressValue(for index: Int) -> CGFloat {
        if index < currentStoryIndex {
            return 1
        }
        if index == currentStoryIndex {
            return CGFloat(max(0, min(currentStoryProgress, 1)))
        }
        return 0
    }

    private func tapZonesOverlay(safeTop: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(touchGesture(for: .previous))

            Color.clear
                .contentShape(Rectangle())
                .gesture(touchGesture(for: .next))
        }
        .padding(.top, safeTop + 68)
    }

    @ViewBuilder
    private func currentStoryView(compactLayout: Bool) -> some View {
        switch currentStory {
        case .overview:
            overviewStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .categories:
            categoriesStory(compactLayout: compactLayout)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .highlights:
            highlightsStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .savingsStreak:
            savingsStreakStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .activeDay:
            activeDayStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .savingsCategory:
            savingsCategoryStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .dailyAverageExpense:
            dailyAverageExpenseStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .bestWeek:
            bestWeekStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .comparison:
            comparisonStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .sharedExpenses:
            sharedExpensesStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .slowestReimbursement:
            slowestReimbursementStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .closing:
            closingStory
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var closingStory: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 12)

            wrappedBadge(title: "Siempre disponible", icon: "sparkles.rectangle.stack")
                .wrappedReveal(step: 1, current: revealStep)

            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(.white.opacity(0.94))
                .wrappedReveal(step: 2, current: revealStep)

            Text("Eso es todo por ahora")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .wrappedReveal(step: 2, current: revealStep)

            Text("Puedes volver a ver este resumen cuando quieras desde el boton superior derecho.")
                .font(.title3)
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.9))
                .wrappedReveal(step: 3, current: revealStep)

            Text("Busca el icono de wrapped en la pantalla de inicio.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .wrappedReveal(step: 3, current: revealStep)

            Spacer()

            Button {
                dismiss()
            } label: {
                HStack(spacing: 10) {
                    Text("Cerrar")
                        .fontWeight(.semibold)

                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.16, blue: 0.24))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .wrappedReveal(step: 4, current: revealStep)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private var overviewStory: some View {
        ZStack(alignment: .topLeading) {
            Text(summary.netBalance.asCurrency(code: appCurrencyCode))
                .font(.system(size: 132, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.12)
                .foregroundStyle(.white.opacity(0.08))
                .rotationEffect(.degrees(-8))
                .offset(x: -18, y: 98)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Resumen del mes", icon: "sparkles")
                    .wrappedReveal(step: 1, current: revealStep)

                Text(month.longLabel.capitalized)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .wrappedReveal(step: 2, current: revealStep)

                Text(summary.netBalance.asCurrency(code: appCurrencyCode))
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(netBalanceColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .wrappedReveal(step: 2, current: revealStep)

                Text(balanceNarrative)
                    .font(.subheadline)
                    .lineSpacing(2)
                    .foregroundStyle(.white.opacity(0.90))
                    .wrappedReveal(step: 3, current: revealStep)

                Spacer(minLength: 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    storyMetricTile(title: "Ingresos", value: summary.incomeTotal.asCurrency(code: appCurrencyCode), tint: .green)
                    storyMetricTile(title: "Gastos", value: summary.expenseTotal.asCurrency(code: appCurrencyCode), tint: .red)
                    storyMetricTile(title: "Tasa ahorro", value: summary.savingsRate.map { wrappedPercentString($0) } ?? "-", tint: (summary.savingsRate ?? 0).isNegative ? .red : .green)
                    storyMetricTile(title: "Movimientos", value: "\(summary.movementCount)", tint: .blue)
                }
                .wrappedReveal(step: 4, current: revealStep)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func categoriesStory(compactLayout: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: summary.topExpenseCategories.first?.iconName ?? "chart.bar")
                .font(.system(size: 180, weight: .black))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 44, y: 10)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: compactLayout ? 10 : 14) {
                wrappedBadge(title: "Dónde fue tu dinero", icon: "chart.bar.doc.horizontal")
                    .wrappedReveal(step: 1, current: revealStep)

                Text("Tus 5 categorías top")
                    .font(.system(size: compactLayout ? 30 : 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .wrappedReveal(step: 2, current: revealStep)

                if summary.topExpenseCategories.isEmpty {
                    Spacer(minLength: 8)

                    Text("Sin gastos registrados este mes")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.94))

                    Text("Añade movimientos para ver aquí el ranking mensual.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.78))

                    Spacer(minLength: 8)
                } else {
                    VStack(spacing: compactLayout ? 8 : 10) {
                        ForEach(Array(summary.topExpenseCategories.enumerated()), id: \.element.id) { index, category in
                            categoryRow(index: index + 1, category: category, compactLayout: compactLayout)
                        }
                    }
                    .wrappedReveal(step: 3, current: revealStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)   
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var highlightsStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "sparkles")
                .font(.system(size: 190, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 180, y: 10)
                .rotationEffect(.degrees(9))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Momentos clave", icon: "sparkle.magnifyingglass")
                    .wrappedReveal(step: 1, current: revealStep)

                Text("Tus estadísticas")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .wrappedReveal(step: 2, current: revealStep)

                VStack(spacing: 12) {
                    if let highestExpenseDay = summary.highestExpenseDay {
                        highlightPanel(
                            title: "Día de mayor gasto",
                            icon: "calendar.badge.exclamationmark",
                            tint: .orange,
                            primary: highestExpenseDay.totalExpense.asCurrency(code: appCurrencyCode),
                            secondary: highestExpenseDay.date.asSpanishShortDate(),
                            tertiary: "\(highestExpenseDay.movementCount) movimientos"
                        )
                    } else {
                        highlightPanel(
                            title: "Día de mayor gasto",
                            icon: "calendar.badge.exclamationmark",
                            tint: .gray,
                            primary: "Sin datos",
                            secondary: "No hay gastos registrados",
                            tertiary: ""
                        )
                    }

                    if let expensiveMovement = summary.mostExpensiveMovement {
                        highlightPanel(
                            title: "Movimiento más caro",
                            icon: expensiveMovement.categoryIconName,
                            tint: .red,
                            primary: expensiveMovement.amount.asCurrency(code: appCurrencyCode),
                            secondary: expensiveMovement.concept,
                            tertiary: expensiveMovement.date.asSpanishShortDate()
                        )
                    } else {
                        highlightPanel(
                            title: "Movimiento más caro",
                            icon: "banknote",
                            tint: .gray,
                            primary: "Sin datos",
                            secondary: "No hay gastos en este mes",
                            tertiary: ""
                        )
                    }
                }
                .wrappedReveal(step: 3, current: revealStep)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var savingsStreakStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "flame.fill")
                .font(.system(size: 190, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 188, y: 8)
                .rotationEffect(.degrees(8))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Racha de ahorro", icon: "flame")
                    .wrappedReveal(step: 1, current: revealStep)

                if summary.savingsStreakMonths > 0 {
                    Text(summary.savingsStreakMonths == 1 ? "1 mes seguido" : "\(summary.savingsStreakMonths) meses seguidos")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("Llevas \(summary.savingsStreakMonths) meses cerrando con balance positivo. Sigue así.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)
                } else {
                    Text("Sin racha activa")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("Este mes no cerró en positivo. El próximo mes puede iniciar una nueva racha.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)
                }

                Spacer(minLength: 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    storyMetricTile(title: "Balance", value: summary.netBalance.asCurrency(code: appCurrencyCode), tint: netBalanceColor)
                    storyMetricTile(title: "Tasa ahorro", value: summary.savingsRate.map { wrappedPercentString($0) } ?? "-", tint: (summary.savingsRate ?? 0).isNegative ? .red : .green)
                }
                .wrappedReveal(step: 4, current: revealStep)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var activeDayStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 178, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 174, y: 18)
                .rotationEffect(.degrees(-8))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Día más activo", icon: "calendar.badge.clock")
                    .wrappedReveal(step: 1, current: revealStep)

                if let weekday = summary.mostActiveWeekday {
                    Text(weekday.weekdayName.capitalized)
                        .font(.system(size: 46, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("\(weekday.movementCount) movimientos")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.94))
                        .wrappedReveal(step: 3, current: revealStep)

                    Text("Concentró el \(wrappedPercentString(activitySharePercent(for: weekday))) de tu actividad mensual.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.86))
                        .wrappedReveal(step: 3, current: revealStep)
                } else {
                    Text("Sin actividad")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("No hay movimientos suficientes para calcular el día más activo.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)
                }

                Spacer(minLength: 8)

                storyMetricTile(title: "Movimientos del mes", value: "\(summary.movementCount)", tint: .blue)
                    .wrappedReveal(step: 4, current: revealStep)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var savingsCategoryStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: summary.bestSavingsCategory?.iconName ?? "tag")
                .font(.system(size: 180, weight: .black))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 180, y: 10)
                .rotationEffect(.degrees(7))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Categoría con más ahorro", icon: "leaf")
                    .wrappedReveal(step: 1, current: revealStep)

                if let category = summary.bestSavingsCategory {
                    Label(category.name, systemImage: category.iconName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text(signedCurrency(category.savingsDelta))
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .foregroundStyle(category.savingsDelta.isNegative ? .red : .green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text(savingsCategoryNarrative(for: category))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .wrappedReveal(step: 3, current: revealStep)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        storyMetricTile(title: "Media histórica", value: category.historicalAverageExpense.asCurrency(code: appCurrencyCode), tint: .white)
                        storyMetricTile(title: "Gasto actual", value: category.currentExpense.asCurrency(code: appCurrencyCode), tint: .white)
                    }
                    .wrappedReveal(step: 4, current: revealStep)
                } else {
                    Text("Sin histórico suficiente")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("Necesitas más meses previos para comparar categorías y detectar dónde ahorras más.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var dailyAverageExpenseStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "calendar")
                .font(.system(size: 186, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 186, y: 12)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Gasto medio diario", icon: "calendar")
                    .wrappedReveal(step: 1, current: revealStep)

                Text(summary.averageDailyExpense.averageExpense.asCurrency(code: appCurrencyCode))
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .wrappedReveal(step: 2, current: revealStep)

                Text("Promedio por día durante \(summary.averageDailyExpense.dayCount) días de mes cerrado.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.90))
                    .wrappedReveal(step: 3, current: revealStep)

                Spacer(minLength: 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    storyMetricTile(title: "Gasto total", value: summary.expenseTotal.asCurrency(code: appCurrencyCode), tint: .red)
                    storyMetricTile(title: "Días del mes", value: "\(summary.averageDailyExpense.dayCount)", tint: .blue)
                }
                .wrappedReveal(step: 4, current: revealStep)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var bestWeekStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 184, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 184, y: 16)
                .rotationEffect(.degrees(-9))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Mejor semana", icon: "calendar.badge.checkmark")
                    .wrappedReveal(step: 1, current: revealStep)

                if let bestWeek = summary.bestWeek {
                    Text("Semana \(bestWeek.weekOfMonth)")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text(bestWeek.expenseTotal.asCurrency(code: appCurrencyCode))
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("Semana con menor gasto del mes")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.86))
                        .wrappedReveal(step: 3, current: revealStep)

                    Text(weekRangeLabel(for: bestWeek))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .wrappedReveal(step: 3, current: revealStep)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        storyMetricTile(title: "Gastos", value: bestWeek.expenseTotal.asCurrency(code: appCurrencyCode), tint: .red)
                        storyMetricTile(title: "Movimientos", value: "\(bestWeek.movementCount)", tint: .blue)
                        storyMetricTile(title: "Ingresos", value: bestWeek.incomeTotal.asCurrency(code: appCurrencyCode), tint: .green)
                        storyMetricTile(title: "Balance", value: bestWeek.netBalance.asCurrency(code: appCurrencyCode), tint: bestWeek.netBalance.isNegative ? .red : .green)
                    }
                    .wrappedReveal(step: 4, current: revealStep)
                } else {
                    Text("Sin semanas comparables")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("No hay gastos suficientes para detectar la semana con menor gasto del mes.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var comparisonStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 170, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 172, y: 14)
                .rotationEffect(.degrees(-10))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Comparativa", icon: "arrow.left.arrow.right")
                    .wrappedReveal(step: 1, current: revealStep)

                Text("Vs. \(month.previousMonth.shortLabel.capitalized)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .wrappedReveal(step: 2, current: revealStep)

                if let comparison = summary.comparison {
                    HStack(spacing: 10) {
                        comparisonValuePanel(
                            title: "Mes actual",
                            income: summary.incomeTotal,
                            expense: summary.expenseTotal,
                            net: summary.netBalance
                        )

                        comparisonValuePanel(
                            title: comparison.previousMonth.shortLabel.capitalized,
                            income: comparison.previousIncomeTotal,
                            expense: comparison.previousExpenseTotal,
                            net: comparison.previousNetBalance
                        )
                    }
                    .wrappedReveal(step: 3, current: revealStep)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        comparisonDeltaChip(title: "Ingresos", delta: comparison.incomeDelta, valueText: signedCurrency(comparison.incomeDelta), positiveIsGood: true)
                        comparisonDeltaChip(title: "Gastos", delta: comparison.expenseDelta, valueText: signedCurrency(comparison.expenseDelta), positiveIsGood: false)
                        comparisonDeltaChip(title: "Balance", delta: comparison.netDelta, valueText: signedCurrency(comparison.netDelta), positiveIsGood: true)
                        comparisonDeltaChip(title: "Tasa ahorro", delta: comparison.savingsRateDelta, valueText: comparison.savingsRateDelta.map { signedPercent($0) } ?? "-", positiveIsGood: true)
                    }
                    .wrappedReveal(step: 4, current: revealStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sharedExpensesStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 180, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 184, y: 16)
                .rotationEffect(.degrees(-8))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Gastos compartidos", icon: "person.2")
                    .wrappedReveal(step: 1, current: revealStep)

                if let shared = summary.sharedExpenseSummary {
                    Text(shared.totalExpected.asCurrency(code: appCurrencyCode))
                        .font(.system(size: 50, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text(shared.movementCount == 1 ? "1 gasto compartido registrado" : "\(shared.movementCount) gastos compartidos registrados")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)

                    Text("Top: \(shared.topSharedExpense.concept) - \(shared.topSharedExpense.expectedReimbursement.asCurrency(code: appCurrencyCode))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(2)
                        .wrappedReveal(step: 3, current: revealStep)

                    if let rate = shared.recoveryRate {
                        Text("Recuperaste el \(wrappedPercentString(rate)) al cierre del mes.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.84))
                            .wrappedReveal(step: 3, current: revealStep)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        storyMetricTile(title: "Esperado", value: shared.totalExpected.asCurrency(code: appCurrencyCode), tint: .white)
                        storyMetricTile(title: "Recuperado", value: shared.totalRecovered.asCurrency(code: appCurrencyCode), tint: .green)
                        storyMetricTile(title: "Pendiente", value: shared.totalPending.asCurrency(code: appCurrencyCode), tint: shared.totalPending > 0 ? .orange : .green)
                    }
                    .wrappedReveal(step: 4, current: revealStep)
                } else {
                    Text("Sin gastos compartidos")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("No registraste gastos compartidos durante este mes.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var slowestReimbursementStory: some View {
        ZStack(alignment: .topLeading) {
            Image(systemName: "hourglass")
                .font(.system(size: 176, weight: .black))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 182, y: 14)
                .rotationEffect(.degrees(8))
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                wrappedBadge(title: "Reembolsos cerrados en el mes", icon: "hourglass")
                    .wrappedReveal(step: 1, current: revealStep)

                if let slowest = summary.slowestReimbursementCompletion {
                    Text("\(slowest.daysToComplete) días")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("Fue el reembolso que más tardó en completarse al 100% este mes.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        storyMetricTile(title: "Gasto origen", value: slowest.expenseDate.asSpanishShortDate(), tint: .white)
                        storyMetricTile(title: "Completado", value: slowest.completionDate.asSpanishShortDate(), tint: .green)
                        storyMetricTile(title: "Reembolso", value: slowest.expectedReimbursement.asCurrency(code: appCurrencyCode), tint: .orange)
                        storyMetricTile(title: "Concepto", value: slowest.concept, tint: .white)
                    }
                    .wrappedReveal(step: 4, current: revealStep)
                } else {
                    Text("Sin reembolsos completados")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .wrappedReveal(step: 2, current: revealStep)

                    Text("Este mes no se completó ningún reembolso al 100%.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.90))
                        .wrappedReveal(step: 3, current: revealStep)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func storyMetricTile(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.82))

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private func categoryRow(index: Int, category: WrappedCategoryStat, compactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: compactLayout ? 6 : 8) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(.system(size: compactLayout ? 22 : 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, alignment: .leading)

                Label(category.name, systemImage: category.iconName)
                    .font(compactLayout ? .callout : .subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer()

                Text(category.amount.asCurrency(code: appCurrencyCode))
                    .font(compactLayout ? .callout : .subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(category.color.opacity(0.26))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(category.color)
                            .frame(width: max(8, geometry.size.width * categoryRatio(for: category)))
                    }
            }
            .frame(height: compactLayout ? 7 : 8)

            Text("\(category.movementCount) movimientos")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compactLayout ? 9 : 11)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
    }

    private func highlightPanel(
        title: String,
        icon: String,
        tint: Color,
        primary: String,
        secondary: String,
        tertiary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.92))

            Text(primary)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(secondary)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.86))

            if !tertiary.isEmpty {
                Text(tertiary)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func comparisonValuePanel(title: String, income: Decimal, expense: Decimal, net: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.84))

            Label(income.asCurrency(code: appCurrencyCode), systemImage: "arrow.up.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            Label(expense.asCurrency(code: appCurrencyCode), systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)

            Label(net.asCurrency(code: appCurrencyCode), systemImage: "equal.circle.fill")
                .font(.caption)
                .foregroundStyle(net.isNegative ? .red : .green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func comparisonDeltaChip(title: String, delta: Decimal?, valueText: String, positiveIsGood: Bool) -> some View {
        let tint = comparisonDeltaColor(delta: delta, positiveIsGood: positiveIsGood)

        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.84))

            HStack(spacing: 5) {
                Image(systemName: comparisonDeltaSymbol(delta: delta))
                    .font(.caption2)

                Text(valueText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func wrappedBadge(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.14))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
    }

    private var netBalanceColor: Color {
        if summary.netBalance < 0 {
            return .red
        }
        if summary.netBalance > 0 {
            return .green
        }
        return .white
    }

    private func comparisonDeltaColor(delta: Decimal?, positiveIsGood: Bool) -> Color {
        guard let delta else { return .white.opacity(0.82) }
        if delta == 0 { return .white.opacity(0.82) }

        let isPositive = delta > 0
        let favorable = positiveIsGood ? isPositive : !isPositive
        return favorable ? .green : .red
    }

    private func comparisonDeltaSymbol(delta: Decimal?) -> String {
        guard let delta else { return "questionmark.circle" }
        if delta == 0 { return "equal.circle" }
        return delta > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
    }

    private func categoryRatio(for category: WrappedCategoryStat) -> CGFloat {
        let maxValue = summary.topExpenseCategories.map(\.amount).max() ?? 0
        guard maxValue > 0 else { return 0 }

        let ratio = decimalAsDouble(category.amount / maxValue)
        return CGFloat(max(0, min(ratio, 1)))
    }

    private func decimalAsDouble(_ value: Decimal) -> Double {
        (value as NSDecimalNumber).doubleValue
    }

    private func signedCurrency(_ value: Decimal) -> String {
        if value > 0 {
            return "+\(value.asCurrency(code: appCurrencyCode))"
        }

        return value.asCurrency(code: appCurrencyCode)
    }

    private func signedPercent(_ value: Decimal) -> String {
        if value > 0 {
            return "+\(wrappedPercentString(value))"
        }

        return wrappedPercentString(value)
    }

    private func activitySharePercent(for weekday: WrappedWeekdayStat) -> Decimal {
        guard summary.movementCount > 0 else { return 0 }
        return (Decimal(weekday.movementCount) / Decimal(summary.movementCount)) * 100
    }

    private func savingsCategoryNarrative(for category: WrappedCategorySavingsStat) -> String {
        if category.savingsDelta >= 0 {
            return "Gastaste \(category.currentExpense.asCurrency(code: appCurrencyCode)) frente a una media de \(category.historicalAverageExpense.asCurrency(code: appCurrencyCode)) en \(category.comparedMonths) meses."
        }

        return "Es tu categoría más contenida, pero quedó por encima de su media histórica de \(category.historicalAverageExpense.asCurrency(code: appCurrencyCode))."
    }

    private func weekRangeLabel(for week: WrappedWeekBalanceStat) -> String {
        let calendar = Calendar.current
        let endDate = calendar.date(byAdding: .day, value: -1, to: week.endDate) ?? week.endDate
        return "\(week.startDate.asSpanishShortDate()) - \(endDate.asSpanishShortDate())"
    }

    private func handleStoryTick() {
        guard !isHoldingTouch else { return }

        let increment = storyTick / storyDuration
        currentStoryProgress += increment

        if currentStoryProgress >= 1 {
            goToNextStory()
        }
    }

    private func goToNextStory() {
        if currentStoryIndex < storyCount - 1 {
            withAnimation(.easeInOut(duration: 0.24)) {
                currentStoryIndex += 1
                currentStoryProgress = 0
            }
        } else {
            dismiss()
        }
    }

    private func goToPreviousStory() {
        guard currentStoryIndex > 0 else {
            currentStoryProgress = 0
            return
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            currentStoryIndex -= 1
            currentStoryProgress = 0
        }
    }

    private func restartStories() {
        currentStoryIndex = 0
        currentStoryProgress = 0
    }

    private func startRevealSequence() {
        let sequenceID = UUID()
        revealSequenceID = sequenceID
        revealStep = 0

        queueRevealStep(1, after: 0.02, sequenceID: sequenceID)
        queueRevealStep(2, after: 0.14, sequenceID: sequenceID)
        queueRevealStep(3, after: 0.28, sequenceID: sequenceID)
        queueRevealStep(4, after: 0.42, sequenceID: sequenceID)
    }

    private func queueRevealStep(_ step: Int, after delay: Double, sequenceID: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard revealSequenceID == sequenceID else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                revealStep = step
            }
        }
    }

    private enum TouchAction {
        case previous
        case next
    }

    private func touchGesture(for action: TouchAction) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if touchStartedAt == nil {
                    touchStartedAt = Date()
                    scheduleHoldActivation()
                }
            }
            .onEnded { _ in
                let duration = Date().timeIntervalSince(touchStartedAt ?? Date())
                let didHold = didActivateHoldDuringTouch

                cancelHoldActivation()
                isHoldingTouch = false
                touchStartedAt = nil
                didActivateHoldDuringTouch = false

                guard !didHold, duration <= tapAsHoldThreshold else { return }

                switch action {
                case .previous:
                    goToPreviousStory()
                case .next:
                    goToNextStory()
                }
            }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard value.translation.height > dismissSwipeThreshold else { return }
                guard abs(value.translation.width) < value.translation.height else { return }

                cancelHoldActivation()
                isHoldingTouch = false
                touchStartedAt = nil
                didActivateHoldDuringTouch = false
                dismiss()
            }
    }

    private func scheduleHoldActivation() {
        cancelHoldActivation()

        let task = DispatchWorkItem {
            guard touchStartedAt != nil else { return }
            isHoldingTouch = true
            didActivateHoldDuringTouch = true
        }

        holdActivationTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + holdActivationDelay, execute: task)
    }

    private func cancelHoldActivation() {
        holdActivationTask?.cancel()
        holdActivationTask = nil
    }
}

private extension View {
    func wrappedReveal(step: Int, current: Int, offset: CGFloat = 18) -> some View {
        self
            .opacity(current >= step ? 1 : 0)
            .offset(y: current >= step ? 0 : offset)
    }
}

private func wrappedPercentString(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = Locale(identifier: "es_ES")
    formatter.maximumFractionDigits = 2
    formatter.minimumFractionDigits = 2
    formatter.groupingSeparator = "."
    formatter.decimalSeparator = ","

    let formatted = formatter.string(from: value as NSDecimalNumber) ?? "0,00"
    return "\(formatted)%"
}
