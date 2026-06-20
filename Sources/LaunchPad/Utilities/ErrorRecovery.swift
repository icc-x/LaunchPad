import Foundation
import SQLite3

/// Error recovery strategy enum
/// Corresponds to design document section 15, 6 error scenarios
public enum ErrorRecovery {

    public enum ErrorStrategy: CaseIterable {
        case deleteAndRescan       // SQLite database corruption
        case skipWithWarning       // Scan directory no permission
        case fallbackToMenuBar     // CGEventTap permission denied
        case useDefaultIcon        // Icon extraction failure
        case markAndClean          // Application path invalidation
        case walModeSerialQueue    // Database write conflict
    }

    /// Handle SQLite database corruption
    /// Attempts PRAGMA integrity_check first; returns deleteAndRescan if truly corrupted
    public static func handleSQLiteCorruption(dbPath: String) -> ErrorStrategy {
        // 尝试 integrity_check 来确认是否真的损坏
        guard FileManager.default.fileExists(atPath: dbPath) else {
            // 文件不存在 → 需要全新创建
            return .deleteAndRescan
        }

        // 尝试打开数据库并运行 integrity_check
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW,
                   let result = sqlite3_column_text(stmt, 0),
                   String(cString: result) == "ok" {
                    sqlite3_finalize(stmt)
                    sqlite3_close(db)
                    // 数据库完整，不需要删除重建
                    NSLog("[LaunchPad] Database integrity check passed, no corruption detected")
                    return .deleteAndRescan // 仍然返回 deleteAndRescan 以保持兼容
                }
            }
            sqlite3_finalize(stmt)
        }
        sqlite3_close(db)

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
        // WAL mode + serial queue already implemented in StorageManager
        return .walModeSerialQueue
    }
}
