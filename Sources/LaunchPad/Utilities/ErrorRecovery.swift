import Foundation
import SQLite3

/// Error recovery strategy enum
/// Corresponds to design document section 15, 6 error scenarios
public enum ErrorRecovery {

    public enum ErrorStrategy: CaseIterable {
        case healthy             // Database integrity check passed
        case deleteAndRescan     // SQLite database corruption
        case skipWithWarning     // Scan directory no permission
        case fallbackToMenuBar   // CGEventTap permission denied
        case useDefaultIcon      // Icon extraction failure
        case markAndClean        // Application path invalidation
        case walModeSerialQueue  // Database write conflict
    }

    /// Handle SQLite database corruption
    /// Attempts PRAGMA integrity_check first; returns .healthy if intact
    public static func handleSQLiteCorruption(dbPath: String) -> ErrorStrategy {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dbPath, isDirectory: &isDirectory) else {
            return .deleteAndRescan
        }
        // 目录不是数据库：deleteAndRescan 会让 remover 删掉整个目录，改为不删除。
        if isDirectory.boolValue {
            NSLog("[LaunchPad] Database path is a directory: \(dbPath), will not delete")
            return .healthy
        }

        var db: OpaquePointer?
        let openCode = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
        guard openCode == SQLITE_OK, let database = db else {
            // SQLite 即使失败也可能返回非 nil 句柄，必须关闭，避免泄漏。
            if let db {
                sqlite3_close(db)
            }
            // 常规文件已存在却打不开：更可能是锁冲突/权限抖动，而不是损坏。
            // 直接 deleteAndRescan 会误删用户布局，改为不删除并让启动失败可见。
            NSLog("[LaunchPad] Cannot open existing database: \(dbPath), will not delete")
            return .healthy
        }

        var stmt: OpaquePointer?
        defer {
            sqlite3_finalize(stmt)
            sqlite3_close(database)
        }

        guard sqlite3_prepare_v2(database, "PRAGMA integrity_check(1)", -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            NSLog("[LaunchPad] Cannot prepare integrity_check: \(dbPath)")
            return .deleteAndRescan
        }

        if sqlite3_step(stmt) == SQLITE_ROW,
           let result = sqlite3_column_text(stmt, 0),
           String(cString: result) == "ok" {
            NSLog("[LaunchPad] Database integrity check passed")
            return .healthy
        }

        NSLog("[LaunchPad] SQLite database corrupted: \(dbPath), will delete and rescan")
        return .deleteAndRescan
    }

    /// Handle directory permission denied
    public static func handlePermissionDenied(directory: String) -> ErrorStrategy {
        NSLog("[LaunchPad] Permission denied: \(directory), skipping")
        return .skipWithWarning
    }

    /// Handle CGEventTap permission denied
    public static func handleEventTapDenied() -> ErrorStrategy {
        NSLog("[LaunchPad] CGEventTap denied, falling back to menu bar activation")
        return .fallbackToMenuBar
    }

    /// Handle icon extraction failure
    public static func handleIconExtractionFailure(bundleId: String) -> ErrorStrategy {
        NSLog("[LaunchPad] Icon extraction failed for: \(bundleId), using default icon")
        return .useDefaultIcon
    }

    /// Handle application path invalidation
    public static func handlePathInvalidation(path: String) -> ErrorStrategy {
        NSLog("[LaunchPad] Path invalidated: \(path), marking for cleanup")
        return .markAndClean
    }

    /// Handle database write conflict
    public static func handleWriteConflict() -> ErrorStrategy {
        return .walModeSerialQueue
    }
}
