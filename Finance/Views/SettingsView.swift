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
@MainActor
struct SettingsView: View {
    let onSelectCategoryMovements: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var persistenceCoordinator = PersistenceOperationCoordinator.shared
    @AppStorage(AppCurrency.storageKey) private var appCurrencyCode = AppCurrency.fallbackCode

    @AppStorage("investmentReminderEnabled") private var investmentReminderEnabled = false
    @AppStorage("investmentReminderHour") private var investmentReminderHour = 21
    @AppStorage("investmentReminderMinute") private var investmentReminderMinute = 0
    @AppStorage(AutoBackupService.enabledStorageKey) private var autoBackupEnabled = false
    @AppStorage(AutoBackupService.hourStorageKey) private var autoBackupHour = 0
    @AppStorage(AutoBackupService.minuteStorageKey) private var autoBackupMinute = 0

    @State private var showingBankManagement = false
    @State private var showingCategoryManagement = false
    @State private var showingWalletAutomationSetup = false
    @State private var pendingCategoryNavigationID: UUID?
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingSyncFolderPicker = false
    @State private var showingImportModeDialog = false
    @State private var showingSyncImportConfirmation = false
    @State private var showingLocalBackups = false
    @State private var localBackups: [LocalRepairBackupService.BackupInfo] = []
    @State private var pendingImportURL: URL?
    @State private var showingDeleteAllConfirmation = false
    @State private var showingHistoricalRepairConfirmation = false
    @State private var syncFolderName = "No configurada"
    @State private var historicalMovementCount = 0
    @State private var deleteCounts: DataExportService.ImportCounts?
    @State private var exportedFileURL: URL?
    @State private var operationTask: Task<Void, Never>?
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    settingsSubtitle

                    SettingsPanel(title: "Moneda", subtitle: "Preferencia global", systemImage: "eurosign.circle.fill") {
                        Picker(selection: $appCurrencyCode) {
                            ForEach(AppCurrency.supported, id: \.code) { option in
                                Text("\(AppCurrency.symbol(for: option.code))  \(option.code)")
                                    .tag(option.code)
                            }
                        } label: {
                            SettingsCurrencyControlLabel(selectedCode: appCurrencyCode)
                        }
                        .pickerStyle(.menu)

                        SettingsFootnote("Se aplica de forma global a toda la app. No se realiza conversión automática.")
                    }

