//
//  ContentView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData
import UIKit

private enum QuickExpenseSheet: Identifiable {
    case standard
    case wallet(WalletExpenseDraft)

    var id: String {
        switch self {
        case .standard:
            return "standard"
        case .wallet(let draft):
            return draft.id.uuidString
        }
    }
}

struct CategoryMovementNavigationRequest: Equatable {
    let id = UUID()
    let categoryID: UUID
}

private enum FinanceTab: Hashable {
    case home
    case movements
    case calendar
    case accounts
    case settings
}

/// Vista raíz de la aplicación con navegación inferior por pestañas.
@MainActor
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @ObservedObject private var persistenceCoordinator = PersistenceOperationCoordinator.shared

    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @State private var showingSyncImportPrompt = false
    @State private var pendingSyncExportDate: Date?
    @State private var showingSyncErrorAlert = false
    @State private var syncErrorMessage = ""
    @State private var quickExpenseSheet: QuickExpenseSheet?
    @State private var activeWalletDraftID: UUID?
    @State private var walletDismissedForRestore = false
    @State private var pendingCrashReport: CrashReport?
    @State private var showingCrashReportAlert = false
    @State private var selectedTab: FinanceTab = .home
    @State private var categoryMovementNavigationRequest: CategoryMovementNavigationRequest?

    private var crashReportAlertMessage: String {
        guard let pendingCrashReport else { return "" }
        return "\(pendingCrashReport.summary)\n\nEl diagnóstico completo se guarda localmente en la app. Puedes copiarlo ahora para revisarlo o compartirlo."
    }

    var body: some View {
        ContentBadgeReader { pendingRecurringCount in
            quickExpenseContent(pendingRecurringCount: pendingRecurringCount)
        }
    }

    private func tabContent(pendingRecurringCount: Int) -> some View {
        TabView(selection: $selectedTab) {
            ChartsView()
                .tabItem {
                    Label("Inicio", systemImage: "house.fill")
                }
                .tag(FinanceTab.home)

            MovementsView(
                categoryNavigationRequest: $categoryMovementNavigationRequest,
                isActiveTab: selectedTab == .movements
            )
                .tabItem {
                    Label("Movimientos", systemImage: "arrow.left.arrow.right.circle.fill")
                }
                .tag(FinanceTab.movements)
                .badge(pendingRecurringCount > 0 ? Text("\(pendingRecurringCount)") : nil)

            RecurringCalendarView()
                .tabItem {
                    Label("Calendario", systemImage: "calendar")
                }
                .tag(FinanceTab.calendar)

            AccountListView()
                .tabItem {
                    Label("Cuentas", systemImage: "building.columns")
                }
                .tag(FinanceTab.accounts)

            SettingsView(onSelectCategoryMovements: { categoryID in
                categoryMovementNavigationRequest = CategoryMovementNavigationRequest(categoryID: categoryID)
                selectedTab = .movements
            })
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape.fill")
                }
                .tag(FinanceTab.settings)
        }
        .tint(.financeAccent)
        .font(FinanceGlassTokens.Typography.appDefaultFont)
        .fontDesign(FinanceGlassTokens.Typography.appDesign)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(FinanceGlassBackground().ignoresSafeArea())
    }

    private func lifecycleContent(pendingRecurringCount: Int) -> some View {
        tabContent(pendingRecurringCount: pendingRecurringCount)
        .task {
            await performStartupTasks()
            presentPendingWalletExpenseDraftIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func alertContent(pendingRecurringCount: Int) -> some View {
        lifecycleContent(pendingRecurringCount: pendingRecurringCount)
        .alert("Copia de seguridad más reciente disponible", isPresented: $showingSyncImportPrompt) {
            Button("Ahora no", role: .cancel) {
                if let pendingSyncExportDate {
                    ManualSyncService.markDismissed(exportDate: pendingSyncExportDate)
                }
                pendingSyncExportDate = nil
                showingSyncImportPrompt = false
                schedulePendingWalletExpensePresentation()
            }
            Button("Importar y reemplazar", role: .destructive) {
                showingSyncImportPrompt = false
                importLatestBackupFromICloudDrive()
                schedulePendingWalletExpensePresentation()
            }
        } message: {
            Text("Se encontró en iCloud Drive una copia de seguridad más reciente. Si importas, se reemplazarán todos los datos actuales.")
        }
        .alert("Error de sincronización", isPresented: $showingSyncErrorAlert) {
            Button("Aceptar", role: .cancel) {
                showingSyncErrorAlert = false
                schedulePendingWalletExpensePresentation()
            }
        } message: {
            Text(syncErrorMessage)
        }
        .alert("La app se cerró inesperadamente", isPresented: $showingCrashReportAlert) {
            Button("Copiar diagnóstico") {
                copyPendingCrashReportAndDismiss()
            }
            Button("Aceptar", role: .cancel) {
                dismissPendingCrashReport()
            }
        } message: {
            Text(crashReportAlertMessage)
        }
    }

    private func quickExpenseContent(pendingRecurringCount: Int) -> some View {
        alertContent(pendingRecurringCount: pendingRecurringCount)
        .sheet(item: $quickExpenseSheet, onDismiss: handleQuickExpenseSheetDismissal) { destination in
            switch destination {
            case .standard:
                AddMovementView(preselectedType: .expense)
            case .wallet(let draft):
                AddMovementView(walletExpenseDraft: draft)
            }
        }
        .onChange(of: deepLinkRouter.pendingAddExpense) { _, shouldOpen in
            if shouldOpen { presentPendingDeepLinkExpenseIfNeeded() }
        }
        .onChange(of: deepLinkRouter.walletExpenseDraftRevision) { _, _ in
            presentPendingWalletExpenseDraftIfNeeded()
        }
        .onChange(of: persistenceCoordinator.isRestoring) { _, isRestoring in
            if isRestoring, case .wallet = quickExpenseSheet {
                // No se confirma el draft: si la restauración cancela la hoja,
                // el gasto pendiente podrá mostrarse de nuevo al terminar.
                walletDismissedForRestore = true
                quickExpenseSheet = nil
            } else if !isRestoring {
                presentPendingDeepLinkExpenseIfNeeded()
            }
        }
        .onChange(of: persistenceCoordinator.isBusy) { _, isBusy in
            guard !isBusy else { return }
            presentPendingDeepLinkExpenseIfNeeded()
            schedulePendingWalletExpensePresentation()
        }
    }

    private func checkForSyncUpdates() async {
        guard ManualSyncService.isConfigured else { return }
        guard !showingSyncImportPrompt else { return }
        guard !persistenceCoordinator.isBusy else { return }

        guard let latest = try? await ManualSyncService.latestBackupIfPromptNeeded() else { return }

        pendingSyncExportDate = latest.exportDate
        showingSyncImportPrompt = true
    }

    private func presentPendingCrashReportIfNeeded() {
        guard pendingCrashReport == nil else { return }
        guard let report = CrashReportService.shared.pendingReport() else { return }

        pendingCrashReport = report
        showingCrashReportAlert = true
    }

    private func copyPendingCrashReportAndDismiss() {
        if let pendingCrashReport {
            UIPasteboard.general.string = pendingCrashReport.details
        }

        dismissPendingCrashReport()
    }

    private func dismissPendingCrashReport() {
        CrashReportService.shared.markPendingReportSeen()
        pendingCrashReport = nil
        showingCrashReportAlert = false
        schedulePendingWalletExpensePresentation()
    }

    private func performStartupTasks() async {
        presentPendingCrashReportIfNeeded()

        guard !showingCrashReportAlert else { return }
        await refreshSyncState()
        MonthlyWrappedService.configureMonthlyReminder()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .background {
            CrashReportService.shared.markSessionClean()
            return
        }

        guard newPhase == .active else { return }

        CrashReportService.shared.markSessionRunning()
        presentPendingCrashReportIfNeeded()
        Task { @MainActor in
            await refreshSyncState()
            MonthlyWrappedService.configureMonthlyReminder()
            presentPendingWalletExpenseDraftIfNeeded()
        }
    }

    private func presentPendingWalletExpenseDraftIfNeeded() {
        guard quickExpenseSheet == nil else { return }
        guard !showingSyncImportPrompt, !showingSyncErrorAlert, !showingCrashReportAlert else { return }
        guard !persistenceCoordinator.isBusy else { return }
        guard let draft = WalletExpenseDraftStore.nextPending() else { return }
        activeWalletDraftID = draft.id
        quickExpenseSheet = .wallet(draft)
    }

    private func presentPendingDeepLinkExpenseIfNeeded() {
        guard !persistenceCoordinator.isBusy,
              quickExpenseSheet == nil,
              deepLinkRouter.pendingAddExpense else { return }
        deepLinkRouter.pendingAddExpense = false
        quickExpenseSheet = .standard
    }

    private func handleQuickExpenseSheetDismissal() {
        if walletDismissedForRestore {
            walletDismissedForRestore = false
            activeWalletDraftID = nil
        } else if !persistenceCoordinator.isRestoring, let activeWalletDraftID {
            WalletExpenseDraftStore.acknowledge(activeWalletDraftID)
            self.activeWalletDraftID = nil
        }

        presentPendingDeepLinkExpenseIfNeeded()
        presentPendingWalletExpenseDraftIfNeeded()
    }

    private func schedulePendingWalletExpensePresentation() {
        guard !persistenceCoordinator.isBusy else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !persistenceCoordinator.isBusy else { return }
            presentPendingWalletExpenseDraftIfNeeded()
        }
    }

    private func refreshSyncState() async {
        await runAutomaticBackupIfDue()
        await checkForSyncUpdates()
    }

    private func runAutomaticBackupIfDue() async {
        do {
            _ = try await AutoBackupService.performAutoBackupIfDue(in: modelContext)
        } catch {
            return
        }
    }

    private func importLatestBackupFromICloudDrive() {
        guard persistenceCoordinator.begin(.restore) else { return }
        Task { @MainActor in
            defer { persistenceCoordinator.finish(.restore) }
            do {
                let (importResult, exportDate, revision) = try await ManualSyncService.prepareLatestBackupForRestoreAsync(
                    snapshotProvider: {
                        try DataExportService.fetchSnapshot(in: modelContext)
                    }
                )
                try Task.checkCancellation()
                guard try await DataExportService.revisionAsync(in: modelContext) == revision else {
                    throw PersistenceOperationError.localChangesDetected
                }
                _ = try DataExportService.importData(
                    importResult,
                    into: modelContext,
                    mode: .replace,
                    currencyCode: appCurrencyCode
                )

                ManualSyncService.markImported(exportDate: exportDate)
                pendingSyncExportDate = nil
            } catch {
                if Task.isCancelled { return }
                syncErrorMessage = "No se pudo importar la copia de iCloud Drive: \(error.localizedDescription)"
                showingSyncErrorAlert = true
            }
        }
    }

    private func deleteAllData() {
        CrashReportService.shared.recordBreadcrumb("ContentView.deleteAllData")
        guard let snapshot = try? DataExportService.fetchSnapshot(in: modelContext) else { return }
        withAnimation {
            for movement in snapshot.movements {
                modelContext.delete(movement)
            }

            for investmentSnapshot in snapshot.investmentSnapshots {
                modelContext.delete(investmentSnapshot)
            }

            for recurring in snapshot.recurringMovements {
                modelContext.delete(recurring)
            }

            for budget in snapshot.budgets {
                modelContext.delete(budget)
            }

            for category in snapshot.categories {
                modelContext.delete(category)
            }

            for account in snapshot.accounts {
                modelContext.delete(account)
            }

            for bank in snapshot.banks {
                modelContext.delete(bank)
            }
        }

        try? modelContext.save()
    }
}

