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
private extension BankDTO {
    nonisolated init(id: UUID, name: String, icon: String, color: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
    }
}

private extension BankAccountDTO {
    nonisolated init(
        id: UUID,
        name: String,
        bankId: UUID?,
        accountType: String,
        balance: Decimal,
        currency: String,
        notes: String,
        investedAmount: Decimal?,
        marketValue: Decimal?,
        marketValueUpdatedAt: Date?,
        isArchived: Bool,
        archivedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.bankId = bankId
        self.accountType = accountType
        self.balance = balance
        self.currency = currency
        self.notes = notes
        self.investedAmount = investedAmount
        self.marketValue = marketValue
        self.marketValueUpdatedAt = marketValueUpdatedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

private extension MovementCategoryDTO {
    nonisolated init(id: UUID, name: String, icon: String, color: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
    }
}

private extension MovementDTO {
    nonisolated init(
        id: UUID,
        concept: String,
        amount: Decimal,
        type: String,
        occurredAt: Date,
        notes: String,
        resultingBalance: Decimal?,
        recurringRuleId: UUID?,
        recurringScheduledAt: Date?,
        personalAmount: Decimal?,
        reimbursementForId: UUID?,
        createdAt: Date,
        updatedAt: Date,
        accountId: UUID?,
        destinationAccountId: UUID?,
        categoryId: UUID?
    ) {
        self.id = id
        self.concept = concept
        self.amount = amount
        self.type = type
        self.occurredAt = occurredAt
        self.notes = notes
        self.resultingBalance = resultingBalance
        self.recurringRuleId = recurringRuleId
        self.recurringScheduledAt = recurringScheduledAt
        self.personalAmount = personalAmount
        self.reimbursementForId = reimbursementForId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.accountId = accountId
        self.destinationAccountId = destinationAccountId
        self.categoryId = categoryId
    }
}

private extension InvestmentSnapshotDTO {
    nonisolated init(
        id: UUID,
        snapshotDate: Date,
        investedAmount: Decimal,
        marketValue: Decimal,
        createdAt: Date,
        updatedAt: Date,
        accountId: UUID?
    ) {
        self.id = id
        self.snapshotDate = snapshotDate
        self.investedAmount = investedAmount
        self.marketValue = marketValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.accountId = accountId
    }
}

private extension RecurringMovementDTO {
    nonisolated init(
        id: UUID,
        concept: String,
        amount: Decimal,
        type: String,
        frequency: String,
        dayOfMonth: Int,
        startDate: Date,
        endDate: Date?,
        notes: String,
        isActive: Bool,
        skippedOccurrenceDates: [Date],
        createdAt: Date,
        updatedAt: Date,
        accountId: UUID?,
        categoryId: UUID?
    ) {
        self.id = id
        self.concept = concept
        self.amount = amount
        self.type = type
        self.frequency = frequency
        self.dayOfMonth = dayOfMonth
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.isActive = isActive
        self.skippedOccurrenceDates = skippedOccurrenceDates
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.accountId = accountId
        self.categoryId = categoryId
    }
}

private extension BudgetItemDTO {
    nonisolated init(id: UUID, allocatedAmount: Decimal, createdAt: Date, categoryId: UUID?) {
        self.id = id
        self.allocatedAmount = allocatedAmount
        self.createdAt = createdAt
        self.categoryId = categoryId
    }
}

private extension BudgetDTO {
    nonisolated init(
        id: UUID,
        totalAmount: Decimal,
        isActive: Bool,
        notifyAt80Percent: Bool,
        notifyAt100Percent: Bool,
        createdAt: Date,
        updatedAt: Date,
        items: [BudgetItemDTO]
    ) {
        self.id = id
        self.totalAmount = totalAmount
        self.isActive = isActive
        self.notifyAt80Percent = notifyAt80Percent
        self.notifyAt100Percent = notifyAt100Percent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }
}

private nonisolated enum ExportFileSerializationLock {
    static let value = NSLock()
}

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
    private nonisolated struct ExportData: Codable, Sendable {
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

    private nonisolated struct ExportMetadata: Decodable, Sendable {
        let exportDate: Date
    }

    /// Captura puntual de los modelos necesarios para una operación de datos.
    /// No se mantiene como estado observable de ninguna vista.
    struct DataSnapshot {
        let banks: [Bank]
        let accounts: [BankAccount]
        let categories: [MovementCategory]
        let movements: [Movement]
        let investmentSnapshots: [InvestmentSnapshot]
        let recurringMovements: [RecurringMovement]
        let budgets: [Budget]
    }

    /// Huella efímera del estado que se leyó antes de una operación asíncrona.
    /// No se persiste: solo evita aplicar una restauración sobre cambios locales
    /// que ocurrieron mientras se decodificaba o escribía el backup previo.
    struct DataRevision: Equatable, Sendable {
        fileprivate let digest: Int
    }

    // Estas estructuras solo contienen valores Sendable. La lectura de los
    // modelos se hace en MainActor y todo el trabajo de conversión/hashing se
    // puede ejecutar después sin transportar objetos SwiftData entre actores.
    private struct RawBank: Sendable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let createdAt: Date
    }

    private struct RawAccount: Sendable {
        let id: UUID
        let name: String
        let bankId: UUID?
        let accountType: String
        let balance: Decimal
        let currency: String
        let notes: String
        let investedAmount: Decimal?
        let marketValue: Decimal?
        let marketValueUpdatedAt: Date?
        let isArchived: Bool
        let archivedAt: Date?
        let createdAt: Date
        let updatedAt: Date
    }

    private struct RawCategory: Sendable {
        let id: UUID
        let name: String
        let icon: String
        let color: String
        let createdAt: Date
    }

    private struct RawMovement: Sendable {
        let id: UUID
        let concept: String
        let amount: Decimal
        let type: String
        let occurredAt: Date
        let notes: String
        let resultingBalance: Decimal?
        let recurringRuleId: UUID?
        let recurringScheduledAt: Date?
        let personalAmount: Decimal?
        let reimbursementForId: UUID?
        let createdAt: Date
        let updatedAt: Date
        let accountId: UUID?
        let destinationAccountId: UUID?
        let categoryId: UUID?
    }

    private struct RawInvestmentSnapshot: Sendable {
        let id: UUID
        let snapshotDate: Date
        let investedAmount: Decimal
        let marketValue: Decimal
        let createdAt: Date
        let updatedAt: Date
        let accountId: UUID?
    }

    private struct RawRecurringMovement: Sendable {
        let id: UUID
        let concept: String
        let amount: Decimal
        let type: String
        let frequency: String
        let dayOfMonth: Int
        let startDate: Date
        let endDate: Date?
        let notes: String
        let isActive: Bool
        let skippedOccurrenceDatesData: Data
        let createdAt: Date
        let updatedAt: Date
        let accountId: UUID?
        let categoryId: UUID?
    }

    private struct RawBudgetItem: Sendable {
        let id: UUID
        let allocatedAmount: Decimal
        let createdAt: Date
        let categoryId: UUID?
    }

    private struct RawBudget: Sendable {
        let id: UUID
        let totalAmount: Decimal
        let isActive: Bool
        let notifyAt80Percent: Bool
        let notifyAt100Percent: Bool
        let createdAt: Date
        let updatedAt: Date
        let items: [RawBudgetItem]
    }

    private struct RawExportSnapshot: Sendable {
        let banks: [RawBank]
        let accounts: [RawAccount]
        let categories: [RawCategory]
        let movements: [RawMovement]
        let investmentSnapshots: [RawInvestmentSnapshot]
        let recurringMovements: [RawRecurringMovement]
        let budgets: [RawBudget]
    }

    /// Nombre del archivo exportado con timestamp.
    private nonisolated static var exportFileName: String {
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

    @MainActor
    static func fetchSnapshot(in modelContext: ModelContext) throws -> DataSnapshot {
        DataSnapshot(
            banks: try modelContext.fetch(
                FetchDescriptor<Bank>(sortBy: [SortDescriptor(\Bank.name)])
            ),
            accounts: try modelContext.fetch(
                FetchDescriptor<BankAccount>(sortBy: [SortDescriptor(\BankAccount.name)])
            ),
            categories: try modelContext.fetch(
                FetchDescriptor<MovementCategory>(sortBy: [SortDescriptor(\MovementCategory.name)])
            ),
            movements: try modelContext.fetch(
                FetchDescriptor<Movement>(sortBy: [SortDescriptor(\Movement.occurredAt, order: .reverse)])
            ),
            investmentSnapshots: try modelContext.fetch(
                FetchDescriptor<InvestmentSnapshot>(sortBy: [SortDescriptor(\InvestmentSnapshot.snapshotDate, order: .reverse)])
            ),
            recurringMovements: try modelContext.fetch(
                FetchDescriptor<RecurringMovement>(sortBy: [SortDescriptor(\RecurringMovement.updatedAt, order: .reverse)])
            ),
            budgets: try modelContext.fetch(
                FetchDescriptor<Budget>(sortBy: [SortDescriptor(\Budget.createdAt)])
            )
        )
    }

    @MainActor
    static func fetchBankAccounts(in modelContext: ModelContext) throws -> [BankAccount] {
        try modelContext.fetch(
            FetchDescriptor<BankAccount>(sortBy: [SortDescriptor(\BankAccount.name)])
        )
    }

    @MainActor
    static func fetchMovementCount(in modelContext: ModelContext) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Movement>())
    }

