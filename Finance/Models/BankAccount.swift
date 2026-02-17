//
//  BankAccount.swift
//  Finance
//
//  Created by Ismael Pérez on 11/02/2026.
//

import Foundation
import SwiftData

/// Modelo principal que representa una cuenta bancaria.
/// Se almacena localmente mediante SwiftData (SQLite).
/// Nunca se envía a ningún servidor externo.
@Model
final class BankAccount {
    var id: UUID
    var name: String
    var accountTypeRaw: String
    var balance: Decimal
    var currency: String
    var notes: String
    var investedAmount: Decimal?
    var marketValue: Decimal?
    var marketValueUpdatedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    /// Relación con la entidad Bank.
    var bank: Bank?

    /// Relación inversa: movimientos asociados a esta cuenta.
    /// Si se elimina la cuenta, se eliminan también sus movimientos.
    @Relationship(deleteRule: .cascade, inverse: \Movement.account)
    var movements: [Movement]?

    /// Relación inversa: snapshots de inversión asociados a esta cuenta.
    @Relationship(deleteRule: .cascade, inverse: \InvestmentSnapshot.account)
    var investmentSnapshots: [InvestmentSnapshot]?

    /// Tipo de cuenta (wrapper tipado sobre accountTypeRaw).
    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .checking }
        set { accountTypeRaw = newValue.rawValue }
    }

    /// Nombre del banco para mostrar (desde la relación Bank, o "Sin banco" como fallback).
    var bankDisplayName: String {
        bank?.name ?? "Sin banco"
    }

    var isInvestmentAccount: Bool {
        accountType == .investment
    }

    var effectiveInvestedAmount: Decimal {
        investedAmount ?? balance
    }

    var effectiveMarketValue: Decimal {
        marketValue ?? balance
    }

    var investmentProfit: Decimal {
        effectiveMarketValue - effectiveInvestedAmount
    }

    var investmentReturnPercent: Decimal? {
        guard effectiveInvestedAmount > 0 else { return nil }
        return (investmentProfit / effectiveInvestedAmount) * 100
    }

    init(
        name: String,
        bank: Bank? = nil,
        accountType: AccountType,
        balance: Decimal = 0,
        currency: String = "EUR",
        notes: String = "",
        investedAmount: Decimal? = nil,
        marketValue: Decimal? = nil,
        marketValueUpdatedAt: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.bank = bank
        self.accountTypeRaw = accountType.rawValue
        self.balance = balance
        self.currency = currency
        self.notes = notes
        self.investedAmount = investedAmount
        self.marketValue = marketValue
        self.marketValueUpdatedAt = marketValueUpdatedAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO para Export/Import JSON

/// Representación Codable de BankAccount para exportar/importar datos.
/// SwiftData @Model no soporta Codable directamente, por lo que usamos un DTO.
struct BankAccountDTO: Codable {
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
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case bankId
        case accountType
        case balance
        case currency
        case notes
        case investedAmount
        case marketValue
        case marketValueUpdatedAt
        case createdAt
        case updatedAt
    }

    init(from account: BankAccount) {
        self.id = account.id
        self.name = account.name
        self.bankId = account.bank?.id
        self.accountType = account.accountTypeRaw
        self.balance = account.balance
        self.currency = account.currency
        self.notes = account.notes
        self.investedAmount = account.investedAmount
        self.marketValue = account.marketValue
        self.marketValueUpdatedAt = account.marketValueUpdatedAt
        self.createdAt = account.createdAt
        self.updatedAt = account.updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        bankId = try container.decodeIfPresent(UUID.self, forKey: .bankId)
        accountType = try container.decode(String.self, forKey: .accountType)
        balance = try container.decode(Decimal.self, forKey: .balance)
        currency = try container.decode(String.self, forKey: .currency)
        notes = try container.decode(String.self, forKey: .notes)
        investedAmount = try container.decodeIfPresent(Decimal.self, forKey: .investedAmount)
        marketValue = try container.decodeIfPresent(Decimal.self, forKey: .marketValue)
        marketValueUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .marketValueUpdatedAt)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Convierte el DTO en un modelo BankAccount de SwiftData.
    /// El banco se vincula después, ya que necesita el ModelContext para buscarlo.
    func toModel() -> BankAccount {
        let account = BankAccount(
            name: name,
            bank: nil,
            accountType: AccountType(rawValue: accountType) ?? .checking,
            balance: balance,
            currency: currency,
            notes: notes,
            investedAmount: investedAmount,
            marketValue: marketValue,
            marketValueUpdatedAt: marketValueUpdatedAt
        )
        account.id = id
        account.createdAt = createdAt
        account.updatedAt = updatedAt
        return account
    }
}
