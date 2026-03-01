//
//  ContentView.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import SwiftUI
import SwiftData

/// Vista raíz de la aplicación con navegación inferior por pestañas.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query(sort: \InvestmentSnapshot.snapshotDate, order: .reverse) private var investmentSnapshots: [InvestmentSnapshot]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]

    @State private var showingSyncImportPrompt = false
    @State private var pendingSyncExportDate: Date?
    @State private var showingSyncErrorAlert = false
    @State private var syncErrorMessage = ""

    private var pendingRecurringCount: Int {
        RecurringMovementService.pendingMovements(
            for: recurringMovements,
            confirmedMovements: movements,
            horizonDays: 5
        ).count
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
        .task {
            refreshSyncState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshSyncState()
            }
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
    }

    private func checkForSyncUpdates() {
        guard ManualSyncService.isConfigured else { return }
        guard !showingSyncImportPrompt else { return }

        guard ManualSyncService.shouldPromptForNewBackup() else { return }
        guard let latest = try? ManualSyncService.latestBackup() else { return }

        pendingSyncExportDate = latest.exportDate
        showingSyncImportPrompt = true
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
                recurringMovements: recurringMovements
            )
        } catch {
            return
        }
    }

    private func importLatestBackupFromICloudDrive() {
        do {
            let (importResult, exportDate) = try ManualSyncService.importLatestBackup()

            deleteAllData()

            for bank in importResult.banks {
                modelContext.insert(bank)
            }

            for category in importResult.categories {
                modelContext.insert(category)
            }

            for account in importResult.accounts {
                account.currency = appCurrencyCode
                modelContext.insert(account)
            }

            for movement in importResult.movements {
                modelContext.insert(movement)
            }

            for snapshot in importResult.investmentSnapshots {
                modelContext.insert(snapshot)
            }

            for recurring in importResult.recurringMovements {
                modelContext.insert(recurring)
            }

            ManualSyncService.markImported(exportDate: exportDate)
            pendingSyncExportDate = nil
        } catch {
            syncErrorMessage = "No se pudo importar la copia de iCloud Drive: \(error.localizedDescription)"
            showingSyncErrorAlert = true
        }
    }

    private func deleteAllData() {
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
}
