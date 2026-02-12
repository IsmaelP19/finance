//
//  DataExportService.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import Foundation
import SwiftData

/// Servicio para exportar e importar datos de la aplicación en formato JSON.
/// Los datos nunca se envían a ningún servidor. El usuario controla manualmente
/// cuándo y dónde se exportan/importan.
enum DataExportService {

    /// Estructura raíz del archivo JSON exportado.
    /// Incluye tanto bancos como cuentas para una exportación completa.
    private struct ExportData: Codable {
        let version: Int
        let exportDate: Date
        let banks: [BankDTO]
        let accounts: [BankAccountDTO]
    }

    /// Nombre del archivo exportado.
    private static var exportFileName: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "Finance_backup_\(dateString).json"
    }

    /// URL temporal donde se guarda el archivo antes de compartir.
    static func getExportFileURL() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let files = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )
        // Devuelve el último archivo de backup generado
        return files?
            .filter { $0.lastPathComponent.hasPrefix("Finance_backup_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    // MARK: - Exportar

    /// Exporta todos los bancos y cuentas a un archivo JSON temporal.
    @discardableResult
    static func exportData(banks: [Bank], accounts: [BankAccount]) throws -> URL {
        let bankDTOs = banks.map { BankDTO(from: $0) }
        let accountDTOs = accounts.map { BankAccountDTO(from: $0) }

        let exportData = ExportData(
            version: 2,
            exportDate: Date(),
            banks: bankDTOs,
            accounts: accountDTOs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(exportData)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(exportFileName)
        try jsonData.write(to: fileURL)

        return fileURL
    }

    // MARK: - Importar

    /// Resultado de la importación: bancos y cuentas ya vinculados.
    struct ImportResult {
        let banks: [Bank]
        let accounts: [BankAccount]
    }

    /// Importa bancos y cuentas desde un archivo JSON.
    /// Vincula automáticamente cada cuenta con su banco correspondiente por UUID.
    static func importData(from url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let exportData = try decoder.decode(ExportData.self, from: data)

        // Crear los bancos
        let banks = exportData.banks.map { $0.toModel() }

        // Crear un diccionario de bancos por UUID para vincular
        let banksByID = Dictionary(uniqueKeysWithValues: banks.map { ($0.id, $0) })

        // Crear las cuentas y vincular cada una con su banco
        let accounts = exportData.accounts.map { dto -> BankAccount in
            let account = dto.toModel()
            if let bankId = dto.bankId {
                account.bank = banksByID[bankId]
            }
            return account
        }

        return ImportResult(banks: banks, accounts: accounts)
    }
}
