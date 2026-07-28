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
    enum ImportError: LocalizedError {
        case duplicateIdentifiers(String)
        case missingReference(entity: String, identifier: UUID, target: String)
        case invalidReference(entity: String, identifier: UUID, target: String)

        var errorDescription: String? {
            switch self {
            case .duplicateIdentifiers(let entity):
                return "La copia contiene identificadores UUID duplicados en \(entity)."
            case .missingReference(let entity, let identifier, let target):
                return "La copia contiene una referencia inexistente: \(entity) -> \(target) (\(identifier.uuidString))."
            case .invalidReference(let entity, let identifier, let target):
                return "La copia contiene una referencia no válida: \(entity) -> \(target) (\(identifier.uuidString))."
            }
        }
    }

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

    private struct ExportMetadata: Decodable {
        let exportDate: Date
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
            version: 8,
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

        guard let metadata = try? decoder.decode(ExportMetadata.self, from: data) else { return nil }
        return metadata.exportDate
    }

    /// Valida la estructura y las referencias del JSON sin crear ni normalizar modelos.
    @MainActor static func validateExportFile(from url: URL) throws {
        let exportData = try decodeExportData(from: url)
        try validateUniqueIdentifiers(in: exportData)
        try validateReferences(in: exportData)
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
        let repairedReferences: Int

        init(
            banks: [Bank],
            accounts: [BankAccount],
            categories: [MovementCategory],
            movements: [Movement],
            investmentSnapshots: [InvestmentSnapshot],
            recurringMovements: [RecurringMovement],
            budgets: [Budget],
            repairedReferences: Int = 0
        ) {
            self.banks = banks
            self.accounts = accounts
            self.categories = categories
            self.movements = movements
            self.investmentSnapshots = investmentSnapshots
            self.recurringMovements = recurringMovements
            self.budgets = budgets
            self.repairedReferences = repairedReferences
        }
    }

    enum ImportMode: Equatable {
        case merge
        case replace
    }

    struct ImportCounts {
        let banks: Int
        let accounts: Int
        let categories: Int
        let movements: Int
        let investmentSnapshots: Int
        let recurringMovements: Int
        let budgets: Int
        let budgetItems: Int

        var total: Int {
            banks + accounts + categories + movements + investmentSnapshots + recurringMovements + budgets + budgetItems
        }

        var breakdown: String {
            [
                formattedCount(banks, singular: "banco", plural: "bancos"),
                formattedCount(accounts, singular: "cuenta", plural: "cuentas"),
                formattedCount(categories, singular: "categoría", plural: "categorías"),
                formattedCount(movements, singular: "movimiento", plural: "movimientos"),
                formattedCount(investmentSnapshots, singular: "snapshot de inversión", plural: "snapshots de inversión"),
                formattedCount(recurringMovements, singular: "recurrencia", plural: "recurrencias"),
                formattedCount(budgets, singular: "presupuesto", plural: "presupuestos"),
                formattedCount(budgetItems, singular: "partida de presupuesto", plural: "partidas de presupuesto")
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }

        private func formattedCount(_ count: Int, singular: String, plural: String) -> String? {
            guard count > 0 else { return nil }
            return "\(count) \(count == 1 ? singular : plural)"
        }
    }

    struct ImportReport {
        let mode: ImportMode
        let imported: ImportCounts
        let conflicts: ImportCounts
        let repairedReferences: Int

        init(
            mode: ImportMode,
            imported: ImportCounts,
            conflicts: ImportCounts,
            repairedReferences: Int = 0
        ) {
            self.mode = mode
            self.imported = imported
            self.conflicts = conflicts
            self.repairedReferences = repairedReferences
        }

        var alertTitle: String {
            guard mode == .merge else { return "Restauración completada" }
            if imported.total == 0, conflicts.total > 0 { return "Importación sin cambios" }
            if imported.total > 0, conflicts.total > 0 { return "Importación parcial" }
            return "Importación completada"
        }

        var summary: String {
            let importedText = recordCountText(imported.total, breakdown: imported.breakdown)

            var summary = "\(importedText)."
            if mode == .merge, conflicts.total > 0 {
                let conflictWord = conflicts.total == 1 ? "conflicto local" : "conflictos locales"
                let conflictBreakdown = conflicts.breakdown.isEmpty ? "" : " (\(conflicts.breakdown))"
                summary += " Se conservaron \(conflicts.total) \(conflictWord)\(conflictBreakdown) y se omitieron los importados."
            }
            if repairedReferences > 0 {
                summary += " Se repararon \(repairedReferences) referencias opcionales inválidas."
            }
            return summary
        }

        private func recordCountText(_ count: Int, breakdown: String) -> String {
            let breakdownText = breakdown.isEmpty ? "" : " (\(breakdown))"
            switch count {
            case 0:
                return "No se incorporó ningún registro"
            case 1:
                return "Se incorporó 1 registro\(breakdownText)"
            default:
                return "Se incorporaron \(count) registros\(breakdownText)"
            }
        }
    }

    private struct LocalData {
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
        let exportData = try decodeExportData(from: url)
        try validateUniqueIdentifiers(in: exportData)
        try validateReferences(in: exportData)

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
            if recurring.account?.isArchived == true {
                recurring.isActive = false
                recurring.updatedAt = Date()
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

        let importedMovementByID = Dictionary(uniqueKeysWithValues: movements.map { ($0.id, $0) })
        let importedRecurringIDs = Set(recurringMovements.map(\.id))
        var repairedReferences = 0
        for movement in movements {
            if let recurringRuleID = movement.recurringRuleId,
               !importedRecurringIDs.contains(recurringRuleID) {
                movement.recurringRuleId = nil
                repairedReferences += 1
            }

            if let reimbursementForID = movement.reimbursementForId {
                let isValidReimbursement = movement.type == .income
                    && importedMovementByID[reimbursementForID]?.type == .expense
                if !isValidReimbursement {
                    movement.reimbursementForId = nil
                    repairedReferences += 1
                }
            }
        }

        return ImportResult(
            banks: banks,
            accounts: accounts,
            categories: categories,
            movements: movements,
            investmentSnapshots: snapshots,
            recurringMovements: recurringMovements,
            budgets: budgets,
            repairedReferences: repairedReferences
        )
    }

    private static func decodeExportData(from url: URL) throws -> ExportData {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportData.self, from: data)
    }

    /// Incorpora o reemplaza datos ya decodificados de forma transaccional.
    /// Los conflictos en modo merge se determinan únicamente por UUID.
    @MainActor
    @discardableResult
    static func importData(
        _ importResult: ImportResult,
        into modelContext: ModelContext,
        mode: ImportMode,
        currencyCode: String
    ) throws -> ImportReport {
        do {
            let localData = try fetchLocalData(in: modelContext)
            let localBankIDs = Set(localData.banks.map(\.id))
            let localAccountIDs = Set(localData.accounts.map(\.id))
            let localCategoryIDs = Set(localData.categories.map(\.id))
            let localMovementIDs = Set(localData.movements.map(\.id))
            let localSnapshotIDs = Set(localData.investmentSnapshots.map(\.id))
            let localRecurringIDs = Set(localData.recurringMovements.map(\.id))
            let localBudgetIDs = Set(localData.budgets.map(\.id))
            let localBudgetItemIDs = Set(localData.budgets.flatMap(\.items).map(\.id))

            let conflicts = ImportCounts(
                banks: mode == .merge ? importResult.banks.filter { localBankIDs.contains($0.id) }.count : 0,
                accounts: mode == .merge ? importResult.accounts.filter { localAccountIDs.contains($0.id) }.count : 0,
                categories: mode == .merge ? importResult.categories.filter { localCategoryIDs.contains($0.id) }.count : 0,
                movements: mode == .merge ? importResult.movements.filter { localMovementIDs.contains($0.id) }.count : 0,
                investmentSnapshots: mode == .merge ? importResult.investmentSnapshots.filter { localSnapshotIDs.contains($0.id) }.count : 0,
                recurringMovements: mode == .merge ? importResult.recurringMovements.filter { localRecurringIDs.contains($0.id) }.count : 0,
                budgets: mode == .merge ? importResult.budgets.filter { localBudgetIDs.contains($0.id) }.count : 0,
                budgetItems: mode == .merge
                    ? importResult.budgets
                        .filter { !localBudgetIDs.contains($0.id) }
                        .flatMap(\.items)
                        .filter { localBudgetItemIDs.contains($0.id) }
                        .count
                    : 0
            )

            if mode == .replace {
                deleteAll(localData, from: modelContext)
            }

            var banksByID = mode == .merge
                ? Dictionary(uniqueKeysWithValues: localData.banks.map { ($0.id, $0) })
                : [:]
            for bank in importResult.banks where mode == .replace || !localBankIDs.contains(bank.id) {
                modelContext.insert(bank)
                banksByID[bank.id] = bank
            }

            var categoriesByID = mode == .merge
                ? Dictionary(uniqueKeysWithValues: localData.categories.map { ($0.id, $0) })
                : [:]
            for category in importResult.categories where mode == .replace || !localCategoryIDs.contains(category.id) {
                modelContext.insert(category)
                categoriesByID[category.id] = category
            }

            var accountsByID = mode == .merge
                ? Dictionary(uniqueKeysWithValues: localData.accounts.map { ($0.id, $0) })
                : [:]
            for account in importResult.accounts where mode == .replace || !localAccountIDs.contains(account.id) {
                account.bank = account.bank.flatMap { banksByID[$0.id] }
                account.currency = currencyCode
                modelContext.insert(account)
                accountsByID[account.id] = account
            }

            var snapshotsImported = 0
            for snapshot in importResult.investmentSnapshots where mode == .replace || !localSnapshotIDs.contains(snapshot.id) {
                snapshot.account = snapshot.account.flatMap { accountsByID[$0.id] }
                modelContext.insert(snapshot)
                snapshotsImported += 1
            }

            var recurringImported = 0
            for recurring in importResult.recurringMovements where mode == .replace || !localRecurringIDs.contains(recurring.id) {
                recurring.account = recurring.account.flatMap { accountsByID[$0.id] }
                recurring.category = recurring.category.flatMap { categoriesByID[$0.id] }
                modelContext.insert(recurring)
                recurringImported += 1
            }

            var budgetsImported = 0
            var budgetItemsImported = 0
            for budget in importResult.budgets where mode == .replace || !localBudgetIDs.contains(budget.id) {
                let itemsToImport = budget.items.filter { mode == .replace || !localBudgetItemIDs.contains($0.id) }
                for item in itemsToImport {
                    item.category = item.category.flatMap { categoriesByID[$0.id] }
                }
                budget.items = itemsToImport
                modelContext.insert(budget)
                budgetsImported += 1
                budgetItemsImported += itemsToImport.count
            }

            var movementsImported = 0
            var incorporatedMovements: [Movement] = []
            for movement in importResult.movements where mode == .replace || !localMovementIDs.contains(movement.id) {
                let sourceAccount = movement.account.flatMap { accountsByID[$0.id] }
                let destinationAccount = movement.destinationAccount.flatMap { accountsByID[$0.id] }
                let category = movement.category.flatMap { categoriesByID[$0.id] }

                // Detach the decoded graph before inserting the movement. In merge mode,
                // the source can be a conflicting account that must never be inserted.
                movement.account = nil
                movement.destinationAccount = nil
                movement.category = nil
                movement.account = sourceAccount
                movement.destinationAccount = destinationAccount
                movement.category = category
                modelContext.insert(movement)
                movementsImported += 1
                incorporatedMovements.append(movement)
            }

            if mode == .merge {
                applyImportedMovementImpacts(
                    incorporatedMovements,
                    localAccountIDs: localAccountIDs
                )
            }

            let imported = ImportCounts(
                banks: importResult.banks.filter { mode == .replace || !localBankIDs.contains($0.id) }.count,
                accounts: importResult.accounts.filter { mode == .replace || !localAccountIDs.contains($0.id) }.count,
                categories: importResult.categories.filter { mode == .replace || !localCategoryIDs.contains($0.id) }.count,
                movements: movementsImported,
                investmentSnapshots: snapshotsImported,
                recurringMovements: recurringImported,
                budgets: budgetsImported,
                budgetItems: budgetItemsImported
            )

            _ = try MovementBalanceService.rebuild(in: modelContext)
            try modelContext.save()

            return ImportReport(
                mode: mode,
                imported: imported,
                conflicts: conflicts,
                repairedReferences: importResult.repairedReferences
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func fetchLocalData(in modelContext: ModelContext) throws -> LocalData {
        LocalData(
            banks: try modelContext.fetch(FetchDescriptor<Bank>()),
            accounts: try modelContext.fetch(FetchDescriptor<BankAccount>()),
            categories: try modelContext.fetch(FetchDescriptor<MovementCategory>()),
            movements: try modelContext.fetch(FetchDescriptor<Movement>()),
            investmentSnapshots: try modelContext.fetch(FetchDescriptor<InvestmentSnapshot>()),
            recurringMovements: try modelContext.fetch(FetchDescriptor<RecurringMovement>()),
            budgets: try modelContext.fetch(FetchDescriptor<Budget>())
        )
    }

    private static func validateUniqueIdentifiers(in exportData: ExportData) throws {
        try validateUniqueIdentifiers(exportData.banks.map(\.id), entity: "bancos")
        try validateUniqueIdentifiers(exportData.accounts.map(\.id), entity: "cuentas")
        try validateUniqueIdentifiers(exportData.categories.map(\.id), entity: "categorías")
        try validateUniqueIdentifiers(exportData.movements.map(\.id), entity: "movimientos")
        try validateUniqueIdentifiers(exportData.investmentSnapshots.map(\.id), entity: "snapshots de inversión")
        try validateUniqueIdentifiers(exportData.recurringMovements.map(\.id), entity: "recurrencias")
        try validateUniqueIdentifiers(exportData.budgets.map(\.id), entity: "presupuestos")
        try validateUniqueIdentifiers(
            exportData.budgets.flatMap(\.items).map(\.id),
            entity: "BudgetItems"
        )
    }

    private static func validateUniqueIdentifiers(_ identifiers: [UUID], entity: String) throws {
        guard Set(identifiers).count == identifiers.count else {
            throw ImportError.duplicateIdentifiers(entity)
        }
    }

    private static func validateReferences(in exportData: ExportData) throws {
        let bankIDs = Set(exportData.banks.map(\.id))
        let accountIDs = Set(exportData.accounts.map(\.id))
        let categoryIDs = Set(exportData.categories.map(\.id))

        for account in exportData.accounts {
            if let bankID = account.bankId, !bankIDs.contains(bankID) {
                throw ImportError.missingReference(entity: "cuenta \(account.id.uuidString)", identifier: bankID, target: "banco")
            }
        }

        for movement in exportData.movements {
            if let accountID = movement.accountId, !accountIDs.contains(accountID) {
                throw ImportError.missingReference(entity: "movimiento \(movement.id.uuidString)", identifier: accountID, target: "cuenta origen")
            }
            if let destinationID = movement.destinationAccountId, !accountIDs.contains(destinationID) {
                throw ImportError.missingReference(entity: "movimiento \(movement.id.uuidString)", identifier: destinationID, target: "cuenta destino")
            }
            if movement.type != MovementType.transfer.rawValue,
               let categoryID = movement.categoryId,
               !categoryIDs.contains(categoryID) {
                throw ImportError.missingReference(entity: "movimiento \(movement.id.uuidString)", identifier: categoryID, target: "categoría")
            }
        }

        for snapshot in exportData.investmentSnapshots {
            if let accountID = snapshot.accountId, !accountIDs.contains(accountID) {
                throw ImportError.missingReference(entity: "snapshot \(snapshot.id.uuidString)", identifier: accountID, target: "cuenta")
            }
        }

        for recurring in exportData.recurringMovements {
            if let accountID = recurring.accountId, !accountIDs.contains(accountID) {
                throw ImportError.missingReference(entity: "recurrencia \(recurring.id.uuidString)", identifier: accountID, target: "cuenta")
            }
            if let categoryID = recurring.categoryId, !categoryIDs.contains(categoryID) {
                throw ImportError.missingReference(entity: "recurrencia \(recurring.id.uuidString)", identifier: categoryID, target: "categoría")
            }
        }

        for budget in exportData.budgets {
            for item in budget.items {
                if let categoryID = item.categoryId, !categoryIDs.contains(categoryID) {
                    throw ImportError.missingReference(entity: "BudgetItem \(item.id.uuidString)", identifier: categoryID, target: "categoría")
                }
            }
        }
    }

    @MainActor
    private static func applyImportedMovementImpacts(
        _ movements: [Movement],
        localAccountIDs: Set<UUID>
    ) {
        for movement in movements.sorted(by: chronologicalMovementOrder) {
            guard let sourceAccount = movement.account,
                  localAccountIDs.contains(sourceAccount.id) else {
                if movement.type == .transfer,
                   let destinationAccount = movement.destinationAccount,
                   localAccountIDs.contains(destinationAccount.id) {
                    let investedAmountBeforeImpact = destinationAccount.effectiveInvestedAmount
                    destinationAccount.balance += movement.amount
                    if destinationAccount.isInvestmentAccount {
                        destinationAccount.investedAmount = investedAmountBeforeImpact + movement.amount
                    }
                    destinationAccount.updatedAt = Date()
                }
                continue
            }

            switch movement.type {
            case .expense:
                sourceAccount.balance -= movement.amount
            case .income:
                sourceAccount.balance += movement.amount
            case .transfer:
                let investedAmountBeforeImpact = sourceAccount.effectiveInvestedAmount
                sourceAccount.balance -= movement.amount
                if sourceAccount.isInvestmentAccount {
                    sourceAccount.investedAmount = max(0, investedAmountBeforeImpact - movement.amount)
                }
                if let destinationAccount = movement.destinationAccount,
                   localAccountIDs.contains(destinationAccount.id) {
                    let investedAmountBeforeImpact = destinationAccount.effectiveInvestedAmount
                    destinationAccount.balance += movement.amount
                    if destinationAccount.isInvestmentAccount {
                        destinationAccount.investedAmount = investedAmountBeforeImpact + movement.amount
                    }
                    destinationAccount.updatedAt = Date()
                }
            }

            sourceAccount.updatedAt = Date()
        }
    }

    @MainActor
    private static func chronologicalMovementOrder(_ lhs: Movement, _ rhs: Movement) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func deleteAll(_ localData: LocalData, from modelContext: ModelContext) {
        localData.movements.forEach { modelContext.delete($0) }
        localData.investmentSnapshots.forEach { modelContext.delete($0) }
        localData.recurringMovements.forEach { modelContext.delete($0) }
        localData.budgets.forEach { modelContext.delete($0) }
        localData.categories.forEach { modelContext.delete($0) }
        localData.accounts.forEach { modelContext.delete($0) }
        localData.banks.forEach { modelContext.delete($0) }
    }
}
