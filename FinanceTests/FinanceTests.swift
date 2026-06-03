//
//  FinanceTests.swift
//  FinanceTests
//
//  Created by Ismael Pérez on 11/02/2026.
//

import Testing
import Foundation
@testable import Finance

struct FinanceTests {

    @Test func activeAccountIsVisibleAfterCreation() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))

        #expect(account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 2)))
    }

    @Test func accountIsNotVisibleBeforeCreation() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 2))

        #expect(!account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 1)))
    }

    @Test func archivedAccountRemainsVisibleBeforeArchiveDate() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))
        account.archive(at: date(year: 2026, month: 5, day: 20))

        #expect(account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 10)))
    }

    @Test func archivedAccountIsNotVisibleAfterArchiveDate() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))
        account.archive(at: date(year: 2026, month: 5, day: 20))

        #expect(!account.isVisibleInPatrimony(at: date(year: 2026, month: 6, day: 1)))
    }

    @Test func archivedAccountWithoutArchiveDateFallsBackToUpdatedAt() async throws {
        let account = makeAccount(createdAt: date(year: 2026, month: 5, day: 1))
        account.isArchived = true
        account.archivedAt = nil
        account.updatedAt = date(year: 2026, month: 5, day: 20)

        #expect(account.isVisibleInPatrimony(at: date(year: 2026, month: 5, day: 10)))
        #expect(!account.isVisibleInPatrimony(at: date(year: 2026, month: 6, day: 1)))
    }

    private func makeAccount(createdAt: Date) -> BankAccount {
        let account = BankAccount(
            name: "Test account",
            accountType: .checking,
            balance: 0
        )
        account.createdAt = createdAt
        account.updatedAt = createdAt
        return account
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))!
    }

}
