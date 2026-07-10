import Testing
import Foundation
import SQLite3
@testable import LaunchPad

@Suite("ErrorRecovery error handling strategies")
struct ErrorRecoveryTests {

    // MARK: - SQLite database corruption

    @Test("Database corruption (no file) -> returns deleteAndRescan strategy")
    func corruptedDB_deleteAndRescan() {
        let result = ErrorRecovery.handleSQLiteCorruption(dbPath: "/tmp/nonexistent_test.db")
        #expect(result == .deleteAndRescan)
    }

    // MARK: - Directory permission

    @Test("Directory no permission -> returns skipWithWarning strategy")
    func permissionDenied_skipWithWarning() {
        let result = ErrorRecovery.handlePermissionDenied(directory: "/System/Applications")
        #expect(result == .skipWithWarning)
    }

    // MARK: - CGEventTap permission

    @Test("CGEventTap permission denied -> returns fallbackToMenuBar strategy")
    func eventTapDenied_fallbackToMenuBar() {
        let result = ErrorRecovery.handleEventTapDenied()
        #expect(result == .fallbackToMenuBar)
    }

    // MARK: - Icon extraction failure

    @Test("Icon extraction failure -> returns useDefaultIcon strategy")
    func iconExtractionFailed_useDefaultIcon() {
        let result = ErrorRecovery.handleIconExtractionFailure(bundleId: "com.test.app")
        #expect(result == .useDefaultIcon)
    }

    // MARK: - Path invalidation

    @Test("App path invalidation -> returns markAndClean strategy")
    func pathInvalid_markAndClean() {
        let result = ErrorRecovery.handlePathInvalidation(path: "/Applications/Deleted.app")
        #expect(result == .markAndClean)
    }

    // MARK: - Strategy enum completeness

    @Test("Database write conflict -> returns walModeSerialQueue strategy")
    func writeConflict_walModeSerialQueue() {
        let result = ErrorRecovery.handleWriteConflict()
        #expect(result == .walModeSerialQueue)
    }

    @Test("ErrorStrategy contains all 7 strategies")
    func errorStrategy_allCases() {
        #expect(ErrorRecovery.ErrorStrategy.allCases.count == 7)
    }

    // MARK: - handleSQLiteCorruption 分支覆盖

    @Test("健康数据库 -> 返回 healthy")
    func handleSQLiteCorruption_healthyDB_returnsHealthy() throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("healthy_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // 创建一个有效的 SQLite 数据库
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, "CREATE TABLE t (id INTEGER)", nil, nil, nil)
        sqlite3_close(db)

        let result = ErrorRecovery.handleSQLiteCorruption(dbPath: path)
        #expect(result == .healthy)
    }

    @Test("非 SQLite 文件 -> 返回 deleteAndRescan")
    func handleSQLiteCorruption_nonDBFile_returnsDeleteAndRescan() throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("notadb_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "not a database".write(toFile: path, atomically: true, encoding: .utf8)

        let result = ErrorRecovery.handleSQLiteCorruption(dbPath: path)
        #expect(result == .deleteAndRescan)
    }

    @Test("损坏的数据库文件 -> 返回 deleteAndRescan")
    func handleSQLiteCorruption_corruptedDB_returnsDeleteAndRescan() throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("corrupt_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // 先创建有效数据库
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, "CREATE TABLE t (id INTEGER)", nil, nil, nil)
        sqlite3_close(db)

        // 写入随机字节破坏数据库
        try Data(repeating: 0xFF, count: 512).write(to: URL(fileURLWithPath: path))

        let result = ErrorRecovery.handleSQLiteCorruption(dbPath: path)
        #expect(result == .deleteAndRescan)
    }

    @Test("目录路径作为 dbPath -> sqlite3_open 只读失败 -> deleteAndRescan")
    func handleSQLiteCorruption_directoryPath_openFails() {
        // sqlite3_open_v2 以只读模式打开目录会返回 SQLITE_CANTOPEN，触发 open 失败分支
        let dirPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("dir_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dirPath) }

        let result = ErrorRecovery.handleSQLiteCorruption(dbPath: dirPath)
        #expect(result == .deleteAndRescan)
    }

    @Test("integrity_check 返回非 ok -> deleteAndRescan")
    func handleSQLiteCorruption_integrityCheckNotOk_returnsDeleteAndRescan() throws {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("integbad_\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(atPath: path) }

        // 创建有效数据库并写入数据
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, "CREATE TABLE t (id INTEGER)", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO t VALUES (1)", nil, nil, nil)
        sqlite3_close(db)

        // 修改 SQLite header 中的 freelist trunk page number（偏移 36，4 字节 big-endian）为不存在的巨大值
        // 使 integrity_check 能 prepare 成功并返回非 "ok" 的错误描述（Freelist 不一致）
        var data = try Data(contentsOf: URL(fileURLWithPath: path))
        if data.count > 40 {
            data[36] = 0x7F
            data[37] = 0x00
            data[38] = 0x00
            data[39] = 0x00
            try data.write(to: URL(fileURLWithPath: path))
        }

        let result = ErrorRecovery.handleSQLiteCorruption(dbPath: path)
        #expect(result == .deleteAndRescan)
    }
}