/// Mantiene las consultas observables del badge fuera de la vista raíz.
/// Sólo observa movimientos vinculados a recurrencias y cuentas activas.
@MainActor
private struct ContentBadgeReader<Content: View>: View {
    @AppStorage(AppLaunchUX.hasAccountsSnapshotKey) private var hasAccountsSnapshot = false
    @Query(filter: #Predicate<BankAccount> { !$0.isArchived }) private var activeAccounts: [BankAccount]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]
    @Query(filter: #Predicate<Movement> { $0.recurringRuleId != nil }) private var confirmedMovements: [Movement]

    let content: (Int) -> Content

    private var pendingRecurringCount: Int {
        RecurringMovementService.pendingMovements(
            for: recurringMovements,
            confirmedMovements: confirmedMovements,
            horizonDays: 5
        ).count
    }

    init(@ViewBuilder content: @escaping (Int) -> Content) {
        self.content = content
    }

    var body: some View {
        content(pendingRecurringCount)
            .onAppear(perform: updateAccountSnapshot)
            .onChange(of: activeAccounts.count) { _, _ in
                updateAccountSnapshot()
            }
    }

    private func updateAccountSnapshot() {
        let newValue = !activeAccounts.isEmpty
        if hasAccountsSnapshot != newValue {
            hasAccountsSnapshot = newValue
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                Bank.self,
                BankAccount.self,
                MovementCategory.self,
                Movement.self,
                InvestmentSnapshot.self,
                RecurringMovement.self
            ],
            inMemory: true
        )
        .environment(DeepLinkRouter())
}
