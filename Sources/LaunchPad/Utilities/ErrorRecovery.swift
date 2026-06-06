import Foundation

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
    /// Pure function: returns strategy, caller executes side effects like deletion
    public static func handleSQLiteCorruption(dbPath: String) -> ErrorStrategy {
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
