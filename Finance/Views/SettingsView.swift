//
//  SettingsView.swift
//  Finance
//
//  Created by Ismael Perez on 11/02/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Ajustes de la aplicacion: bancos, importacion/exportacion y borrado total.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \Bank.name) private var banks: [Bank]
    @Query(sort: \Movement.occurredAt, order: .reverse) private var movements: [Movement]
    @Query(sort: \MovementCategory.name) private var categories: [MovementCategory]
    @Query(sort: \InvestmentSnapshot.snapshotDate, order: .reverse) private var investmentSnapshots: [InvestmentSnapshot]
    @Query(sort: \RecurringMovement.updatedAt, order: .reverse) private var recurringMovements: [RecurringMovement]
    @Query(sort: \Budget.createdAt) private var budgets: [Budget]

    @AppStorage("investmentReminderEnabled") private var investmentReminderEnabled = false
    @AppStorage("investmentReminderHour") private var investmentReminderHour = 21
    @AppStorage("investmentReminderMinute") private var investmentReminderMinute = 0
    @AppStorage(AutoBackupService.enabledStorageKey) private var autoBackupEnabled = false
    @AppStorage(AutoBackupService.hourStorageKey) private var autoBackupHour = 0
    @AppStorage(AutoBackupService.minuteStorageKey) private var autoBackupMinute = 0

    @State private var showingBankManagement = false
    @State private var showingCategoryManagement = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingSyncFolderPicker = false
    @State private var showingImportModeDialog = false
    @State private var showingSyncImportConfirmation = false
    @State private var pendingImportURL: URL?
    @State private var showingDeleteAllConfirmation = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var syncFolderName: String {
        ManualSyncService.syncFolderDisplayName()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Moneda") {
                    Picker("Moneda global", selection: $appCurrencyCode) {
                        ForEach(AppCurrency.supported, id: \.code) { option in
                            Text("\(option.name) (\(option.code))")
                                .tag(option.code)
                        }
                    }

                    Text("Se aplica de forma global a toda la app. No se realiza conversión automática.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Organización") {
                    Button {
                        showingBankManagement = true
                    } label: {
                        Label("Gestionar bancos", systemImage: "building.columns")
                    }

                    Button {
                        showingCategoryManagement = true
                    } label: {
                        Label("Gestionar categorías", systemImage: "tag")
                    }
                }

                Section("Datos") {
                    Button {
                        exportData()
                    } label: {
                        Label("Exportar datos", systemImage: "square.and.arrow.up")
                    }

                    ImportDataButton(showingImportPicker: $showingImportPicker) { result in
                        handleImportSelection(result: result)
                    }

                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        Label("Eliminar todos los datos", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }

                Section("Sincronización manual") {
                    Button {
                        showingSyncFolderPicker = true
                    } label: {
                        Label("Configurar carpeta iCloud Drive", systemImage: "folder.badge.plus")
                    }
                    .fileImporter(
                        isPresented: $showingSyncFolderPicker,
                        allowedContentTypes: [.folder],
                        allowsMultipleSelection: false
                    ) { result in
                        handleSyncFolderSelection(result: result)
                    }

                    HStack {
                        Label("Carpeta", systemImage: "folder")
                        Spacer()
                        Text(syncFolderName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        exportToICloudDrive()
                    } label: {
                        Label("Exportar a iCloud Drive", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(!ManualSyncService.isConfigured)

                    Button(role: .destructive) {
                        showingSyncImportConfirmation = true
                    } label: {
                        Label("Importar última copia de iCloud", systemImage: "icloud.and.arrow.down")
                            .foregroundStyle(.red)
                    }
                    .disabled(!ManualSyncService.isConfigured)
                }

                Section("Backup automático") {
                    Toggle("Backup diario", isOn: $autoBackupEnabled)

                    DatePicker(
                        "Hora",
                        selection: Binding(
                            get: {
                                Calendar.current.date(
                                    bySettingHour: autoBackupHour,
                                    minute: autoBackupMinute,
                                    second: 0,
                                    of: Date()
                                ) ?? Date()
                            },
                            set: { newDate in
                                autoBackupHour = Calendar.current.component(.hour, from: newDate)
                                autoBackupMinute = Calendar.current.component(.minute, from: newDate)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!autoBackupEnabled)

                    Text("Se ejecuta en modo best effort. iOS puede retrasar la ejecución exacta con la app cerrada.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Recordatorio inversión") {
                    Toggle("Recordatorio diario (L-V)", isOn: $investmentReminderEnabled)

                    DatePicker(
                        "Hora",
                        selection: Binding(
                            get: {
                                Calendar.current.date(
                                    bySettingHour: investmentReminderHour,
                                    minute: investmentReminderMinute,
                                    second: 0,
                                    of: Date()
                                ) ?? Date()
                            },
                            set: { newDate in
                                investmentReminderHour = Calendar.current.component(.hour, from: newDate)
                                investmentReminderMinute = Calendar.current.component(.minute, from: newDate)
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!investmentReminderEnabled)
                }

                HStack {
                    Spacer()
                    Text("v\(AppVersion.current)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 18, leading: 0, bottom: 8, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            }
            .financeGlassListContainer()
            .navigationTitle("Ajustes")
            .sheet(isPresented: $showingBankManagement) {
                BankManagementView()
            }
            .sheet(isPresented: $showingCategoryManagement) {
                CategoryManagementView()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = DataExportService.getExportFileURL() {
                    ShareSheet(activityItems: [url])
                }
            }
            .confirmationDialog(
                "Importar desde iCloud Drive",
                isPresented: $showingSyncImportConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancelar", role: .cancel) {}
                Button("Importar y reemplazar", role: .destructive) {
                    importLatestFromICloudDriveReplacingData()
                }
            } message: {
                Text("Se importará la última copia disponible en iCloud Drive y se reemplazarán todos los datos actuales.")
            }
            .confirmationDialog(
                "Importar datos",
                isPresented: $showingImportModeDialog,
                titleVisibility: .visible
            ) {
                Button("Mantener datos actuales") {
                    importFromPendingURL(replaceExistingData: false)
                }

                Button("Reemplazar datos actuales", role: .destructive) {
                    importFromPendingURL(replaceExistingData: true)
                }

                Button("Cancelar", role: .cancel) {
                    pendingImportURL = nil
                }
            } message: {
                Text("Puedes importar sumando los datos al estado actual o reemplazarlos completamente.")
            }
            .alert("Eliminar todos los datos", isPresented: $showingDeleteAllConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) {
                    deleteAllData(showSuccessAlert: true)
                }
            } message: {
                Text("Se eliminaran \(banks.count) banco(s), \(accounts.count) cuenta(s), \(categories.count) categoria(s), \(movements.count) movimiento(s), \(investmentSnapshots.count) snapshot(s) de inversión y \(recurringMovements.count) recurrencia(s). Esta accion no se puede deshacer.")
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear(perform: applyGlobalCurrencyToAccounts)
        .onAppear {
            updateInvestmentReminderSchedule()
            updateAutoBackupSchedule()
        }
        .onChange(of: appCurrencyCode) { _, _ in
            applyGlobalCurrencyToAccounts()
        }
        .onChange(of: investmentReminderEnabled) { _, _ in
            updateInvestmentReminderSchedule()
        }
        .onChange(of: investmentReminderHour) { _, _ in
            updateInvestmentReminderSchedule()
        }
        .onChange(of: investmentReminderMinute) { _, _ in
            updateInvestmentReminderSchedule()
        }
        .onChange(of: autoBackupEnabled) { _, _ in
            updateAutoBackupSchedule()
        }
        .onChange(of: autoBackupHour) { _, _ in
            updateAutoBackupSchedule()
        }
        .onChange(of: autoBackupMinute) { _, _ in
            updateAutoBackupSchedule()
        }
    }

    private func exportData() {
        do {
            try DataExportService.exportData(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets
            )
            showingExportSheet = true
        } catch {
            showError("Error al exportar: \(error.localizedDescription)")
        }
    }

    private func handleImportSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            pendingImportURL = url
            showingImportModeDialog = true
        case .failure(let error):
            showError("Error al seleccionar archivo: \(error.localizedDescription)")
        }
    }

    private func importFromPendingURL(replaceExistingData: Bool) {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil

        guard url.startAccessingSecurityScopedResource() else {
            showError("No se pudo acceder al archivo seleccionado.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            if replaceExistingData {
                deleteAllData(showSuccessAlert: false)
            }

            let importResult = try DataExportService.importData(from: url)

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

            for budget in importResult.budgets {
                modelContext.insert(budget)
            }

            alertTitle = "Importacion completada"
            alertMessage = "Se importaron \(importResult.banks.count) banco(s), \(importResult.accounts.count) cuenta(s), \(importResult.categories.count) categoria(s), \(importResult.movements.count) movimiento(s), \(importResult.investmentSnapshots.count) snapshot(s) de inversión, \(importResult.recurringMovements.count) recurrencia(s) y \(importResult.budgets.count) presupuesto(s)."
            showingAlert = true
        } catch {
            showError("Error al importar: \(error.localizedDescription)")
        }
    }

    private func deleteAllData(showSuccessAlert: Bool) {
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

        if showSuccessAlert {
            alertTitle = "Datos eliminados"
            alertMessage = "Se eliminaron todos los datos de la aplicacion."
            showingAlert = true
        }
    }

    private func showError(_ message: String) {
        alertTitle = "Error"
        alertMessage = message
        showingAlert = true
    }

    private func handleSyncFolderSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard didAccess else {
                showError("No se pudo acceder a la carpeta seleccionada.")
                return
            }

            do {
                try ManualSyncService.setSyncDirectory(url)
                updateAutoBackupSchedule()
                alertTitle = "Carpeta configurada"
                alertMessage = "Se guardarán backups en \(url.lastPathComponent)."
                showingAlert = true
            } catch {
                showError("No se pudo guardar la carpeta: \(error.localizedDescription)")
            }
        case .failure(let error):
            showError("Error al seleccionar carpeta: \(error.localizedDescription)")
        }
    }

    private func exportToICloudDrive() {
        do {
            let backup = try ManualSyncService.exportToSyncDirectory(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets
            )

            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            alertTitle = "Backup exportado"
            alertMessage = "Se guardó \(backup.url.lastPathComponent) en iCloud Drive (\(formatter.string(from: backup.exportDate)))."
            showingAlert = true
        } catch {
            showError("Error al exportar a iCloud Drive: \(error.localizedDescription)")
        }
    }

    private func importLatestFromICloudDriveReplacingData() {
        do {
            let (importResult, exportDate) = try ManualSyncService.importLatestBackup()

            deleteAllData(showSuccessAlert: false)

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

            for budget in importResult.budgets {
                modelContext.insert(budget)
            }

            ManualSyncService.markImported(exportDate: exportDate)

            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short

            alertTitle = "Importación completada"
            alertMessage = "Se importó la copia de iCloud Drive del \(formatter.string(from: exportDate))."
            showingAlert = true
        } catch {
            showError("Error al importar desde iCloud Drive: \(error.localizedDescription)")
        }
    }

    private func applyGlobalCurrencyToAccounts() {
        for account in accounts where account.currency != appCurrencyCode {
            account.currency = appCurrencyCode
            account.updatedAt = Date()
        }
    }

    private func updateInvestmentReminderSchedule() {
        InvestmentReminderService.configureWeekdayReminder(
            enabled: investmentReminderEnabled,
            hour: investmentReminderHour,
            minute: investmentReminderMinute
        )
    }

    private func updateAutoBackupSchedule() {
        AutoBackupService.refreshBackgroundSchedule(
            enabled: autoBackupEnabled,
            hour: autoBackupHour,
            minute: autoBackupMinute
        )
    }
}

// MARK: - Import Data Button

/// Vista independiente que encapsula el botón de importar datos y su `.fileImporter`.
/// Al ser una vista separada, el `.fileImporter` no compite con otros modifiers de
/// presentación en la vista padre.
private struct ImportDataButton: View {
    @Binding var showingImportPicker: Bool
    var onResult: (Result<[URL], Error>) -> Void

    var body: some View {
        Button {
            showingImportPicker = true
        } label: {
            Label("Importar datos", systemImage: "square.and.arrow.down")
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            onResult(result)
        }
    }
}
