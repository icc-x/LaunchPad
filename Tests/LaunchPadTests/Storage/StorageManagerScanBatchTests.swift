import Foundation
import SQLite3
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("StorageManager scan batch")
struct StorageManagerScanBatchTests {
    enum InitialFault: CaseIterable, Sendable {
        case begin, read, prepare, bind, step, changes, commit

        var point: SQLiteFaultPoint {
            switch self {
            case .begin: .begin
            case .read: .step(.fetchAllItems)
            case .prepare: .prepare(.insertItem)
            case .bind: .bind(.insertItem, index: 1)
            case .step: .step(.insertItem)
            case .changes: .changes(.insertItem)
            case .commit: .commit
            }
        }

        var code: Int32 {
            switch self {
            case .begin: SQLITE_BUSY
            case .bind: SQLITE_RANGE
            case .changes: 0
            default: SQLITE_IOERR
            }
        }
    }

    private func app(_ name: String, _ bundleID: String, _ path: String? = nil) -> ScannedApp {
        ScannedApp(name: name, bundleId: bundleID, path: path ?? "/\(name).app")
    }

    private func makeFaultableStorage(_ script: SQLiteFaultScript) throws -> StorageManager {
        try StorageManager(
            dbPath: ":memory:",
            schemaSetup: { Schema.setupSchema(db: $0) },
            faultInjector: script.result(for:)
        )
    }

