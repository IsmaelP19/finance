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
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var showingLocalBackups = false
    @State private var localBackups: [LocalRepairBackupService.BackupInfo] = []
    @State private var pendingImportURL: URL?
    @State private var showingDeleteAllConfirmation = false
    @State private var showingHistoricalRepairConfirmation = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var syncFolderName: String {
        ManualSyncService.syncFolderDisplayName()
    }

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
                            showingHistoricalRepairConfirmation = true
                        } label: {
                            SettingsActionLabel(title: "Reparar saldos históricos", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        Button {
                            showLocalBackups()
                        } label: {
                            SettingsActionLabel(title: "Restaurar backup local", systemImage: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(.plain)

                        SettingsDivider()

                        Button(role: .destructive) {
                            showingDeleteAllConfirmation = true
                        } label: {
                            SettingsActionLabel(title: "Eliminar todos los datos", systemImage: "trash", tint: .red)
                        }
                        .buttonStyle(.plain)
                    }

                    SettingsPanel(title: "Sincronización manual", subtitle: "Backups en iCloud Drive", systemImage: "icloud.fill") {
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

                    SettingsPanel(title: "Backup automático", subtitle: "Copia diaria programada", systemImage: "clock.arrow.circlepath") {
                        Toggle(isOn: $autoBackupEnabled) {
                            SettingsControlLabel(title: "Backup diario", subtitle: "Programa una copia de seguridad", systemImage: "arrow.triangle.2.circlepath")
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
                            SettingsControlLabel(title: "Hora", subtitle: "Best effort de iOS", systemImage: "clock")
                        }
                        .disabled(!autoBackupEnabled)

                        SettingsFootnote("Se ejecuta en modo best effort. iOS puede retrasar la ejecución exacta con la app cerrada.")
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
            .sheet(isPresented: $showingCategoryManagement) {
                CategoryManagementView()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = DataExportService.getExportFileURL() {
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
                Button("Reparar y crear backup", role: .destructive) {
                    repairHistoricalBalances()
                }
            } message: {
                Text("Se creará un backup local antes de revisar y recalcular los saldos de \(movements.count) movimiento(s).")
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
            let importResult = try DataExportService.importData(from: url)

            if replaceExistingData {
                try ManualSyncService.createVerifiedPreRestoreBackup(
                    banks: banks,
                    accounts: accounts,
                    categories: categories,
                    movements: movements,
                    investmentSnapshots: investmentSnapshots,
                    recurringMovements: recurringMovements,
                    budgets: budgets
                )
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
            showError("Error al importar: \(error.localizedDescription)")
        }
    }

    private func repairHistoricalBalances() {
        do {
            let backup = try LocalRepairBackupService.createVerifiedBackup(
                banks: banks,
                accounts: accounts,
                categories: categories,
                movements: movements,
                investmentSnapshots: investmentSnapshots,
                recurringMovements: recurringMovements,
                budgets: budgets
            )
            let report = try MovementBalanceService.repair(in: modelContext)

            alertTitle = report.accountsChanged == 0 && report.movementsChanged == 0
                ? "Saldos históricos verificados"
                : "Saldos históricos reparados"
            alertMessage = "Se revisaron \(report.accountsChecked) cuenta(s) y \(report.movementsChecked) movimiento(s). Se actualizaron \(report.accountsChanged) cuenta(s) y \(report.movementsChanged) movimiento(s). Backup local: \(backup.url.lastPathComponent)."
            showingAlert = true
        } catch {
            modelContext.rollback()
            showError("No se pudieron reparar los saldos históricos: \(error.localizedDescription)")
        }
    }

    private func showLocalBackups() {
        do {
            localBackups = try LocalRepairBackupService.availableBackups()
            showingLocalBackups = true
        } catch {
            showError("No se pudieron cargar los backups locales: \(error.localizedDescription)")
        }
    }

    private func restoreLocalBackup(_ backup: LocalRepairBackupService.BackupInfo) {
        do {
            let importResult = try LocalRepairBackupService.prepareForRestore(backup)
            let currentBackup = try LocalRepairBackupService.createVerifiedBackup(
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

            alertTitle = "Backup restaurado"
            let repairedReferencesMessage = importResult.repairedReferences > 0
                ? " Se repararon \(importResult.repairedReferences) referencias opcionales inválidas."
                : ""
            alertMessage = "Se restauró la copia del \(backup.exportDate.formatted(date: .abbreviated, time: .shortened)).\(repairedReferencesMessage) Backup del estado anterior: \(currentBackup.url.lastPathComponent)."
            showingAlert = true
        } catch {
            modelContext.rollback()
            showError("No se pudo restaurar el backup local: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func deleteAllData(showSuccessAlert: Bool) -> Bool {
        CrashReportService.shared.recordBreadcrumb("SettingsView.deleteAllData")

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

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            showError("Error al eliminar los datos: \(error.localizedDescription)")
            return false
        }

        if showSuccessAlert {
            alertTitle = "Datos eliminados"
            alertMessage = "Se eliminaron todos los datos de la aplicacion."
            DispatchQueue.main.async {
                showingAlert = true
            }
        }

        return true
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
