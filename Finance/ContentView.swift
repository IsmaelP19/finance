//
//  ContentView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData
import UIKit

/// Vista raíz de la aplicación con navegación inferior por pestañas.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(DeepLinkRouter.self) private var deepLinkRouter

    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @AppStorage(AppLaunchUX.hasAccountsSnapshotKey) private var hasAccountsSnapshot = false
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query(sort: \InvestmentSnapshot.snapshotDate, order: .reverse) private var investmentSnapshots: [InvestmentSnapshot]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]

    @State private var showingSyncImportPrompt = false
    @State private var pendingSyncExportDate: Date?
    @State private var showingSyncErrorAlert = false
    @State private var syncErrorMessage = ""
    @State private var showingQuickAddExpense = false
    @State private var pendingCrashReport: CrashReport?
    @State private var showingCrashReportAlert = false

    private var pendingRecurringCount: Int {
        RecurringMovementService.pendingMovements(
            for: recurringMovements,
            confirmedMovements: movements,
            horizonDays: 5
        ).count
    }

    private var activeAccounts: [BankAccount] {
        accounts.filter(\.isActive)
    }

    private var crashReportAlertMessage: String {
        guard let pendingCrashReport else { return "" }
        return "\(pendingCrashReport.summary)\n\nEl diagnóstico completo se guarda localmente en la app. Puedes copiarlo ahora para revisarlo o compartirlo."
    }

    var body: some View {
        TabView {
            ChartsView()
                .tabItem {
                    Label("Inicio", systemImage: "house.fill")
                }

            MovementsView()
                .tabItem {
                    Label("Movimientos", systemImage: "arrow.left.arrow.right.circle.fill")
                }
                .badge(pendingRecurringCount > 0 ? Text("\(pendingRecurringCount)") : nil)

            RecurringCalendarView()
                .tabItem {
                    Label("Calendario", systemImage: "calendar")
                }

            AccountListView()
                .tabItem {
                    Label("Cuentas", systemImage: "building.columns")
                }

            SettingsView()
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape.fill")
                }
        }
        .tint(.financeAccent)
        .font(FinanceGlassTokens.Typography.appDefaultFont)
        .fontDesign(FinanceGlassTokens.Typography.appDesign)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(FinanceGlassBackground().ignoresSafeArea())
        .task {
            performStartupTasks()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .alert("Backup más reciente disponible", isPresented: $showingSyncImportPrompt) {
            Button("Ahora no", role: .cancel) {
                if let pendingSyncExportDate {
                    ManualSyncService.markDismissed(exportDate: pendingSyncExportDate)
                }
                pendingSyncExportDate = nil
            }
            Button("Importar y reemplazar", role: .destructive) {
                importLatestBackupFromICloudDrive()
            }
        } message: {
            Text("Se encontró en iCloud Drive una copia de seguridad más reciente. Si importas, se reemplazarán todos los datos actuales.")
        }
        .alert("Error de sincronización", isPresented: $showingSyncErrorAlert) {
            Button("Aceptar", role: .cancel) {}
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
        .sheet(isPresented: $showingQuickAddExpense) {
            AddMovementView(preselectedType: .expense)
        }
        .onChange(of: deepLinkRouter.pendingAddExpense) { _, shouldOpen in
            if shouldOpen {
                deepLinkRouter.pendingAddExpense = false
                showingQuickAddExpense = true
            }
        }
        .onAppear {
            hasAccountsSnapshot = !activeAccounts.isEmpty
        }
        .onChange(of: accounts.count) { _, _ in
            hasAccountsSnapshot = !activeAccounts.isEmpty
        }
        .onChange(of: accounts.map(\.isArchived)) { _, _ in
            hasAccountsSnapshot = !activeAccounts.isEmpty
        }
    }

    private func checkForSyncUpdates() {
        guard ManualSyncService.isConfigured else { return }
        guard !showingSyncImportPrompt else { return }

        guard ManualSyncService.shouldPromptForNewBackup() else { return }
        guard let latest = try? ManualSyncService.latestBackup() else { return }

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
    }

    private func performStartupTasks() {
        presentPendingCrashReportIfNeeded()

        guard !showingCrashReportAlert else { return }
        refreshSyncState()
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
        refreshSyncState()
        MonthlyWrappedService.configureMonthlyReminder()
    }

    private func refreshSyncState() {
        runAutomaticBackupIfDue()
        checkForSyncUpdates()
    }

    private func runAutomaticBackupIfDue() {
        do {
            _ = try AutoBackupService.performAutoBackupIfDue(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets
            )
        } catch {
            return
        }
    }

    private func importLatestBackupFromICloudDrive() {
        do {
            let (importResult, exportDate) = try ManualSyncService.prepareLatestBackupForRestore(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets
            )
            _ = try DataExportService.importData(
                importResult,
                into: modelContext,
                mode: .replace,
                currencyCode: appCurrencyCode
            )

            ManualSyncService.markImported(exportDate: exportDate)
            pendingSyncExportDate = nil
        } catch {
            syncErrorMessage = "No se pudo importar la copia de iCloud Drive: \(error.localizedDescription)"
            showingSyncErrorAlert = true
        }
    }

    private func deleteAllData() {
        CrashReportService.shared.recordBreadcrumb("ContentView.deleteAllData")
        withAnimation {
            for movement in movements {
                modelContext.delete(movement)
            }

            for snapshot in investmentSnapshots {
                modelContext.delete(snapshot)
            }

            for recurring in recurringMovements {
                modelContext.delete(recurring)
            }

            for budget in budgets {
                modelContext.delete(budget)
            }

            for category in categories {
                modelContext.delete(category)
            }

            for account in accounts {
                modelContext.delete(account)
            }

            for bank in banks {
                modelContext.delete(bank)
            }
        }

        try? modelContext.save()
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
