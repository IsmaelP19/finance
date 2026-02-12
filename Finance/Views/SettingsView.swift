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
    @Query(sort: \BankAccount.name) private var accounts: [BankAccount]
    @Query(sort: \Bank.name) private var banks: [Bank]

    @State private var showingBankManagement = false
    @State private var showingExportSheet = false
    @State private var showingImportPicker = false
    @State private var showingImportModeDialog = false
    @State private var pendingImportURL: URL?
    @State private var showingDeleteAllConfirmation = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Bancos") {
                    Button {
                        showingBankManagement = true
                    } label: {
                        Label("Gestionar bancos", systemImage: "building.columns")
                    }
                }

                Section("Datos") {
                    Button {
                        exportData()
                    } label: {
                        Label("Exportar datos", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showingImportPicker = true
                    } label: {
                        Label("Importar datos", systemImage: "square.and.arrow.down")
                    }

                    Button(role: .destructive) {
                        showingDeleteAllConfirmation = true
                    } label: {
                        Label("Eliminar todos los datos", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Ajustes")
            .sheet(isPresented: $showingBankManagement) {
                BankManagementView()
            }
            .sheet(isPresented: $showingExportSheet) {
                if let url = DataExportService.getExportFileURL() {
                    ShareSheet(activityItems: [url])
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImportSelection(result: result)
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
                Text("Se eliminaran \(banks.count) banco(s) y \(accounts.count) cuenta(s). Esta accion no se puede deshacer.")
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func exportData() {
        do {
            try DataExportService.exportData(banks: banks, accounts: accounts)
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

            for account in importResult.accounts {
                modelContext.insert(account)
            }

            alertTitle = "Importacion completada"
            alertMessage = "Se importaron \(importResult.banks.count) banco(s) y \(importResult.accounts.count) cuenta(s)."
            showingAlert = true
        } catch {
            showError("Error al importar: \(error.localizedDescription)")
        }
    }

    private func deleteAllData(showSuccessAlert: Bool) {
        withAnimation {
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
}

