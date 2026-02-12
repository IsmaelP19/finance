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
    var createdAt: Date
    var updatedAt: Date

    /// Relación con la entidad Bank.
    var bank: Bank?

    /// Tipo de cuenta (wrapper tipado sobre accountTypeRaw).
    var accountType: AccountType {
        get { AccountType(rawValue: accountTypeRaw) ?? .checking }
        set { accountTypeRaw = newValue.rawValue }
    }

    /// Nombre del banco para mostrar (desde la relación Bank, o "Sin banco" como fallback).
    var bankDisplayName: String {
        bank?.name ?? "Sin banco"
    }

    init(
        name: String,
        bank: Bank? = nil,
        accountType: AccountType,
        balance: Decimal = 0,
        currency: String = "EUR",
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.bank = bank
        self.accountTypeRaw = accountType.rawValue
        self.balance = balance
        self.currency = currency
        self.notes = notes
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
    let createdAt: Date
    let updatedAt: Date

    init(from account: BankAccount) {
        self.id = account.id
        self.name = account.name
        self.bankId = account.bank?.id
        self.accountType = account.accountTypeRaw
        self.balance = account.balance
        self.currency = account.currency
        self.notes = account.notes
        self.createdAt = account.createdAt
        self.updatedAt = account.updatedAt
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
            notes: notes
        )
        account.id = id
        account.createdAt = createdAt
        account.updatedAt = updatedAt
        return account
    }
}
