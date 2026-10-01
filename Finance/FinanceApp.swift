//
//  FinanceApp.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData
import BackgroundTasks
import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

private actor ModelContainerProvider {
    static let shared = ModelContainerProvider()

    private var cachedContainer: ModelContainer?
    private var loadingTask: Task<ModelContainer, Error>?

    func loadIfNeeded() async throws -> ModelContainer {
        if let cachedContainer {
            return cachedContainer
        }

        if let loadingTask {
            return try await loadingTask.value
        }

        let task = Task {
            try await Self.buildContainerOnBackgroundQueue()
        }
        loadingTask = task

        do {
            let container = try await task.value
            cachedContainer = container
            loadingTask = nil
            return container
        } catch {
            loadingTask = nil
            throw error
        }
    }

    private nonisolated static func buildContainerOnBackgroundQueue() async throws -> ModelContainer {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try makeContainer())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func makeContainer() throws -> ModelContainer {
        DataIntegrityRepairService.repairBeforeOpeningModelContainer()

        let schema = Schema([
            Bank.self,
            BankAccount.self,
            MovementCategory.self,
            Movement.self,
            InvestmentSnapshot.self,
            RecurringMovement.self,
            Budget.self,
            BudgetItem.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}

@main
struct FinanceApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let logger = Logger(subsystem: "Finance", category: "AppLaunch")

    @State private var sharedModelContainer: ModelContainer?
    @State private var modelContainerError: String?
    @State private var deepLinkRouter = DeepLinkRouter.shared
    @AppStorage(AppLaunchUX.hasAccountsSnapshotKey) private var hasAccountsSnapshot = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainerError {
                    ContentUnavailableView(
                        "No se pudo iniciar la base de datos",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(modelContainerError)
                    )
                } else {
                    ZStack {
                        FinanceLaunchPlaceholderView()
                            .opacity(sharedModelContainer == nil ? 1 : 0)

                        if hasAccountsSnapshot {
                            FinanceHomeSkeletonView()
                                .opacity(sharedModelContainer == nil ? 1 : 0)
                        }

                        if let sharedModelContainer {
                            ContentView()
                                .modelContainer(sharedModelContainer)
                                .environment(deepLinkRouter)
                                .opacity(1)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.38), value: sharedModelContainer != nil)
            .task {
                await ensureModelContainerLoaded()
            }
            .onOpenURL { url in
                deepLinkRouter.handle(url: url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
        }
        .backgroundTask(.appRefresh(AutoBackupService.taskIdentifier)) {
            do {
                let container = try await ModelContainerProvider.shared.loadIfNeeded()
                await AutoBackupService.handleBackgroundRefresh(modelContainer: container)
            } catch {
                return
            }
        }
    }

    init() {
        CrashReportService.shared.install()
        AutoBackupService.refreshBackgroundScheduleFromSettings()
        configureNavigationBarTypography()
    }

    private func configureNavigationBarTypography() {
#if canImport(UIKit)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes[.font] = FinanceGlassTokens.Typography.navigationLargeTitleUIFont()
        appearance.largeTitleTextAttributes[.kern] = FinanceGlassTokens.Typography.cardTitleTracking
        appearance.titleTextAttributes[.font] = FinanceGlassTokens.Typography.navigationInlineTitleUIFont()

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
#endif
    }

    private func ensureModelContainerLoaded() async {
        guard sharedModelContainer == nil else { return }

        let start = Date()
        let minimumSkeletonVisibleTime: TimeInterval = 0.12

        do {
            let container = try await ModelContainerProvider.shared.loadIfNeeded()
            try await MainActor.run {
                let repairContext = ModelContext(container)
                try MovementIntegrityRepairService.repairDanglingReimbursements(in: repairContext)
            }
            let duration = Date().timeIntervalSince(start)
            logger.log("Model container loaded in \(duration, format: .fixed(precision: 3)) seconds")

            let remainingSkeletonTime = minimumSkeletonVisibleTime - duration
            if remainingSkeletonTime > 0 {
                try? await Task.sleep(for: .seconds(remainingSkeletonTime))
            }

            await MainActor.run {
                self.sharedModelContainer = container
                self.modelContainerError = nil
            }
        } catch {
            let duration = Date().timeIntervalSince(start)
            logger.error("Model container failed after \(duration, format: .fixed(precision: 3)) seconds: \(error.localizedDescription, privacy: .public)")

            await MainActor.run {
                self.modelContainerError = error.localizedDescription
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            CrashReportService.shared.markSessionRunning()
        case .background:
            CrashReportService.shared.markSessionClean()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

private struct FinanceLaunchPlaceholderView: View {
    var body: some View {
        FinanceGlassBackground()
            .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FinanceHomeSkeletonView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    skeletonHomeHeader
                    skeletonHeroCard
                    skeletonBudgetSection
                    skeletonPatrimonySection
                    skeletonBankSection
                    skeletonSummarySection
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .financeGlassPageBackground()
            .navigationTitle("Finance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "eye")
                        .financeToolbarIconStyle()
                        .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .financeToolbarIconStyle()
                        .foregroundStyle(.secondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "chart.bar.xaxis")
                        .financeToolbarIconStyle()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var skeletonHomeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.20))
                .frame(width: 130, height: 42)

            Capsule()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 260, height: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shimmerSkeleton()
    }

    private var skeletonHeroCard: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 145, height: 14)

                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 210, height: 10)
                }

                Spacer(minLength: 12)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.30))
                    .frame(width: 230, height: 48)

                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 190, height: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color(red: 0.098, green: 0.110, blue: 0.122), in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.financeAccent.opacity(0.55))
                .frame(width: 160, height: 160)
                .offset(x: 58, y: 58)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.hero, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shimmerSkeleton()
    }

    private var skeletonBudgetSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonSectionHeader(titleWidth: 190, subtitleWidth: 200, trailingPillWidth: 36)

            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.orange.opacity(0.18))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: 130, height: 12)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.22))
                            .frame(width: 150, height: 34)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Capsule()
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 48, height: 10)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.18))
                            .frame(width: 92, height: 22)
                    }
                }

                Capsule()
                    .fill(Color.orange.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)

                HStack {
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 105, height: 12)
                    Spacer()
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                        .frame(width: 120, height: 12)
                }
            }
            .padding(16)
            .background(Color.primary.opacity(0.075), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
            )
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shimmerSkeleton()
    }

    private var skeletonPatrimonySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonSectionHeader(titleWidth: 170, subtitleWidth: 145, trailingPillWidth: 64)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.16), lineWidth: 28)
                            .frame(width: 148, height: 148)
                        VStack(spacing: 6) {
                            Capsule()
                                .fill(Color.primary.opacity(0.14))
                                .frame(width: 42, height: 10)
                            Capsule()
                                .fill(Color.primary.opacity(0.20))
                                .frame(width: 74, height: 12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<4, id: \.self) { index in
                            HStack(spacing: 9) {
                                Circle()
                                    .fill([Color.blue, .green, .purple, .cyan][index].opacity(0.55))
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 4) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.20))
                                        .frame(width: CGFloat([135, 155, 90, 75][index]), height: 12)
                                    Capsule()
                                        .fill(Color.primary.opacity(0.13))
                                        .frame(width: CGFloat([120, 135, 105, 70][index]), height: 10)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Circle()
                        .stroke(Color.primary.opacity(0.16), lineWidth: 28)
                        .frame(width: 164, height: 164)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            Capsule()
                                .fill(Color.primary.opacity(0.16))
                                .frame(height: 12)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shimmerSkeleton()
    }

    private var skeletonBankSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonSectionHeader(titleWidth: 165, subtitleWidth: 170, trailingPillWidth: 70)

            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Capsule()
                                .fill(Color.primary.opacity(0.12))
                                .frame(width: 44, height: 28)

                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill([Color.indigo, .blue, .green, .orange][index].opacity(0.18))
                                .frame(width: 34, height: 34)

                            VStack(alignment: .leading, spacing: 6) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.22))
                                    .frame(
                                        minWidth: 0,
                                        idealWidth: CGFloat([110, 145, 120, 85][index]),
                                        maxWidth: CGFloat([110, 145, 120, 85][index])
                                    )
                                    .frame(height: 14)
                                Capsule()
                                    .fill(Color.primary.opacity(0.14))
                                    .frame(minWidth: 0, idealWidth: 75, maxWidth: 75)
                                    .frame(height: 10)
                            }

                            Spacer(minLength: 0)

                            Capsule()
                                .fill(Color.primary.opacity(0.22))
                                .frame(width: 96, height: 14)
                        }

                        Capsule()
                            .fill([Color.indigo, .blue, .green, .orange][index].opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: 7)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                }
            }
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shimmerSkeleton()
    }

    private func skeletonSectionHeader(titleWidth: CGFloat, subtitleWidth: CGFloat, trailingPillWidth: CGFloat? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Capsule()
                    .fill(Color.primary.opacity(0.22))
                    .frame(width: titleWidth, height: 14)

                Capsule()
                    .fill(Color.primary.opacity(0.14))
                    .frame(width: subtitleWidth, height: 12)
            }

            Spacer()

            if let trailingPillWidth {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: trailingPillWidth, height: 32)
            }
        }
    }

    private var skeletonSummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            skeletonSectionHeader(titleWidth: 150, subtitleWidth: 220)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 240), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 34, height: 34)

                        Capsule()
                            .fill(Color.primary.opacity(0.16))
                            .frame(width: CGFloat([120, 70, 62, 135, 125, 115][index]), height: 12)

                        Capsule()
                            .fill(Color.primary.opacity(0.22))
                            .frame(width: CGFloat([130, 35, 35, 110, 90, 120][index]), height: 18)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 106, alignment: .topLeading)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                }
            }
        }
        .padding(FinanceGlassTokens.Spacing.medium)
        .padding(.bottom, 6)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: FinanceGlassTokens.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
            .shimmerSkeleton()
    }
}

private struct FinanceShimmerModifier: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let size = proxy.size
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: max(80, size.width * 0.45), height: size.height * 1.7)
                    .rotationEffect(.degrees(15))
                    .offset(x: isAnimating ? size.width * 1.35 : -size.width * 0.65)
                    .animation(
                        .linear(duration: 1.15)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
                }
                .clipped()
            }
            .onAppear {
                isAnimating = true
            }
    }
}

private extension View {
    func shimmerSkeleton() -> some View {
        modifier(FinanceShimmerModifier())
    }
}
