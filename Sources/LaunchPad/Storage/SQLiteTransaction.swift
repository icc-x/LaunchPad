import Foundation
import SQLite3

enum SQLiteStatementKind: Hashable, Sendable {
    case fetchItems
    case fetchAllItems
    case insertItem
    case insertAppMetadata
    case insertGroupMetadata
    case updateItem
    case updateAppMetadata
    case updateGroupMetadata
    case deleteItem
    case reorderItem
    case saveImage
    case fetchImage
    case updateLayoutItem
    case updatePageOrdering
    case insertPage
    case deleteLayoutItem
}

enum SQLiteFaultPoint: Hashable, Sendable {
    case begin
    case prepare(SQLiteStatementKind)
    case bind(SQLiteStatementKind, index: Int32)
    case step(SQLiteStatementKind)
    case changes(SQLiteStatementKind)
    case commit
    case rollback
}

struct SQLiteDriver: @unchecked Sendable {
    typealias FaultInjector = @Sendable (SQLiteFaultPoint) -> Int32?

    let faultInjector: FaultInjector?

    func execute(
        database: OpaquePointer,
        sql: String,
        point: SQLiteFaultPoint
    ) -> Int32 {
        if let code = faultInjector?(point) { return code }
        return sqlite3_exec(database, sql, nil, nil, nil)
    }

    func prepare(
        database: OpaquePointer,
        sql: String,
        statement: inout OpaquePointer?,
        kind: SQLiteStatementKind
    ) -> Int32 {
        if let code = faultInjector?(.prepare(kind)) { return code }
        return sqlite3_prepare_v2(database, sql, -1, &statement, nil)
    }

    func bind(
        _ operation: @autoclosure () -> Int32,
        kind: SQLiteStatementKind,
        index: Int32
    ) -> Int32 {
        if let code = faultInjector?(.bind(kind, index: index)) { return code }
        return operation()
    }

    func step(
        _ statement: OpaquePointer?,
        kind: SQLiteStatementKind
    ) -> Int32 {
        if let code = faultInjector?(.step(kind)) { return code }
        return sqlite3_step(statement)
    }

    func changes(
        database: OpaquePointer,
        kind: SQLiteStatementKind
    ) -> Int32 {
        if let count = faultInjector?(.changes(kind)) { return count }
        return sqlite3_changes(database)
    }
}

enum SQLiteTransactionMode: Sendable, Equatable {
    case deferred
    case immediate
}

struct SQLiteRollbackFailure: Error {
    let primaryError: Error
    let rollbackCode: Int32
}

struct SQLiteTransaction {
    let database: OpaquePointer
    let driver: SQLiteDriver

    func run<T>(
        mode: SQLiteTransactionMode,
        body: () throws -> T
    ) throws -> T {
        let begin = mode == .immediate ? "BEGIN IMMEDIATE" : "BEGIN"
        guard driver.execute(
            database: database,
            sql: begin,
            point: .begin
        ) == SQLITE_OK else {
            throw StorageError.beginFailed
        }
        do {
            let result = try body()
            guard driver.execute(
                database: database,
                sql: "COMMIT",
                point: .commit
            ) == SQLITE_OK else {
                throw StorageError.commitFailed
            }
            return result
        } catch {
            let primary = error
            // SQLite may already have ended the transaction after a severe
            // error or RAISE(ROLLBACK). Do not issue a synthetic rollback.
            guard sqlite3_get_autocommit(database) == 0 else {
                throw primary
            }
            let rollbackCode = driver.execute(
                database: database,
                sql: "ROLLBACK",
                point: .rollback
            )
            guard rollbackCode == SQLITE_OK else {
                throw SQLiteRollbackFailure(
                    primaryError: primary,
                    rollbackCode: rollbackCode
                )
            }
            throw primary
        }
    }
}