    @MainActor
    static func revision(in modelContext: ModelContext) throws -> DataRevision {
        revision(of: try fetchSnapshot(in: modelContext))
    }

    /// Variante asíncrona: la lectura de modelos permanece en MainActor, pero
    /// DTOs, hashing y el resto del cálculo se ejecutan fuera de él.
    @MainActor
    static func revisionAsync(in modelContext: ModelContext) async throws -> DataRevision {
        try await revisionAsync(of: fetchSnapshot(in: modelContext))
    }

    /// Calcula la huella de forma síncrona para los wrappers existentes.
    @MainActor
    static func revision(of snapshot: DataSnapshot) -> DataRevision {
        makeDataRevision(from: makeRawExportSnapshot(from: snapshot))
    }

    /// Calcula la huella sin pasar modelos SwiftData a la tarea en segundo plano.
    @MainActor
    static func revisionAsync(of snapshot: DataSnapshot) async -> DataRevision {
        let rawSnapshot = makeRawExportSnapshot(from: snapshot)
        let task = Task.detached(priority: .utility) {
            makeDataRevision(from: rawSnapshot)
        }
        return await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    @MainActor
    private static func makeRawExportSnapshot(from snapshot: DataSnapshot) -> RawExportSnapshot {
        RawExportSnapshot(
            banks: snapshot.banks.map {
                RawBank(
                    id: $0.id,
                    name: $0.name,
                    icon: $0.iconRaw,
                    color: $0.colorRaw,
                    createdAt: $0.createdAt
                )
            },
            accounts: snapshot.accounts.map {
                RawAccount(
                    id: $0.id,
                    name: $0.name,
                    bankId: $0.bank?.id,
                    accountType: $0.accountTypeRaw,
                    balance: $0.balance,
                    currency: $0.currency,
                    notes: $0.notes,
                    investedAmount: $0.investedAmount,
                    marketValue: $0.marketValue,
                    marketValueUpdatedAt: $0.marketValueUpdatedAt,
                    isArchived: $0.isArchived,
                    archivedAt: $0.archivedAt,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            categories: snapshot.categories.map {
                RawCategory(
                    id: $0.id,
                    name: $0.name,
                    icon: $0.iconRaw ?? CategoryIcon.tag.rawValue,
                    color: $0.colorRaw ?? CategoryColor.blue.rawValue,
                    createdAt: $0.createdAt
                )
            },
            movements: snapshot.movements.map {
                RawMovement(
                    id: $0.id,
                    concept: $0.concept,
                    amount: $0.amount,
                    type: $0.typeRaw,
                    occurredAt: $0.occurredAt,
                    notes: $0.notes,
                    resultingBalance: $0.resultingBalance,
                    recurringRuleId: $0.recurringRuleId,
                    recurringScheduledAt: $0.recurringScheduledAt,
                    personalAmount: $0.personalAmount,
                    reimbursementForId: $0.reimbursementForId,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountId: $0.account?.id,
                    destinationAccountId: $0.destinationAccount?.id,
                    categoryId: $0.category?.id
                )
            },
            investmentSnapshots: snapshot.investmentSnapshots.map {
                RawInvestmentSnapshot(
                    id: $0.id,
                    snapshotDate: $0.snapshotDate,
                    investedAmount: $0.investedAmount,
                    marketValue: $0.marketValue,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountId: $0.account?.id
                )
            },
            recurringMovements: snapshot.recurringMovements.map {
                RawRecurringMovement(
                    id: $0.id,
                    concept: $0.concept,
                    amount: $0.amount,
                    type: $0.typeRaw,
                    frequency: $0.frequencyRaw,
                    dayOfMonth: $0.dayOfMonth,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    notes: $0.notes,
                    isActive: $0.isActive,
                    skippedOccurrenceDatesData: $0.skippedOccurrenceDatesData,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountId: $0.account?.id,
                    categoryId: $0.category?.id
                )
            },
            budgets: snapshot.budgets.map {
                RawBudget(
                    id: $0.id,
                    totalAmount: $0.totalAmount,
                    isActive: $0.isActive,
                    notifyAt80Percent: $0.notifyAt80Percent,
                    notifyAt100Percent: $0.notifyAt100Percent,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    items: $0.items.map {
                        RawBudgetItem(
                            id: $0.id,
                            allocatedAmount: $0.allocatedAmount,
                            createdAt: $0.createdAt,
                            categoryId: $0.category?.id
                        )
                    }
                )
            }
        )
    }

    private nonisolated static func makeDataRevision(from raw: RawExportSnapshot) -> DataRevision {
        var hasher = Hasher()

        func combineCollection<T>(_ name: String, _ values: [T], _ combine: (inout Hasher, T) -> Void) {
            hasher.combine(name)
            hasher.combine(values.count)
            for value in values {
                hasher.combine(name)
                combine(&hasher, value)
            }
            hasher.combine("end_\(name)")
        }

        let banks = raw.banks.sorted { $0.id.uuidString < $1.id.uuidString }
        combineCollection("banks", banks) { hasher, bank in
            hasher.combine(bank.id)
            hasher.combine(bank.name)
            hasher.combine(bank.icon)
            hasher.combine(bank.color)
            hasher.combine(bank.createdAt)
        }

        let accounts = raw.accounts.sorted { $0.id.uuidString < $1.id.uuidString }
        combineCollection("accounts", accounts) { hasher, account in
            hasher.combine(account.id)
            hasher.combine(account.name)
            hasher.combine(account.bankId)
            hasher.combine(account.accountType)
            hasher.combine(account.balance)
            hasher.combine(account.currency)
            hasher.combine(account.notes)
            hasher.combine(account.investedAmount)
            hasher.combine(account.marketValue)
            hasher.combine(account.marketValueUpdatedAt)
            hasher.combine(account.isArchived)
            hasher.combine(account.archivedAt)
            hasher.combine(account.createdAt)
            hasher.combine(account.updatedAt)
        }

        let categories = raw.categories.sorted { $0.id.uuidString < $1.id.uuidString }
        combineCollection("categories", categories) { hasher, category in
            hasher.combine(category.id)
            hasher.combine(category.name)
            hasher.combine(category.icon)
            hasher.combine(category.color)
            hasher.combine(category.createdAt)
        }

        let movements = raw.movements.sorted { $0.id.uuidString < $1.id.uuidString }
        combineCollection("movements", movements) { hasher, movement in
            hasher.combine(movement.id)
            hasher.combine(movement.concept)
            hasher.combine(movement.amount)
            hasher.combine(movement.type)
            hasher.combine(movement.occurredAt)
            hasher.combine(movement.notes)
            hasher.combine(movement.resultingBalance)
            hasher.combine(movement.recurringRuleId)
            hasher.combine(movement.recurringScheduledAt)
            hasher.combine(movement.personalAmount)
            hasher.combine(movement.reimbursementForId)
            hasher.combine(movement.createdAt)
            hasher.combine(movement.updatedAt)
            hasher.combine(movement.accountId)
            hasher.combine(movement.destinationAccountId)
            hasher.combine(movement.categoryId)
        }

        let snapshots = raw.investmentSnapshots.sorted { $0.id.uuidString < $1.id.uuidString }
        combineCollection("investmentSnapshots", snapshots) { hasher, snapshot in
            hasher.combine(snapshot.id)
            hasher.combine(snapshot.snapshotDate)
            hasher.combine(snapshot.investedAmount)
            hasher.combine(snapshot.marketValue)
            hasher.combine(snapshot.createdAt)
            hasher.combine(snapshot.updatedAt)
            hasher.combine(snapshot.accountId)
        }

        let recurringMovements = raw.recurringMovements.sorted { $0.id.uuidString < $1.id.uuidString }
        combineCollection("recurringMovements", recurringMovements) { hasher, recurring in
            hasher.combine(recurring.id)
            hasher.combine(recurring.concept)
            hasher.combine(recurring.amount)
            hasher.combine(recurring.type)
            hasher.combine(recurring.frequency)
            hasher.combine(recurring.dayOfMonth)
            hasher.combine(recurring.startDate)
            hasher.combine(recurring.endDate)
            hasher.combine(recurring.notes)
            hasher.combine(recurring.isActive)
            hasher.combine(decodeSkippedOccurrenceDates(from: recurring.skippedOccurrenceDatesData).sorted())
            hasher.combine(recurring.createdAt)
            hasher.combine(recurring.updatedAt)
            hasher.combine(recurring.accountId)
            hasher.combine(recurring.categoryId)
        }

        let budgets = raw.budgets.sorted { $0.id.uuidString < $1.id.uuidString }
        combineCollection("budgets", budgets) { hasher, budget in
            hasher.combine(budget.id)
            hasher.combine(budget.totalAmount)
            hasher.combine(budget.isActive)
            hasher.combine(budget.notifyAt80Percent)
            hasher.combine(budget.notifyAt100Percent)
            hasher.combine(budget.createdAt)
            hasher.combine(budget.updatedAt)

            let items = budget.items.sorted { $0.id.uuidString < $1.id.uuidString }
            hasher.combine("budgetItems")
            hasher.combine(items.count)
            for item in items {
                hasher.combine("budgetItem")
                hasher.combine(item.id)
                hasher.combine(item.allocatedAmount)
                hasher.combine(item.createdAt)
                hasher.combine(item.categoryId)
            }
            hasher.combine("end_budgetItems")
        }

        return DataRevision(digest: hasher.finalize())
    }

    private nonisolated static func decodeSkippedOccurrenceDates(from data: Data) -> [Date] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([Date].self, from: data)) ?? []
    }

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
        let snapshot = DataSnapshot(
            banks: banks,
            accounts: accounts,
            categories: categories,
            movements: movements,
            investmentSnapshots: investmentSnapshots,
            recurringMovements: recurringMovements,
            budgets: budgets
        )
        let rawSnapshot = makeRawExportSnapshot(from: snapshot)
        return try writeExportData(makeExportData(from: rawSnapshot), compact: compact)
    }

