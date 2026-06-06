import Testing
@testable import LaunchPad

@Suite("ErrorRecovery error handling strategies")
struct ErrorRecoveryTests {

    // MARK: - SQLite database corruption

    @Test("Database corruption -> returns deleteAndRescan strategy")
    func corruptedDB_deleteAndRescan() {
        let result = ErrorRecovery.handleSQLiteCorruption(dbPath: "/tmp/test.db")
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

    @Test("ErrorStrategy contains all 6 strategies")
    func errorStrategy_allCases() {
        #expect(ErrorRecovery.ErrorStrategy.allCases.count == 6)
    }
}