    @Test("零扫描结果原子建立唯一空页")
    func emptyInitialScanCreatesOnePage() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        let result = try storage.synchronizeInstalledApps([], initialPageCapacity: 28)
        let snapshot = try storage.persistedLayoutSnapshot()
        #expect(result.isSuccessful)
        #expect(snapshot.pages.count == 1)
        #expect(snapshot.pageChildren[snapshot.pages[0].id] == [])
    }

    @Test("首次扫描按容量分页并稳定去重")
    func initialScanPaginatesAndDeduplicates() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        _ = try storage.synchronizeInstalledApps([
            app("Zulu", "com.test.z"), app("Alpha", "com.test.a"),
            app("Duplicate", "com.test.a"), app("Beta", "com.test.b"),
        ], initialPageCapacity: 2)
        let snapshot = try storage.persistedLayoutSnapshot()
        #expect(snapshot.pages.count == 2)
        #expect(snapshot.pages.flatMap { snapshot.pageChildren[$0.id] ?? [] }.compactMap(\.app?.title) == ["Alpha", "Beta", "Zulu"])
    }

    @Test("增量差分从 allItems 更新、删除并插入")
    func incrementalUsesAllItems() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        _ = try storage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b")], initialPageCapacity: 28)
        _ = try storage.synchronizeInstalledApps([app("A changed", "com.test.a", "/A2.app"), app("C", "com.test.c")], initialPageCapacity: 28)
        let apps = try storage.persistedLayoutSnapshot().allItems.compactMap(\.app)
        #expect(Set(apps.map(\.bundleId)) == ["com.test.a", "com.test.c"])
        #expect(apps.first(where: { $0.bundleId == "com.test.a" })?.title == "A changed")
    }

    @Test("初始写入失败继续后续操作但完整回滚")
    func initialFailureRollsBackEverything() throws {
        let script = SQLiteFaultScript()
        let storage = try StorageManager(dbPath: ":memory:", schemaSetup: { Schema.setupSchema(db: $0) }, faultInjector: script.result(for:))
        script.failNext(.step(.insertAppMetadata), code: SQLITE_CONSTRAINT)
        do {
            _ = try storage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b")], initialPageCapacity: 1)
            Issue.record("expected ScanBatchWriteFailure")
        } catch let failure as ScanBatchWriteFailure {
            #expect(failure.result.attemptedWriteCount == 4)
            #expect(failure.result.successfulWriteCount == 3)
            #expect(failure.result.failedWriteCount == 1)
        }
        #expect(try storage.persistedLayoutSnapshot().allItems.isEmpty)
    }

    @Test("增量 update 失败后仍尝试 insert/delete 且完整回滚")
    func incrementalFailureContinuesAndRollsBackEverything() throws {
        let script = SQLiteFaultScript()
        let storage = try StorageManager(dbPath: ":memory:", schemaSetup: { Schema.setupSchema(db: $0) }, faultInjector: script.result(for:))
        _ = try storage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b")], initialPageCapacity: 28)
        let before = try storage.persistedLayoutSnapshot()
        script.failNext(.step(.updateAppMetadata), code: SQLITE_IOERR)

        do {
            _ = try storage.synchronizeInstalledApps([app("A changed", "com.test.a", "/A2.app"), app("C", "com.test.c")], initialPageCapacity: 28)
            Issue.record("expected ScanBatchWriteFailure")
        } catch let failure as ScanBatchWriteFailure {
            #expect(failure.result.successfulWriteCount == 3)
            #expect(failure.result.failedWriteCount == 1)
        }
        #expect(try storage.persistedLayoutSnapshot() == before)
    }

    @Test("真实 RAISE(ROLLBACK) 后立即停止且不产生 autocommit 残留")
    func automaticSQLiteRollbackStopsFurtherScanWrites() throws {
        let storage = try StorageManager(
            dbPath: ":memory:",
            schemaSetup: { database in
                Schema.setupSchema(db: database)
                let sql = """
                    CREATE TRIGGER abort_test_b BEFORE INSERT ON apps
                    WHEN NEW.bundle_id = 'com.test.b'
                    BEGIN SELECT RAISE(ROLLBACK, 'forced automatic rollback'); END
                    """
                #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
            }
        )
        let before = try storage.persistedLayoutSnapshot()
        let scanned = [app("A", "com.test.a"), app("B", "com.test.b"), app("C", "com.test.c")]
        do {
            _ = try storage.synchronizeInstalledApps(scanned, initialPageCapacity: 3)
            Issue.record("expected ScanBatchWriteFailure")
        } catch let failure as ScanBatchWriteFailure {
            #expect(failure.result.attemptedWriteCount == 3)
            #expect(failure.result.successfulWriteCount == 2)
            #expect(failure.result.failedWriteCount == 1)
        }
        #expect(try storage.persistedLayoutSnapshot() == before)
        _ = try storage.synchronizeInstalledApps([scanned[0], scanned[2]], initialPageCapacity: 3)
        #expect(Set(try storage.persistedLayoutSnapshot().allItems.compactMap(\.app?.bundleId)) == ["com.test.a", "com.test.c"])
    }

    @Test("无效初始容量分类失败并不写入")
    func invalidCapacityDoesNotWrite() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        #expect(throws: ScanBatchWriteFailure.self) {
            _ = try storage.synchronizeInstalledApps([], initialPageCapacity: 0)
        }
        #expect(try storage.persistedLayoutSnapshot().allItems.isEmpty)
    }

    @Test("初始扫描的 BEGIN/read/prepare/bind/step/changes/COMMIT 故障完整回滚", arguments: InitialFault.allCases)
    func initialScanFaultsPreserveCompleteSnapshot(_ fault: InitialFault) throws {
        let script = SQLiteFaultScript()
        let storage = try makeFaultableStorage(script)
        let before = try storage.persistedLayoutSnapshot()
        script.failNext(fault.point, code: fault.code)

        #expect(throws: ScanBatchWriteFailure.self) {
            _ = try storage.synchronizeInstalledApps([app("A", "com.test.a")], initialPageCapacity: 1)
        }
        #expect(try storage.persistedLayoutSnapshot() == before)
    }

    @Test("扫描回滚失败保留 primary failure 并使连接不可用")
    func scanRollbackFailureInvalidatesStorage() throws {
        let script = SQLiteFaultScript()
        let storage = try makeFaultableStorage(script)
        script.failNext(.step(.insertItem), code: SQLITE_IOERR)
        script.failNext(.rollback, code: SQLITE_FULL)

        do {
            _ = try storage.synchronizeInstalledApps([app("A", "com.test.a")], initialPageCapacity: 1)
            Issue.record("expected SQLiteRollbackFailure")
        } catch let error as SQLiteRollbackFailure {
            #expect(error.primaryError is ScanBatchWriteFailure)
            #expect(error.rollbackCode == SQLITE_FULL)
        }
        #expect(throws: StorageError.storageUnavailable) {
            _ = try storage.persistedLayoutSnapshot()
        }
    }

    @Test("文件数据库扫描失败关闭重开后不含部分行")
    func fileBackedFailedScanDoesNotPersistPartialRows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchPadScan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("launchpad.sqlite").path
        let script = SQLiteFaultScript()
        var before: PersistedLayoutSnapshot?
        do {
            let storage = try StorageManager(
                dbPath: path,
                schemaSetup: { Schema.setupSchema(db: $0) },
                faultInjector: script.result(for:)
            )
            before = try storage.persistedLayoutSnapshot()
            script.failNext(.step(.insertAppMetadata), code: SQLITE_IOERR)
            #expect(throws: ScanBatchWriteFailure.self) {
                _ = try storage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b")], initialPageCapacity: 2)
            }
        }
        let reopened = try StorageManager(dbPath: path)
        let expectedBefore = try #require(before)
        #expect(try reopened.persistedLayoutSnapshot() == expectedBefore)
    }

    @Test("初始 page 与 app 失败均继续独立写入后整体回滚")
    func initialPageAndAppFailuresContinueThenRollback() throws {
        let pageScript = SQLiteFaultScript()
        let pageStorage = try makeFaultableStorage(pageScript)
        let pageBefore = try pageStorage.persistedLayoutSnapshot()
        pageScript.fail(.step(.insertItem), onOccurrence: 3, code: SQLITE_IOERR)
        do {
            _ = try pageStorage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b"), app("C", "com.test.c")], initialPageCapacity: 1)
            Issue.record("expected page failure")
        } catch let failure as ScanBatchWriteFailure {
            #expect(failure.result.attemptedWriteCount == 5)
            #expect(failure.result.successfulWriteCount == 4)
        }
        #expect(try pageStorage.persistedLayoutSnapshot() == pageBefore)

        let appScript = SQLiteFaultScript()
        let appStorage = try makeFaultableStorage(appScript)
        let appBefore = try appStorage.persistedLayoutSnapshot()
        appScript.fail(.step(.insertAppMetadata), onOccurrence: 2, code: SQLITE_IOERR)
        #expect(throws: ScanBatchWriteFailure.self) {
            _ = try appStorage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b"), app("C", "com.test.c")], initialPageCapacity: 1)
        }
        #expect(try appStorage.persistedLayoutSnapshot() == appBefore)
    }

    @Test("增量包含 new/changed/unchanged/removed，重复 scanned first-wins 且 no-op 不写入")
    func incrementalDiffCoversAllAppStatesAndNoOp() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        _ = try storage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b"), app("Stable", "com.test.stable")], initialPageCapacity: 28)
        _ = try storage.synchronizeInstalledApps([app("A changed", "com.test.a", "/A2.app"), app("C", "com.test.c"), app("C duplicate", "com.test.c", "/ignored.app"), app("Stable", "com.test.stable")], initialPageCapacity: 28)
        let snapshot = try storage.persistedLayoutSnapshot()
        let apps = snapshot.allItems.compactMap(\.app)
        #expect(Set(apps.map(\.bundleId)) == ["com.test.a", "com.test.c", "com.test.stable"])
        #expect(apps.first(where: { $0.bundleId == "com.test.c" })?.title == "C")
        #expect(apps.first(where: { $0.bundleId == "com.test.a" })?.path == "/A2.app")
        let noOp = try storage.synchronizeInstalledApps([app("A changed", "com.test.a", "/A2.app"), app("C", "com.test.c"), app("Stable", "com.test.stable")], initialPageCapacity: 28)
        #expect(noOp.attemptedWriteCount == 0)
        #expect(try storage.persistedLayoutSnapshot() == snapshot)
    }

    @Test("非空 root 无 page、malformed app 与重复 existing bundle 约束分支")
    func malformedAndInvalidExistingTopologyIsHandledWithoutPartialMutation() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        _ = try storage.insertItem(TestDataFactory.makePageItem(type: .app, app: TestDataFactory.makeAppInfo(bundleId: "com.test.root")))
        let before = try storage.persistedLayoutSnapshot()
        #expect(throws: ScanBatchWriteFailure.self) {
            _ = try storage.synchronizeInstalledApps([app("A", "com.test.a")], initialPageCapacity: 28)
        }
        #expect(try storage.persistedLayoutSnapshot() == before)

        let valid = try StorageManager(dbPath: ":memory:")
        let page = try valid.insertItem(TestDataFactory.makePageItem(type: .page))
        _ = try valid.insertItem(TestDataFactory.makePageItem(type: .app, parentId: page, app: nil))
        _ = try valid.synchronizeInstalledApps([app("A", "com.test.a")], initialPageCapacity: 28)
        #expect(try valid.persistedLayoutSnapshot().allItems.contains { $0.app?.bundleId == "com.test.a" })
        #expect(throws: (any Error).self) {
            _ = try valid.insertItem(TestDataFactory.makePageItem(type: .app, parentId: page, app: TestDataFactory.makeAppInfo(bundleId: "com.test.a")))
        }
    }

    @Test("增量写入首错优先于 normalization 的后续读取错误")
    func incrementalFirstWriteFailureWinsOverNormalizationReadFailure() throws {
        let script = SQLiteFaultScript()
        let storage = try makeFaultableStorage(script)
        _ = try storage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b")], initialPageCapacity: 28)
        let before = try storage.persistedLayoutSnapshot()
        script.failNext(.step(.updateAppMetadata), code: SQLITE_IOERR)
        script.fail(.prepare(.fetchAllItems), onOccurrence: 2, code: SQLITE_IOERR)

        do {
            _ = try storage.synchronizeInstalledApps([app("A changed", "com.test.a", "/A2.app"), app("B", "com.test.b")], initialPageCapacity: 28)
            Issue.record("expected ScanBatchWriteFailure")
        } catch let failure as ScanBatchWriteFailure {
            #expect(failure.primaryError as? StorageError == .updateFailed)
        }
        #expect(try storage.persistedLayoutSnapshot() == before)
    }

    @Test("同页 metadata 失败后继续后项并完整回滚")
    func samePageMetadataFailureContinuesAndRollsBack() throws {
        let script = SQLiteFaultScript()
        let storage = try makeFaultableStorage(script)
        let before = try storage.persistedLayoutSnapshot()
        script.fail(.step(.insertAppMetadata), onOccurrence: 2, code: SQLITE_IOERR)

        do {
            _ = try storage.synchronizeInstalledApps([app("A", "com.test.a"), app("B", "com.test.b"), app("C", "com.test.c")], initialPageCapacity: 3)
            Issue.record("expected ScanBatchWriteFailure")
        } catch let failure as ScanBatchWriteFailure {
            #expect(failure.result.attemptedWriteCount == 4)
            #expect(failure.result.successfulWriteCount == 3)
            #expect(failure.result.failedWriteCount == 1)
        }
        #expect(try storage.persistedLayoutSnapshot() == before)
    }

    @Test("增量删除多页后规范为稠密单页并保留唯一空页")
    func incrementalDeletionNormalizesPagesAndPreservesOnlyEmptyPage() throws {
        let storage = try StorageManager(dbPath: ":memory:")
        let page1 = try storage.insertItem(TestDataFactory.makePageItem(type: .page, ordering: 0))
        let page2 = try storage.insertItem(TestDataFactory.makePageItem(type: .page, ordering: 1))
        let page3 = try storage.insertItem(TestDataFactory.makePageItem(type: .page, ordering: 2))
        func insert(_ scanned: ScannedApp, parentID: Int64, ordering: Int) throws {
            _ = try storage.insertItem(TestDataFactory.makePageItem(
                type: .app,
                ordering: ordering,
                parentId: parentID,
                app: TestDataFactory.makeAppInfo(
                    title: scanned.name,
                    bundleId: scanned.bundleId,
                    path: scanned.path
                )
            ))
        }
        try insert(app("A", "com.test.a"), parentID: page1, ordering: 0)
        try insert(app("B", "com.test.b"), parentID: page2, ordering: 0)
        try insert(app("C", "com.test.c"), parentID: page2, ordering: 1)
        try insert(app("D", "com.test.d"), parentID: page3, ordering: 0)

        _ = try storage.synchronizeInstalledApps([app("C", "com.test.c")], initialPageCapacity: 1)
        var snapshot = try storage.persistedLayoutSnapshot()
        #expect(snapshot.pages.count == 1)
        #expect(snapshot.pages.map(\.ordering) == [0])
        #expect(snapshot.pageChildren[snapshot.pages[0].id]?.map(\.app?.bundleId) == ["com.test.c"])
        #expect(snapshot.pageChildren[snapshot.pages[0].id]?.map(\.ordering) == [0])

        _ = try storage.synchronizeInstalledApps([], initialPageCapacity: 1)
        snapshot = try storage.persistedLayoutSnapshot()
        #expect(snapshot.pages.count == 1)
        #expect(snapshot.pages[0].ordering == 0)
        #expect(snapshot.pageChildren[snapshot.pages[0].id] == [])
    }
}