    /// Variante asíncrona compatible con las acciones de UI. La captura de modelos
    /// ocurre en el actor correcto; el JSON y la escritura temporal se delegan.
    @MainActor
    @discardableResult
    static func exportDataAsync(
        snapshot: DataSnapshot,
        compact: Bool = false
    ) async throws -> URL {
        let rawSnapshot = makeRawExportSnapshot(from: snapshot)
        let task = Task.detached(priority: .utility) { () throws -> URL in
            try Task.checkCancellation()
            return try writeExportData(makeExportData(from: rawSnapshot), compact: compact)
        }
        return try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
    }

    private nonisolated static func makeExportData(from raw: RawExportSnapshot) -> ExportData {
        ExportData(
            version: 8,
            exportDate: Date(),
            banks: raw.banks.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                BankDTO(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color, createdAt: $0.createdAt)
            },
            accounts: raw.accounts.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                BankAccountDTO(
                    id: $0.id,
                    name: $0.name,
                    bankId: $0.bankId,
                    accountType: $0.accountType,
                    balance: $0.balance,
                    currency: $0.currency,
                    notes: $0.notes,
                    investedAmount: $0.investedAmount,
                    marketValue: $0.marketValue,
                    marketValueUpdatedAt: $0.marketValueUpdatedAt,
                    isArchived: $0.isArchived,
                    archivedAt: $0.archivedAt,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            },
            categories: raw.categories.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                MovementCategoryDTO(id: $0.id, name: $0.name, icon: $0.icon, color: $0.color, createdAt: $0.createdAt)
            },
            movements: raw.movements.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                MovementDTO(
                    id: $0.id,
                    concept: $0.concept,
                    amount: $0.amount,
                    type: $0.type,
                    occurredAt: $0.occurredAt,
                    notes: $0.notes,
                    resultingBalance: $0.resultingBalance,
                    recurringRuleId: $0.recurringRuleId,
                    recurringScheduledAt: $0.recurringScheduledAt,
                    personalAmount: $0.personalAmount,
                    reimbursementForId: $0.reimbursementForId,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountId: $0.accountId,
                    destinationAccountId: $0.destinationAccountId,
                    categoryId: $0.categoryId
                )
            },
            investmentSnapshots: raw.investmentSnapshots.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                InvestmentSnapshotDTO(
                    id: $0.id,
                    snapshotDate: $0.snapshotDate,
                    investedAmount: $0.investedAmount,
                    marketValue: $0.marketValue,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountId: $0.accountId
                )
            },
            recurringMovements: raw.recurringMovements.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                RecurringMovementDTO(
                    id: $0.id,
                    concept: $0.concept,
                    amount: $0.amount,
                    type: $0.type,
                    frequency: $0.frequency,
                    dayOfMonth: $0.dayOfMonth,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    notes: $0.notes,
                    isActive: $0.isActive,
                    skippedOccurrenceDates: decodeSkippedOccurrenceDates(from: $0.skippedOccurrenceDatesData).sorted(),
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    accountId: $0.accountId,
                    categoryId: $0.categoryId
                )
            },
            budgets: raw.budgets.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                BudgetDTO(
                    id: $0.id,
                    totalAmount: $0.totalAmount,
                    isActive: $0.isActive,
                    notifyAt80Percent: $0.notifyAt80Percent,
                    notifyAt100Percent: $0.notifyAt100Percent,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    items: $0.items.sorted { $0.id.uuidString < $1.id.uuidString }.map {
                        BudgetItemDTO(
                            id: $0.id,
                            allocatedAmount: $0.allocatedAmount,
                            createdAt: $0.createdAt,
                            categoryId: $0.categoryId
                        )
                    }
                )
            }
        )
    }

    private nonisolated static func writeExportData(_ exportData: ExportData, compact: Bool) throws -> URL {
        ExportFileSerializationLock.value.lock()
        defer { ExportFileSerializationLock.value.unlock() }

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
    nonisolated static func readExportDate(from url: URL) -> Date? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let metadata = try? decoder.decode(ExportMetadata.self, from: data) else { return nil }
        return metadata.exportDate
    }

    /// Valida la estructura y las referencias del JSON sin crear ni normalizar modelos.
    nonisolated static func validateExportFile(from url: URL) throws {
        let exportData = try decodeExportData(from: url)
        try validateUniqueIdentifiers(in: exportData)
        try validateReferences(in: exportData)
    }

    /// Variante asíncrona para validar un archivo sin bloquear el actor principal.
    nonisolated static func validateExportFileAsync(from url: URL) async throws {
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let exportData = try decodeExportData(from: url)
            try validateUniqueIdentifiers(in: exportData)
            try validateReferences(in: exportData)
        }
        try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
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
                formattedCount(investmentSnapshots, singular: "registro de inversión", plural: "registros de inversión"),
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

    private typealias LocalData = DataSnapshot

    /// Importa bancos, cuentas, categorías y movimientos desde un archivo JSON.
    /// Vincula automáticamente las relaciones por UUID.
    @MainActor static func importData(from url: URL) throws -> ImportResult {
        let exportData = try decodeExportData(from: url)
        return try makeImportResult(from: exportData)
    }

    /// Decodifica y valida fuera del actor principal; la creación de modelos y sus
    /// relaciones se mantiene en `MainActor` para conservar la seguridad de SwiftData.
    @MainActor
    static func importDataAsync(from url: URL) async throws -> ImportResult {
        let task = Task.detached(priority: .utility) { () throws -> ExportData in
            try Task.checkCancellation()
            let exportData = try decodeExportData(from: url)
            try validateUniqueIdentifiers(in: exportData)
            try validateReferences(in: exportData)
            return exportData
        }
        let exportData = try await withTaskCancellationHandler(operation: {
            try await task.value
        }, onCancel: {
            task.cancel()
        })
        try Task.checkCancellation()
        return try makeImportResult(from: exportData, skipValidation: true)
    }

    @MainActor
    private static func makeImportResult(
        from exportData: ExportData,
        skipValidation: Bool = false
    ) throws -> ImportResult {
        if !skipValidation {
            try validateUniqueIdentifiers(in: exportData)
            try validateReferences(in: exportData)
        }

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

    private nonisolated static func decodeExportData(from url: URL) throws -> ExportData {
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

    @MainActor
    private static func fetchLocalData(in modelContext: ModelContext) throws -> LocalData {
        try fetchSnapshot(in: modelContext)
    }

    private nonisolated static func validateUniqueIdentifiers(in exportData: ExportData) throws {
        try validateUniqueIdentifiers(exportData.banks.map(\.id), entity: "bancos")
        try validateUniqueIdentifiers(exportData.accounts.map(\.id), entity: "cuentas")
        try validateUniqueIdentifiers(exportData.categories.map(\.id), entity: "categorías")
        try validateUniqueIdentifiers(exportData.movements.map(\.id), entity: "movimientos")
        try validateUniqueIdentifiers(exportData.investmentSnapshots.map(\.id), entity: "registros de inversión")
        try validateUniqueIdentifiers(exportData.recurringMovements.map(\.id), entity: "recurrencias")
        try validateUniqueIdentifiers(exportData.budgets.map(\.id), entity: "presupuestos")
        try validateUniqueIdentifiers(
            exportData.budgets.flatMap(\.items).map(\.id),
            entity: "BudgetItems"
        )
    }

    private nonisolated static func validateUniqueIdentifiers(_ identifiers: [UUID], entity: String) throws {
        guard Set(identifiers).count == identifiers.count else {
            throw ImportError.duplicateIdentifiers(entity)
        }
    }

    private nonisolated static func validateReferences(in exportData: ExportData) throws {
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
                throw ImportError.missingReference(entity: "registro de inversión \(snapshot.id.uuidString)", identifier: accountID, target: "cuenta")
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
