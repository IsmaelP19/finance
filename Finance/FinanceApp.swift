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
    private let logger = Logger(subsystem: "Finance", category: "AppLaunch")

    @State private var sharedModelContainer: ModelContainer?
    @State private var modelContainerError: String?
    @State private var deepLinkRouter = DeepLinkRouter()
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
        AutoBackupService.refreshBackgroundScheduleFromSettings()
    }

    private func ensureModelContainerLoaded() async {
        guard sharedModelContainer == nil else { return }

        let start = Date()
        let minimumSkeletonVisibleTime: TimeInterval = 0.12

        do {
            let container = try await ModelContainerProvider.shared.loadIfNeeded()
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
                VStack(alignment: .leading, spacing: 20) {
                    skeletonHeroCard
                    skeletonWrappedCard
                    skeletonChartCard(height: 260)
                    skeletonChartCard(height: 240)
                    skeletonSummarySection
                }
                .padding()
                .padding(.bottom, 24)
            }
            .financeGlassPageBackground()
            .navigationTitle("Finance")
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

    private var skeletonHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(Color.white.opacity(0.34))
                .frame(width: 140, height: 14)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.34))
                .frame(width: 220, height: 34)

            Capsule()
                .fill(Color.white.opacity(0.26))
                .frame(width: 190, height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.37, blue: 0.85),
                    Color(red: 0.18, green: 0.56, blue: 0.91)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shimmerSkeleton()
    }

    private var skeletonWrappedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 180, height: 12)

            Capsule()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 250, height: 10)

            Capsule()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 220, height: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .financeGlassCard()
        .shimmerSkeleton()
    }

    private func skeletonChartCard(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color.primary.opacity(0.08))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shimmerSkeleton()
    }

    private var skeletonSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 140, height: 12)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule()
                            .fill(Color.primary.opacity(0.14))
                            .frame(width: 90, height: 10)

                        Capsule()
                            .fill(Color.primary.opacity(0.2))
                            .frame(width: 110, height: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
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
