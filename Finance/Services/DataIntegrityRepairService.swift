//
//  DataIntegrityRepairService.swift
//  Finance
//
//  Created by OpenCode on 13/05/2026.
//

import Foundation
import SQLite3

enum DataIntegrityRepairService {
    nonisolated static func repairBeforeOpeningModelContainer() {
        guard let storeURL else { return }
        nullifyDanglingMovementAccountReferences(at: storeURL)
        backfillMissingArchivedAccountDates(at: storeURL)
    }

    nonisolated private static var storeURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("default.store")
    }

    nonisolated private static func nullifyDanglingMovementAccountReferences(at storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return
        }
        defer { sqlite3_close(database) }

        guard let database,
              let movementTable = findTable(namedLike: "MOVEMENT", in: database),
              let accountTable = findTable(namedLike: "BANKACCOUNT", in: database)
        else { return }

        let movementColumns = Set(tableColumns(for: movementTable, in: database).map { $0.uppercased() })
        let accountColumns = Set(tableColumns(for: accountTable, in: database).map { $0.uppercased() })
        guard accountColumns.contains("Z_PK") else { return }

        for column in ["ZACCOUNT", "ZDESTINATIONACCOUNT"] where movementColumns.contains(column) {
            nullifyDanglingReference(
                column: column,
                movementTable: movementTable,
                accountTable: accountTable,
                in: database
            )
        }
    }

    nonisolated private static func backfillMissingArchivedAccountDates(at storeURL: URL) {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return
        }
        defer { sqlite3_close(database) }

        guard let database,
              let accountTable = findTable(namedLike: "BANKACCOUNT", in: database)
        else { return }

        let accountColumns = Set(tableColumns(for: accountTable, in: database).map { $0.uppercased() })
        guard accountColumns.contains("ZISARCHIVED"),
              accountColumns.contains("ZARCHIVEDAT")
        else { return }

        let fallbackColumn: String
        if accountColumns.contains("ZUPDATEDAT") {
            fallbackColumn = "ZUPDATEDAT"
        } else if accountColumns.contains("ZCREATEDAT") {
            fallbackColumn = "ZCREATEDAT"
        } else {
            return
        }

        backfillMissingArchivedAccountDates(
            accountTable: accountTable,
            fallbackColumn: fallbackColumn,
            in: database
        )
    }

    nonisolated private static func backfillMissingArchivedAccountDates(
        accountTable: String,
        fallbackColumn: String,
        in database: OpaquePointer
    ) {
        let sql = """
        UPDATE \(quotedIdentifier(accountTable))
        SET \(quotedIdentifier("ZARCHIVEDAT")) = \(quotedIdentifier(fallbackColumn))
        WHERE \(quotedIdentifier("ZISARCHIVED")) != 0
        AND \(quotedIdentifier("ZARCHIVEDAT")) IS NULL
        AND \(quotedIdentifier(fallbackColumn)) IS NOT NULL
        """

        _ = execute(sql, in: database)
    }

    nonisolated private static func nullifyDanglingReference(
        column: String,
        movementTable: String,
        accountTable: String,
        in database: OpaquePointer
    ) {
        let sql = """
        UPDATE \(quotedIdentifier(movementTable))
        SET \(quotedIdentifier(column)) = NULL
        WHERE \(quotedIdentifier(column)) IS NOT NULL
        AND NOT EXISTS (
            SELECT 1
            FROM \(quotedIdentifier(accountTable))
            WHERE \(quotedIdentifier(accountTable)).\(quotedIdentifier("Z_PK")) = \(quotedIdentifier(movementTable)).\(quotedIdentifier(column))
        )
        """

        _ = execute(sql, in: database)
    }

    nonisolated private static func findTable(namedLike name: String, in database: OpaquePointer) -> String? {
        let target = name.uppercased()
        let tables = queryStrings("SELECT name FROM sqlite_master WHERE type = 'table'", in: database)
        return tables.first { $0.uppercased() == "Z\(target)" }
            ?? tables.first { $0.uppercased().contains(target) }
    }

    nonisolated private static func tableColumns(for table: String, in database: OpaquePointer) -> [String] {
        queryStrings("PRAGMA table_info(\(quotedIdentifier(table)))", columnIndex: 1, in: database)
    }

    nonisolated private static func queryStrings(_ sql: String, columnIndex: Int32 = 0, in database: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, columnIndex) else { continue }
            values.append(String(cString: text))
        }
        return values
    }

    nonisolated private static func execute(_ sql: String, in database: OpaquePointer) -> Bool {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        sqlite3_free(errorMessage)
        return result == SQLITE_OK
    }

    nonisolated private static func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