                    SettingsPanel(title: "Organización", subtitle: "Bancos y categorías", systemImage: "square.grid.2x2.fill") {
                        Button {
                            showingBankManagement = true
                        } label: {
                            SettingsActionLabel(title: "Gestionar bancos", systemImage: "building.columns")
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        Button {
                            showingCategoryManagement = true
                        } label: {
                            SettingsActionLabel(title: "Gestionar categorías", systemImage: "tag")
                        }
                        .buttonStyle(.plain)
                    }

                    if !persistenceCoordinator.isRestoring {
                        SettingsPanel(title: "Pagos con Wallet", subtitle: "Automatizaciones por tarjeta", systemImage: "wallet.pass.fill") {
                            Button {
                                showingWalletAutomationSetup = true
                            } label: {
                                SettingsActionLabel(title: "Configurar en Atajos", systemImage: "bolt.horizontal.circle")
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Abre la guía para preparar gastos de Wallet con una automatización personal.")
                        }
                    }

                    SettingsPanel(title: "Datos", subtitle: "Exportación, importación y borrado", systemImage: "externaldrive.fill") {
                        Button {
                            exportData()
                        } label: {
                            SettingsActionLabel(title: "Exportar datos", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        ImportDataButton(showingImportPicker: $showingImportPicker) { result in
                            handleImportSelection(result: result)
                        }

                        SettingsDivider()

                        Button {
                            prepareHistoricalRepairConfirmation()
                        } label: {
                            SettingsActionLabel(title: "Reparar saldos históricos", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        Button {
                            showLocalBackups()
                        } label: {
                            SettingsActionLabel(title: "Restaurar copia de seguridad local", systemImage: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        Button(role: .destructive) {
                            prepareDeleteAllConfirmation()
                        } label: {
                            SettingsActionLabel(title: "Eliminar todos los datos", systemImage: "trash", tint: .red)
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsPanel(title: "Sincronización manual", subtitle: "Copias de seguridad en iCloud Drive", systemImage: "icloud.fill") {
                        Button {
                            showingSyncFolderPicker = true
                        } label: {
                            SettingsActionLabel(title: "Configurar carpeta iCloud Drive", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.plain)
                        .fileImporter(
                            isPresented: $showingSyncFolderPicker,
                            allowedContentTypes: [.folder],
                            allowsMultipleSelection: false
                        ) { result in
                            handleSyncFolderSelection(result: result)
                        }

                        SettingsDivider()

                        SettingsValueRow(title: "Carpeta", value: syncFolderName, systemImage: "folder")

                        SettingsDivider()

                        Button {
                            exportToICloudDrive()
                        } label: {
                            SettingsActionLabel(title: "Exportar a iCloud Drive", systemImage: "icloud.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .disabled(!ManualSyncService.isConfigured)

                        SettingsDivider()

                        Button(role: .destructive) {
                            showingSyncImportConfirmation = true
                        } label: {
                            SettingsActionLabel(title: "Importar última copia de iCloud", systemImage: "icloud.and.arrow.down", tint: .red)
                        }
                        .buttonStyle(.plain)
                        .disabled(!ManualSyncService.isConfigured)
                    }

                    SettingsPanel(title: "Copia de seguridad automática", subtitle: "Copia diaria programada", systemImage: "clock.arrow.circlepath") {
                        Toggle(isOn: $autoBackupEnabled) {
                            SettingsControlLabel(title: "Copia de seguridad diaria", subtitle: "Programa una copia de seguridad", systemImage: "arrow.triangle.2.circlepath")
                        }

                        SettingsDivider()

                        DatePicker(
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
                        ) {
                            SettingsControlLabel(title: "Hora", subtitle: "Horario aproximado", systemImage: "clock")
                        }
                        .disabled(!autoBackupEnabled)

                        SettingsFootnote("iOS puede retrasar la copia de seguridad respecto a la hora elegida, especialmente si la app está cerrada.")
                    }

                    SettingsPanel(title: "Recordatorio inversión", subtitle: "Aviso de mercado", systemImage: "chart.line.uptrend.xyaxis") {
                        Toggle(isOn: $investmentReminderEnabled) {
                            SettingsControlLabel(title: "Recordatorio diario", subtitle: "De lunes a viernes", systemImage: "bell")
                        }

                        SettingsDivider()

                        DatePicker(
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
                        ) {
                            SettingsControlLabel(title: "Hora", subtitle: "Notificación diaria", systemImage: "clock")
                        }
                        .disabled(!investmentReminderEnabled)
                    }

                    Text("v\(AppVersion.current)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), in: Capsule())
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(settingsBackground.ignoresSafeArea())
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingBankManagement) {
                BankManagementView()
            }
            .sheet(isPresented: $showingCategoryManagement, onDismiss: {
                guard let categoryID = pendingCategoryNavigationID else { return }
                pendingCategoryNavigationID = nil
                onSelectCategoryMovements(categoryID)
            }) {
                CategoryManagementView { categoryID in
                    pendingCategoryNavigationID = categoryID
                    showingCategoryManagement = false
                }
            }
            .sheet(isPresented: $showingWalletAutomationSetup) {
                WalletAutomationSetupView()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $showingLocalBackups) {
                LocalBackupRestoreView(backups: localBackups) { backup in
                    restoreLocalBackup(backup)
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
            .confirmationDialog(
                "Reparar saldos históricos",
                isPresented: $showingHistoricalRepairConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancelar", role: .cancel) {}
                Button("Reparar y crear copia de seguridad", role: .destructive) {
                    repairHistoricalBalances()
                }
            } message: {
                Text("Se creará una copia de seguridad local antes de revisar y recalcular los saldos de \(historicalMovementCount) movimiento(s).")
            }
            .alert("Eliminar todos los datos", isPresented: $showingDeleteAllConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Eliminar", role: .destructive) {
                    deleteAllData(showSuccessAlert: true)
                }
            } message: {
                Text(deleteConfirmationMessage)
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .onAppear {
            syncFolderName = ManualSyncService.syncFolderDisplayName()
            applyGlobalCurrencyToAccounts()
        }
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
        .onDisappear {
            operationTask?.cancel()
        }
        .disabled(persistenceCoordinator.isBusy)
    }

    private var settingsBackground: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.015, green: 0.018, blue: 0.028),
                        Color(red: 0.035, green: 0.055, blue: 0.075),
                        Color(red: 0.07, green: 0.07, blue: 0.11)
                    ]
                    : [
                        Color(red: 0.91, green: 0.955, blue: 1.0),
                        Color(red: 0.965, green: 0.982, blue: 1.0),
                        Color(red: 0.985, green: 0.99, blue: 0.975)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.blue.opacity(colorScheme == .dark ? 0.18 : 0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -170, y: -280)

            Circle()
                .fill(Color.indigo.opacity(colorScheme == .dark ? 0.14 : 0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 86)
                .offset(x: 180, y: -120)

            Circle()
                .fill(Color.teal.opacity(colorScheme == .dark ? 0.08 : 0.09))
                .frame(width: 360, height: 360)
                .blur(radius: 96)
                .offset(x: 120, y: 420)
        }
    }

    private var settingsSubtitle: some View {
        Text("Configura la base de tu finanza sin perder claridad.")
            .financeDisplaySubtitle(size: FinanceGlassTokens.Typography.bodySize, tracking: FinanceGlassTokens.Typography.bodyTracking)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func startPersistenceOperation(
        _ operation: PersistenceOperationCoordinator.Operation,
        action: @escaping @MainActor () async -> Void
    ) {
        guard persistenceCoordinator.begin(operation) else { return }

        operationTask?.cancel()
        operationTask = Task { @MainActor in
            defer { persistenceCoordinator.finish(operation) }
            await action()
        }
    }

    private func exportData() {
        startPersistenceOperation(.export) { @MainActor in
            do {
                let snapshot = try DataExportService.fetchSnapshot(in: modelContext)
                let url = try await DataExportService.exportDataAsync(snapshot: snapshot)
                guard !Task.isCancelled else { return }
                exportedFileURL = url
                showingExportSheet = true
            } catch {
                if !Task.isCancelled {
                    showError("Error al exportar: \(error.localizedDescription)")
                }
            }
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

        startPersistenceOperation(replaceExistingData ? .restore : .importData) { @MainActor in
            guard url.startAccessingSecurityScopedResource() else {
                showError("No se pudo acceder al archivo seleccionado.")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let importResult = try await DataExportService.importDataAsync(from: url)
                guard !Task.isCancelled else { return }

                if replaceExistingData {
                    let snapshot = try DataExportService.fetchSnapshot(in: modelContext)
                    let revision = await DataExportService.revisionAsync(of: snapshot)
                    try await ManualSyncService.createVerifiedPreRestoreBackupAsync(snapshot: snapshot)
                    guard !Task.isCancelled else { return }
                    guard try await DataExportService.revisionAsync(in: modelContext) == revision else {
                        throw PersistenceOperationError.localChangesDetected
                    }
                }

                let report = try DataExportService.importData(
                    importResult,
                    into: modelContext,
                    mode: replaceExistingData ? .replace : .merge,
                    currencyCode: appCurrencyCode
                )

                alertTitle = report.alertTitle
                alertMessage = report.summary
                showingAlert = true
            } catch {
                if !Task.isCancelled {
                    showError("Error al importar: \(error.localizedDescription)")
                }
            }
        }
    }

    private func repairHistoricalBalances() {
        startPersistenceOperation(.repair) { @MainActor in
            guard !Task.isCancelled else { return }
            var repairDidMutateContext = false
            do {
                let snapshot = try DataExportService.fetchSnapshot(in: modelContext)
                let revision = await DataExportService.revisionAsync(of: snapshot)
                let backupURL = try await createLocalPreRestoreBackupAsync(snapshot: snapshot)
                guard !Task.isCancelled else { return }
                guard try await DataExportService.revisionAsync(in: modelContext) == revision else {
                    throw PersistenceOperationError.localChangesDetected
                }
                repairDidMutateContext = true
                let report = try MovementBalanceService.repair(in: modelContext)

                alertTitle = report.accountsChanged == 0 && report.movementsChanged == 0
                    ? "Saldos históricos verificados"
                    : "Saldos históricos reparados"
                alertMessage = "Se revisaron \(report.accountsChecked) cuenta(s) y \(report.movementsChecked) movimiento(s). Se actualizaron \(report.accountsChanged) cuenta(s) y \(report.movementsChanged) movimiento(s). Copia de seguridad local: \(backupURL.lastPathComponent)."
                showingAlert = true
            } catch {
                if !Task.isCancelled {
                    if repairDidMutateContext {
                        modelContext.rollback()
                    }
                    showError("No se pudieron reparar los saldos históricos: \(error.localizedDescription)")
                }
            }
        }
    }

    private func showLocalBackups() {
        do {
            localBackups = try LocalRepairBackupService.availableBackups()
            showingLocalBackups = true
        } catch {
            showError("No se pudieron cargar las copias de seguridad locales: \(error.localizedDescription)")
        }
    }

    /// Crea el backup previo de una restauración local sin bloquear MainActor.
    /// Solo se captura el snapshot en MainActor; la conversión JSON, copia,
    /// validación y poda trabajan con valores Sendable y filesystem.
    private func createLocalPreRestoreBackupAsync(
        snapshot: DataExportService.DataSnapshot
    ) async throws -> URL {
        let tempURL = try await DataExportService.exportDataAsync(snapshot: snapshot)
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directoryURL = applicationSupportURL.appendingPathComponent("PreRepairBackups", isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
            let fileName = "Finance_pre_repair_\(formatter.string(from: Date())).json"
            let destinationURL = directoryURL.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)

            guard FileManager.default.fileExists(atPath: destinationURL.path),
                  DataExportService.readExportDate(from: destinationURL) != nil else {
                throw PersistenceOperationError.localBackupUnavailable
            }

            do {
                try DataExportService.validateExportFile(from: destinationURL)
            } catch {
                throw PersistenceOperationError.localBackupUnavailable
            }

            let backupURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter {
                $0.lastPathComponent.hasPrefix("Finance_pre_repair_")
                    && $0.pathExtension.lowercased() == "json"
            }
            .sorted {
                let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
                return (lhsDate ?? .distantPast) > (rhsDate ?? .distantPast)
            }

            for backupURL in backupURLs.dropFirst(2) {
                try? FileManager.default.removeItem(at: backupURL)
            }

            return destinationURL
        }
        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private func restoreLocalBackup(_ backup: LocalRepairBackupService.BackupInfo) {
        showingLocalBackups = false
        startPersistenceOperation(.restore) { @MainActor in
            do {
                let importResult = try await DataExportService.importDataAsync(from: backup.url)
                guard !Task.isCancelled else { return }

                let snapshot = try DataExportService.fetchSnapshot(in: modelContext)
                let revision = await DataExportService.revisionAsync(of: snapshot)
                let currentBackupURL = try await createLocalPreRestoreBackupAsync(snapshot: snapshot)

                guard !Task.isCancelled,
                      try await DataExportService.revisionAsync(in: modelContext) == revision else {
                    throw PersistenceOperationError.localChangesDetected
                }

                _ = try DataExportService.importData(
                    importResult,
                    into: modelContext,
                    mode: .replace,
                    currencyCode: appCurrencyCode
                )

                alertTitle = "Copia de seguridad restaurada"
                let repairedReferencesMessage = importResult.repairedReferences > 0
                    ? " Se repararon \(importResult.repairedReferences) referencias opcionales inválidas."
                    : ""
                alertMessage = "Se restauró la copia del \(backup.exportDate.formatted(date: .abbreviated, time: .shortened)).\(repairedReferencesMessage) Copia de seguridad del estado anterior: \(currentBackupURL.lastPathComponent)."
                showingAlert = true
            } catch {
                if !Task.isCancelled {
                    showError("No se pudo restaurar la copia de seguridad local: \(error.localizedDescription)")
                }
            }
        }
    }

    private func deleteAllData(showSuccessAlert: Bool) {
        startPersistenceOperation(.delete) { @MainActor in
            guard !Task.isCancelled else { return }
            CrashReportService.shared.recordBreadcrumb("SettingsView.deleteAllData")

            guard let snapshot = try? DataExportService.fetchSnapshot(in: modelContext) else {
                showError("Error al cargar los datos para eliminar.")
                return
            }
            guard !Task.isCancelled else { return }

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

            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                showError("Error al eliminar los datos: \(error.localizedDescription)")
                return
            }

            guard showSuccessAlert else { return }
            alertTitle = "Datos eliminados"
            alertMessage = "Se eliminaron todos los datos de la aplicacion."
            showingAlert = true
        }
    }

    private func prepareHistoricalRepairConfirmation() {
        do {
            historicalMovementCount = try DataExportService.fetchMovementCount(in: modelContext)
            showingHistoricalRepairConfirmation = true
        } catch {
            showError("No se pudo contar los movimientos: \(error.localizedDescription)")
        }
    }

    private func prepareDeleteAllConfirmation() {
        do {
            let snapshot = try DataExportService.fetchSnapshot(in: modelContext)
            deleteCounts = DataExportService.ImportCounts(
                banks: snapshot.banks.count,
                accounts: snapshot.accounts.count,
                categories: snapshot.categories.count,
                movements: snapshot.movements.count,
                investmentSnapshots: snapshot.investmentSnapshots.count,
                recurringMovements: snapshot.recurringMovements.count,
                budgets: snapshot.budgets.count,
                budgetItems: snapshot.budgets.flatMap(\.items).count
            )
            showingDeleteAllConfirmation = true
        } catch {
            showError("No se pudieron cargar los datos: \(error.localizedDescription)")
        }
    }

    private var deleteConfirmationMessage: String {
        "Se eliminarán estos datos: bancos (\(deleteCounts?.banks ?? 0)), cuentas (\(deleteCounts?.accounts ?? 0)), categorías (\(deleteCounts?.categories ?? 0)), movimientos (\(deleteCounts?.movements ?? 0)), registros de inversión (\(deleteCounts?.investmentSnapshots ?? 0)) y recurrencias (\(deleteCounts?.recurringMovements ?? 0)). Esta acción no se puede deshacer."
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
                syncFolderName = url.lastPathComponent
                updateAutoBackupSchedule()
                alertTitle = "Carpeta configurada"
                alertMessage = "Se guardarán copias de seguridad en \(url.lastPathComponent)."
                showingAlert = true
            } catch {
                showError("No se pudo guardar la carpeta: \(error.localizedDescription)")
            }
        case .failure(let error):
            showError("Error al seleccionar carpeta: \(error.localizedDescription)")
        }
    }

    private func exportToICloudDrive() {
        startPersistenceOperation(.export) { @MainActor in
            do {
                let snapshot = try DataExportService.fetchSnapshot(in: modelContext)
                let backup = try await ManualSyncService.exportToSyncDirectoryAsync(snapshot: snapshot)
                guard !Task.isCancelled else { return }

                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short

                alertTitle = "Copia de seguridad exportada"
                alertMessage = "Se guardó \(backup.url.lastPathComponent) en iCloud Drive (\(formatter.string(from: backup.exportDate)))."
                showingAlert = true
            } catch {
                if !Task.isCancelled {
                    showError("Error al exportar a iCloud Drive: \(error.localizedDescription)")
                }
            }
        }
    }

    private func importLatestFromICloudDriveReplacingData() {
        startPersistenceOperation(.restore) { @MainActor in
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

                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short

                alertTitle = "Importación completada"
                alertMessage = "Se importó la copia de iCloud Drive del \(formatter.string(from: exportDate))."
                showingAlert = true
            } catch {
                if !Task.isCancelled {
                    showError("Error al importar desde iCloud Drive: \(error.localizedDescription)")
                }
            }
        }
    }

    private func applyGlobalCurrencyToAccounts() {
        guard let accounts = try? DataExportService.fetchBankAccounts(in: modelContext) else { return }
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

private struct SettingsPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let subtitle: String
    let systemImage: String
    let content: () -> Content

    init(title: String, subtitle: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.title3.weight(.medium))
                        .tracking(-0.2)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var panelBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }
}

private struct SettingsActionLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let systemImage: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: tint)

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(tint)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsControlLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsCurrencyControlLabel: View {
    let selectedCode: String

    private var selectedCurrencyText: String {
        "\(AppCurrency.symbol(for: selectedCode))  \(selectedCode)"
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsCurrencyIcon(code: selectedCode)

            VStack(alignment: .leading, spacing: 2) {
                Text("Moneda global")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Text(selectedCurrencyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsValueRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(systemImage: systemImage, tint: .primary)

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08))
            .frame(height: 0.5)
            .padding(.leading, 46)
    }
}

private struct SettingsIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045), in: Circle())
    }
}

private struct SettingsCurrencyIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    let code: String

    var body: some View {
        Text(AppCurrency.symbol(for: code))
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .frame(width: 34, height: 34)
            .background(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045), in: Circle())
            .accessibilityHidden(true)
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
            SettingsActionLabel(title: "Importar datos", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.plain)
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            onResult(result)
        }
    }
}
