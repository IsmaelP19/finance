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
        let categories: [MovementCategoryDTO]
        let movements: [MovementDTO]
        let investmentSnapshots: [InvestmentSnapshotDTO]
        let recurringMovements: [RecurringMovementDTO]
        let budgets: [BudgetDTO]

        enum CodingKeys: String, CodingKey {
            case version
            case exportDate
            case banks
            case accounts
            case categories
            case movements
            case investmentSnapshots
            case recurringMovements
            case budgets
        }

        init(
            version: Int,
            exportDate: Date,
            banks: [BankDTO],
            accounts: [BankAccountDTO],
            categories: [MovementCategoryDTO],
            movements: [MovementDTO],
            investmentSnapshots: [InvestmentSnapshotDTO],
            recurringMovements: [RecurringMovementDTO],
            budgets: [BudgetDTO]
        ) {
            self.version = version
            self.exportDate = exportDate
            self.banks = banks
            self.accounts = accounts
            self.categories = categories
            self.movements = movements
            self.investmentSnapshots = investmentSnapshots
            self.recurringMovements = recurringMovements
            self.budgets = budgets
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(Int.self, forKey: .version)
            exportDate = try container.decode(Date.self, forKey: .exportDate)
            banks = try container.decode([BankDTO].self, forKey: .banks)
            accounts = try container.decode([BankAccountDTO].self, forKey: .accounts)
            categories = try container.decodeIfPresent([MovementCategoryDTO].self, forKey: .categories) ?? []
            movements = try container.decodeIfPresent([MovementDTO].self, forKey: .movements) ?? []
            investmentSnapshots = try container.decodeIfPresent([InvestmentSnapshotDTO].self, forKey: .investmentSnapshots) ?? []
            recurringMovements = try container.decodeIfPresent([RecurringMovementDTO].self, forKey: .recurringMovements) ?? []
            budgets = try container.decodeIfPresent([BudgetDTO].self, forKey: .budgets) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(version, forKey: .version)
            try container.encode(exportDate, forKey: .exportDate)
            try container.encode(banks, forKey: .banks)
            try container.encode(accounts, forKey: .accounts)
            try container.encode(categories, forKey: .categories)
            try container.encode(movements, forKey: .movements)
            try container.encode(investmentSnapshots, forKey: .investmentSnapshots)
            try container.encode(recurringMovements, forKey: .recurringMovements)
            try container.encode(budgets, forKey: .budgets)
        }
    }

    /// Nombre del archivo exportado con timestamp.
    private static var exportFileName: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmssSSS"
        let dateString = dateFormatter.string(from: Date())
        return "Finance_backup_\(dateString).json"
    }

    /// URL temporal donde se guarda el archivo antes de compartir.
    @MainActor static func getExportFileURL() -> URL? {
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

    /// Exporta todos los bancos, cuentas, categorías y movimientos a un archivo JSON temporal.
    @discardableResult
    @MainActor static func exportData(
        banks: [Bank],
        accounts: [BankAccount],
        categories: [MovementCategory],
        movements: [Movement],
        investmentSnapshots: [InvestmentSnapshot],
        recurringMovements: [RecurringMovement],
        budgets: [Budget],
        compact: Bool = false
    ) throws -> URL {
        let bankDTOs = banks.map { BankDTO(from: $0) }
        let accountDTOs = accounts.map { BankAccountDTO(from: $0) }
        let categoryDTOs = categories.map { MovementCategoryDTO(from: $0) }
        let movementDTOs = movements.map { MovementDTO(from: $0) }
        let snapshotDTOs = investmentSnapshots.map { InvestmentSnapshotDTO(from: $0) }
        let recurringDTOs = recurringMovements.map { RecurringMovementDTO(from: $0) }
        let budgetDTOs = budgets.map { BudgetDTO(from: $0) }

        let exportData = ExportData(
            version: 6,
            exportDate: Date(),
            banks: bankDTOs,
            accounts: accountDTOs,
            categories: categoryDTOs,
            movements: movementDTOs,
            investmentSnapshots: snapshotDTOs,
            recurringMovements: recurringDTOs,
            budgets: budgetDTOs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = compact ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(exportData)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(exportFileName)

        try jsonData.write(to: fileURL)

        return fileURL
    }

    /// Lee la fecha de exportación incluida dentro del JSON.
    @MainActor static func readExportDate(from url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let exportData = try? decoder.decode(ExportData.self, from: data) else { return nil }
        return exportData.exportDate
    }

    // MARK: - Importar

    /// Resultado de la importación: bancos y cuentas ya vinculados.
    struct ImportResult {
        let banks: [Bank]
        let accounts: [BankAccount]
        let categories: [MovementCategory]
        let movements: [Movement]
        let investmentSnapshots: [InvestmentSnapshot]
        let recurringMovements: [RecurringMovement]
        let budgets: [Budget]
    }

    /// Importa bancos, cuentas, categorías y movimientos desde un archivo JSON.
    /// Vincula automáticamente las relaciones por UUID.
    @MainActor static func importData(from url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let exportData = try decoder.decode(ExportData.self, from: data)

        // Crear bancos y categorías
        let banks = exportData.banks.map { $0.toModel() }
        let categories = exportData.categories.map { $0.toModel() }

        // Diccionarios por UUID para vincular relaciones
        let banksByID = Dictionary(uniqueKeysWithValues: banks.map { ($0.id, $0) })
        let categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        // Crear cuentas y vincular cada una con su banco
        let accounts = exportData.accounts.map { dto -> BankAccount in
            let account = dto.toModel()
            if let bankId = dto.bankId {
                account.bank = banksByID[bankId]
            }

            if account.accountType == .investment {
                if account.investedAmount == nil {
                    account.investedAmount = account.balance
                }
                if account.marketValue == nil {
                    account.marketValue = account.balance
                }
                if account.marketValueUpdatedAt == nil {
                    account.marketValueUpdatedAt = account.updatedAt
                }

                account.balance = account.effectiveMarketValue
            }

            return account
        }

        // Crear diccionario de cuentas para vincular movimientos
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })

        // Crear snapshots de inversión y vincular cuenta
        let snapshots = exportData.investmentSnapshots.map { dto -> InvestmentSnapshot in
            let snapshot = dto.toModel()
            if let accountId = dto.accountId {
                snapshot.account = accountsByID[accountId]
            }
            return snapshot
        }

        // Crear plantillas de movimientos recurrentes y vincular relaciones
        let recurringMovements = exportData.recurringMovements.map { dto -> RecurringMovement in
            let recurring = dto.toModel()
            if let accountId = dto.accountId {
                recurring.account = accountsByID[accountId]
            }
            if let categoryId = dto.categoryId {
                recurring.category = categoriesByID[categoryId]
            }
            return recurring
        }

        let budgets = exportData.budgets.map { $0.toModel() }
        let budgetsByID = Dictionary(uniqueKeysWithValues: budgets.map { ($0.id, $0) })

        for budgetDTO in exportData.budgets {
            guard let budget = budgetsByID[budgetDTO.id] else { continue }

            let linkedItems = budgetDTO.items.map { itemDTO -> BudgetItem in
                let item = itemDTO.toModel()
                if let categoryId = itemDTO.categoryId {
                    item.category = categoriesByID[categoryId]
                }
                item.budget = budget
                return item
            }

            budget.items = linkedItems
        }

        // Crear movimientos y vincular cuenta/categoría
        let movements = exportData.movements.map { dto -> Movement in
            let movement = dto.toModel()
            if let accountId = dto.accountId {
                movement.account = accountsByID[accountId]
            }
            if let destinationAccountId = dto.destinationAccountId {
                movement.destinationAccount = accountsByID[destinationAccountId]
            }
            if movement.type != .transfer, let categoryId = dto.categoryId {
                movement.category = categoriesByID[categoryId]
            } else if movement.type == .transfer {
                movement.category = nil
            }
            return movement
        }

        return ImportResult(
            banks: banks,
            accounts: accounts,
            categories: categories,
            movements: movements,
            investmentSnapshots: snapshots,
            recurringMovements: recurringMovements,
            budgets: budgets
        )
    }
}
