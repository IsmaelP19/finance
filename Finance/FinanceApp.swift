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
            SavingsGoal.self,
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
    @State private var sharedModelContainer: ModelContainer?
    @State private var modelContainerError: String?
    @State private var deepLinkRouter = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            Group {
                if let sharedModelContainer {
                    ContentView()
                        .modelContainer(sharedModelContainer)
                        .environment(deepLinkRouter)
                } else if let modelContainerError {
                    ContentUnavailableView(
                        "No se pudo iniciar la base de datos",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(modelContainerError)
                    )
                } else {
                    ProgressView("Preparando datos...")
                }
            }
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

        do {
            let container = try await ModelContainerProvider.shared.loadIfNeeded()
            await MainActor.run {
                self.sharedModelContainer = container
                self.modelContainerError = nil
            }
        } catch {
            await MainActor.run {
                self.modelContainerError = error.localizedDescription
            }
        }
    }
}
