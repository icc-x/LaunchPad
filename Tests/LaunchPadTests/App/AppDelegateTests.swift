import Testing
import Foundation
#if canImport(AppKit)
import AppKit
import ServiceManagement
@testable import LaunchPad
import LaunchPadProtocols

@MainActor
@Suite("AppDelegate 启动流程与分支覆盖")
struct AppDelegateTests {

    // MARK: - Test Doubles

    private final class MockStatusItem: StatusItemManaging {
        var button: NSStatusBarButton?
        var menu: NSMenu?

        init(button: NSStatusBarButton? = nil) {
            self.button = button
        }
    }

    @MainActor
    private final class CallRecorder {
        var count = 0
    }

    /// 可控的 DataStoring 实现：通过属性控制 fetchAllItems 的返回/抛错，其余为无操作
    private struct MockStoring: DataStoring, @unchecked Sendable {
        var itemsToReturn: [PageItem] = []
        var shouldThrow = false

        func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
            if shouldThrow { throw NSError(domain: "MockStoring", code: 1, userInfo: nil) }
            return itemsToReturn
        }
        func insertItem(_ item: PageItem) throws -> Int64 { 0 }
        func updateItem(_ item: PageItem) throws {}
        func deleteItem(id: Int64) throws {}
        func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {}
        func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {}
        func fetchImage(itemId: Int64) throws -> (Data, Data)? { nil }
    }

    private final class RecordingScanBatchWriter: ScanBatchWriting, @unchecked Sendable {
        var result = ScanSyncResult()
        var error: Error?
        var onSynchronize: (@Sendable () -> Void)?
        private(set) var receivedApps: [[ScannedApp]] = []
        private(set) var receivedCapacities: [Int] = []

        func synchronizeInstalledApps(
            _ apps: [ScannedApp],
            initialPageCapacity: Int
        ) throws -> ScanSyncResult {
            receivedApps.append(apps)
            receivedCapacities.append(initialPageCapacity)
            if let error { throw error }
            onSynchronize?()
            return result
        }
    }

    /// 测试用图标提供者：避免触碰真实 NSWorkspace
    private struct MockIconProvider: IconProviding {
        func icon(forPath path: String) -> NSImage { NSImage() }
        func modificationDate(forPath path: String) -> Date? { nil }
    }

    // MARK: - Helpers

    private func makeIsolatedHotkeyManager(
        accessibilityTrusted: Bool = false,
        tapResult: CFMachPort? = nil
    ) -> HotkeyManager {
        let manager = HotkeyManager()
        let localMonitorToken = NSObject()
        manager.accessibilityChecker = { accessibilityTrusted }
        manager.eventTapCreator = { _, _, _ in tapResult }
        manager.runLoopSourceCreator = {
            CFMachPortCreateRunLoopSource(kCFAllocatorDefault, $0, 0)
        }
        manager.runLoopSourceAdder = { _ in }
        manager.runLoopSourceRemover = { _ in }
        manager.eventTapEnabler = { _, _ in }
        manager.localMonitorInstaller = { _ in localMonitorToken }
        manager.localMonitorRemover = { _ in }
        return manager
    }

    /// 创建一个所有危险系统调用都被替换为安全实现的 AppDelegate
    private func makeDelegate() -> AppDelegate {
        let sut = AppDelegate()
        let databasePath = "/tmp/launchpad-appdelegate-\(UUID().uuidString).sqlite3"
        sut.databasePathProvider = { databasePath }
        sut.databaseRemover = { _ in }
        let hotkeyManager = makeIsolatedHotkeyManager()
        sut.activationPolicySetter = { _ in }
        sut.appTerminator = {}
        sut.runningInstanceChecker = { false }
        sut.existingInstanceActivator = {}
        sut.alertRunner = { _ in .alertFirstButtonReturn }
        sut.mainAsyncRunner = { $0() }
        sut.corruptionHandler = { _ in .deleteAndRescan }
        sut.loginItemStatusProvider = { .notRegistered }
        sut.loginItemUnregister = {}
        sut.loginItemRegister = {}
        sut.statusItemFactory = { MockStatusItem() }
        sut.statusItemRemover = { _ in }
        sut.fileWatcherFactory = {
            FileWatcher(
                debounceInterval: 2.0,
                backend: MockFileEventStream(),
                scheduler: MockScheduler()
            )
        }
        sut.hotkeyManagerFactory = { hotkeyManager }
        sut.workspaceURLOpener = { _ in }
        sut.applicationOpener = { _ in }
        sut.hotkeyToggleRunner = { action in
            MainActor.assumeIsolated { action() }
        }
        sut.storageFactory = { _ in try StorageManager(dbPath: ":memory:") }
        sut.scanBatchWriter = RecordingScanBatchWriter()
        return sut
    }

    private func makeFileSystemWithApps(count: Int) -> MockFileSystemService {
        let fileSystem = MockFileSystemService()
        let root = URL(fileURLWithPath: "/Applications")
        let urls = (0..<count).map { root.appendingPathComponent("App\($0).app") }
        fileSystem.directoryContentsMap[root] = urls
        for (index, url) in urls.enumerated() {
            fileSystem.bundleInfos[url] = [
                "CFBundleName": "App \(index)",
                "CFBundleIdentifier": "com.test.app\(index)",
            ]
        }
        return fileSystem
    }

    /// 构造一个真实但无视图依赖的 LaunchPadViewController
    private func makeViewController() throws -> LaunchPadViewController {
        let storage = try StorageManager(dbPath: ":memory:")
        let iconCache = IconCache(iconProvider: MockIconProvider(), imageStore: storage)
        let searchEngine = SearchEngine()
        let dragController = DragController()
        let folderController = FolderController(itemWriter: storage)
        return LaunchPadViewController(
            storage: storage,
            layoutMutator: storage,
            iconCache: iconCache,
            searchEngine: searchEngine,
            dragController: dragController,
            folderController: folderController,
            applicationOpener: { _ in }
        )
    }

    private func keyEvent(keyCode: UInt16, characters: String = "") -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func flagsChangedEvent() -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 58
        )!
    }

    private func visibleLifecycle() -> WindowLifecycle {
        let lifecycle = WindowLifecycle()
        lifecycle.handleToggle()
        lifecycle.openAnimationDidFinish()
        return lifecycle
    }

    private func prepareKeyboardMonitor(
        _ sut: AppDelegate,
        lifecycle: WindowLifecycle,
        viewController: LaunchPadViewController?
    ) -> HotkeyManager {
        let manager = makeIsolatedHotkeyManager()
        sut.hotkeyManager = manager
        sut.lifecycle = lifecycle
        sut.viewController = viewController
        sut.setupHotkey()
        return manager
    }

    private func pageItem() -> PageItem {
        PageItem(
            id: 1,
            uuid: UUID().uuidString,
            type: .page,
            ordering: 0,
            parentId: nil,
            app: nil,
            group: nil
        )
    }

    private func referencesSameObject(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject) === (rhs as AnyObject)
    }

    // MARK: - applicationDidFinishLaunching

    @Test("多实例：激活已有实例并退出，不初始化服务")
    func applicationDidFinishLaunching_terminatesExistingInstance() {
        let sut = makeDelegate()
        var activated = false
        var terminated = false
        sut.runningInstanceChecker = { true }
        sut.existingInstanceActivator = { activated = true }
        sut.appTerminator = { terminated = true }

        sut.applicationDidFinishLaunching(Notification(name: Notification.Name("test")))

        #expect(activated)
        #expect(terminated)
        #expect(sut.storage == nil)
    }

    @Test("正常启动：完整执行所有 setup 步骤")
    func applicationDidFinishLaunching_normalLaunch() throws {
        let sut = makeDelegate()

        sut.applicationDidFinishLaunching(Notification(name: Notification.Name("test")))

        #expect(sut.storage != nil)
        #expect(sut.iconCache != nil)
        #expect(sut.appScanner != nil)
        #expect(sut.searchEngine != nil)
        #expect(sut.hotkeyManager != nil)
        #expect(sut.lifecycle != nil)
        #expect(sut.viewController != nil)
        #expect(sut.windowController != nil)
        #expect(sut.statusItem != nil)
        #expect(sut.fileWatcher != nil)
    }

    @Test("启动失败：数据库不可用则记录致命错误并退出")
    func applicationDidFinishLaunching_fatalWhenStorageUnavailable() {
        let sut = makeDelegate()
        sut.storageFactory = { _ in throw NSError(domain: "db", code: 9) }
        sut.corruptionHandler = { _ in .healthy } // 非重建策略 → storage 保持 nil

        sut.applicationDidFinishLaunching(Notification(name: Notification.Name("test")))

        #expect(sut.storage == nil)
    }

    // MARK: - setupServices

    @Test("setupServices 成功创建存储与所有协作对象")
    func setupServices_success() throws {
        let sut = makeDelegate()
        sut.setupServices()

        #expect(sut.storage != nil)
        #expect(sut.layoutMutator != nil)
        #expect(referencesSameObject(sut.storage as Any, sut.layoutMutator as Any))
        #expect(sut.iconCache != nil)
        #expect(sut.appScanner != nil)
        #expect(sut.searchEngine != nil)
        #expect(sut.hotkeyManager != nil)
    }

    @Test("setupServices 只调用一次热键工厂并使用其返回实例")
    func setupServices_usesHotkeyFactoryExactlyOnce() {
        let sut = makeDelegate()
        let expectedManager = makeIsolatedHotkeyManager()
        var factoryCalls = 0
        sut.hotkeyManagerFactory = {
            factoryCalls += 1
            return expectedManager
        }

        sut.setupServices()

        #expect(factoryCalls == 1)
        #expect(sut.hotkeyManager === expectedManager)
    }

    @Test("setupServices：数据库损坏后删除并重建成功")
    func setupServices_corruptionRecovery() throws {
        let sut = makeDelegate()
        let safePath = sut.databasePathProvider()
        var attempts = 0
        var factoryPaths: [String] = []
        var handlerPaths: [String] = []
        var removedPaths: [String] = []
        sut.storageFactory = { path in
            attempts += 1
            factoryPaths.append(path)
            if attempts == 1 { throw NSError(domain: "db", code: 1) }
            return try StorageManager(dbPath: ":memory:")
        }
        sut.corruptionHandler = { path in
            handlerPaths.append(path)
            return .deleteAndRescan
        }
        sut.databaseRemover = { removedPaths.append($0) }

        sut.setupServices()

        #expect(attempts == 2)
        #expect(factoryPaths == [safePath, safePath])
        #expect(handlerPaths == [safePath])
        #expect(removedPaths == [safePath])
        #expect(sut.storage != nil)
        #expect(sut.layoutMutator != nil)
        #expect(referencesSameObject(sut.storage as Any, sut.layoutMutator as Any))
    }

    @Test("setupServices：损坏且非重建策略时放弃启动")
    func setupServices_nonDeleteStrategyDoesNotRemoveOrRetry() throws {
        let sut = makeDelegate()
        let safePath = sut.databasePathProvider()
        var factoryPaths: [String] = []
        var handlerPaths: [String] = []
        var removedPaths: [String] = []
        sut.storageFactory = { path in
            factoryPaths.append(path)
            throw NSError(domain: "db", code: 2)
        }
        sut.corruptionHandler = { path in
            handlerPaths.append(path)
            return .healthy
        }
        sut.databaseRemover = { removedPaths.append($0) }

        sut.setupServices()

        #expect(factoryPaths == [safePath])
        #expect(handlerPaths == [safePath])
        #expect(removedPaths.isEmpty)
        #expect(sut.storage == nil)
        #expect(sut.layoutMutator == nil)
    }

    @Test("setupServices：删除失败仍使用同一路径重试")
    func setupServices_removerThrowsStillRetries() throws {
        let sut = makeDelegate()
        let safePath = sut.databasePathProvider()
        var factoryPaths: [String] = []
        var handlerPaths: [String] = []
        var removedPaths: [String] = []
        sut.storageFactory = { path in
            factoryPaths.append(path)
            if factoryPaths.count == 1 { throw NSError(domain: "db", code: 3) }
            return try StorageManager(dbPath: ":memory:")
        }
        sut.corruptionHandler = { path in
            handlerPaths.append(path)
            return .deleteAndRescan
        }
        sut.databaseRemover = { path in
            removedPaths.append(path)
            throw NSError(domain: "db", code: 4)
        }

        sut.setupServices()

        #expect(factoryPaths == [safePath, safePath])
        #expect(handlerPaths == [safePath])
        #expect(removedPaths == [safePath])
        #expect(sut.storage != nil)
        #expect(sut.layoutMutator != nil)
        #expect(referencesSameObject(sut.storage as Any, sut.layoutMutator as Any))
    }

    @Test("setupServices：删除重建再次失败时两个协议引用均为空")
    func setupServices_recoveryFailureClearsBothReferences() {
        let sut = makeDelegate()
        sut.storageFactory = { _ in throw NSError(domain: "db", code: 5) }
        sut.corruptionHandler = { _ in .deleteAndRescan }

        sut.setupServices()

        #expect(sut.storage == nil)
        #expect(sut.layoutMutator == nil)
    }

    @Test("setupServices：重复初始化不会混用新旧协议引用")
    func setupServices_repeatedSetupReplacesBothReferencesTogether() throws {
        let sut = makeDelegate()
        var managers: [StorageManager] = []
        sut.storageFactory = { _ in
            let manager = try StorageManager(dbPath: ":memory:")
            managers.append(manager)
            return manager
        }

        sut.setupServices()
        let firstStorage = try #require(sut.storage)
        sut.setupServices()
        let secondStorage = try #require(sut.storage)

        #expect(managers.count == 2)
        #expect(!referencesSameObject(firstStorage, secondStorage))
        #expect(referencesSameObject(secondStorage, sut.layoutMutator as Any))

        sut.storageFactory = { _ in throw NSError(domain: "db", code: 6) }
        sut.corruptionHandler = { _ in .healthy }
        sut.setupServices()

        #expect(sut.storage == nil)
        #expect(sut.layoutMutator == nil)
    }

    // MARK: - setupControllers

    @Test("setupControllers 构建视图控制器与窗口控制器")
    func setupControllers_buildsAll() throws {
        let sut = makeDelegate()
        sut.setupServices()

        sut.setupControllers()

        #expect(sut.viewController != nil)
        #expect(sut.lifecycle != nil)
        #expect(sut.windowController != nil)
    }

    @Test("setupControllers 只允许 storage 与 layoutMutator 同时存在")
    func setupControllersRequiresBothTypedDependencies() {
        for (hasStorage, hasMutator) in [
            (false, false),
            (true, false),
            (false, true),
            (true, true),
        ] {
            let sut = makeDelegate()
            sut.setupServices()
            if !hasStorage { sut.storage = nil }
            if !hasMutator { sut.layoutMutator = nil }

            sut.setupControllers()

            let shouldBuild = hasStorage && hasMutator
            #expect((sut.viewController != nil) == shouldBuild)
            #expect((sut.lifecycle != nil) == shouldBuild)
            #expect((sut.windowController != nil) == shouldBuild)
        }
    }

    @Test("onClose 回调触发窗口 escape")
    func onClose_triggersEscape() throws {
        let sut = makeDelegate()
        sut.setupServices()
        sut.setupControllers()
        guard let lifecycle = sut.lifecycle,
              let windowController = sut.windowController else {
            Issue.record("controllers should be installed")
            return
        }
        var animationCompletions: [() -> Void] = []
        windowController.mainActorDispatcher = { operation in
            MainActor.assumeIsolated { operation() }
        }
        windowController.mainAsyncRunner = { $0() }
        windowController.targetScreenFrameProvider = { _ in
            NSRect(x: 0, y: 0, width: 800, height: 600)
        }
        windowController.runAnimated = { _, animations, completion in
            animations()
            animationCompletions.append(completion)
        }

        lifecycle.handleToggle()
        #expect(lifecycle.state == .opening)
        try #require(animationCompletions.count == 1)
        animationCompletions.removeFirst()()
        #expect(lifecycle.state == .visible)

        sut.viewController?.onClose?()

        #expect(lifecycle.state == .closing)
        #expect(animationCompletions.count == 1)
    }

    // MARK: - setupMenuBar

    @Test("setupMenuBar：登录项处于禁用态")
    func setupMenuBar_disabled() {
        let sut = makeDelegate()
        sut.loginItemStatusProvider = { .notRegistered }

        sut.setupMenuBar()

        #expect(sut.statusItem != nil)
        let loginItem = sut.statusItem?.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
        #expect(loginItem?.state == .off)
    }

    @Test("setupMenuBar：登录项处于启用态")
    func setupMenuBar_enabled() {
        let sut = makeDelegate()
        sut.loginItemStatusProvider = { .enabled }

        sut.setupMenuBar()

        let loginItem = sut.statusItem?.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
        #expect(loginItem?.state == .on)
    }

    @Test("setupMenuBar 只配置注入 status item 的 button")
    func setupMenuBarConfiguresInjectedButton() {
        let sut = makeDelegate()
        let button = NSStatusBarButton()
        let statusItem = MockStatusItem(button: button)
        sut.statusItemFactory = { statusItem }

        sut.setupMenuBar()

        #expect(sut.statusItem === statusItem)
        #expect(button.action == #selector(AppDelegate.statusItemClicked))
        #expect(button.target === sut)
    }

    // MARK: - toggleLoginItem

    @Test("toggleLoginItem：已启用时注销并更新菜单为禁用")
    func toggleLoginItem_unregisterWhenEnabled() {
        let sut = makeDelegate()
        var calls = 0
        sut.loginItemStatusProvider = { calls += 1; return calls <= 2 ? .enabled : .notRegistered }
        var unregisterCalled = false
        sut.loginItemUnregister = { unregisterCalled = true }
        sut.setupMenuBar()

        sut.toggleLoginItem()

        #expect(unregisterCalled)
        let loginItem = sut.statusItem?.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
        #expect(loginItem?.state == .off)
    }

    @Test("toggleLoginItem：未启用时注册并更新菜单为启用")
    func toggleLoginItem_registerWhenDisabled() {
        let sut = makeDelegate()
        var calls = 0
        sut.loginItemStatusProvider = { calls += 1; return calls <= 2 ? .notRegistered : .enabled }
        var registerCalled = false
        sut.loginItemRegister = { registerCalled = true }
        sut.setupMenuBar()

        sut.toggleLoginItem()

        #expect(registerCalled)
        let loginItem = sut.statusItem?.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
        #expect(loginItem?.state == .on)
    }

    @Test("toggleLoginItem：注册/注销失败时仅记录日志不崩溃")
    func toggleLoginItem_throws() {
        let sut = makeDelegate()
        var calls = 0
        var unregisterCalls = 0
        var failures: [NSError] = []
        sut.loginItemStatusProvider = { calls += 1; return calls <= 2 ? .enabled : .notRegistered }
        sut.loginItemUnregister = {
            unregisterCalls += 1
            throw NSError(domain: "sm", code: 3)
        }
        sut.loginItemFailureLogger = { failures.append($0 as NSError) }
        sut.setupMenuBar()

        sut.toggleLoginItem()

        let loginItem = sut.statusItem?.menu?.items.first {
            $0.action == #selector(AppDelegate.toggleLoginItem)
        }
        #expect(unregisterCalls == 1)
        #expect(failures.map(\.domain) == ["sm"])
        #expect(failures.map(\.code) == [3])
        #expect(loginItem?.state == .on)
    }

    // MARK: - setupHotkey

    @Test("setupHotkey：快捷键冲突时弹出占用提示")
    func setupHotkey_conflict() {
        let sut = makeDelegate()
        let hm = makeIsolatedHotkeyManager(accessibilityTrusted: true)
        sut.hotkeyManager = hm
        var alertMessages: [String] = []
        var openedURLs: [URL] = []
        sut.alertRunner = { alert in
            alertMessages.append(alert.messageText)
            return .alertFirstButtonReturn
        }
        sut.workspaceURLOpener = { openedURLs.append($0) }

        sut.setupHotkey()

        #expect(alertMessages == ["Option+Space 快捷键已被占用"])
        #expect(openedURLs.isEmpty)
    }

    @Test("setupHotkey：无权限时弹出授权提示并打开系统设置")
    func setupHotkey_permission() {
        let sut = makeDelegate()
        sut.hotkeyManager = makeIsolatedHotkeyManager(accessibilityTrusted: false)
        var openedURLs: [URL] = []
        sut.alertRunner = { _ in .alertFirstButtonReturn }
        sut.workspaceURLOpener = { openedURLs.append($0) }

        sut.setupHotkey()

        #expect(openedURLs == [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!,
        ])
    }

    @Test("setupHotkey：无权限时选择稍后设置不会打开系统设置")
    func setupHotkey_permission_secondButtonDoesNotOpenSettings() {
        let sut = makeDelegate()
        sut.hotkeyManager = makeIsolatedHotkeyManager(accessibilityTrusted: false)
        var openedURLs: [URL] = []
        sut.alertRunner = { _ in .alertSecondButtonReturn }
        sut.workspaceURLOpener = { openedURLs.append($0) }

        sut.setupHotkey()

        #expect(openedURLs.isEmpty)
    }

    @Test("setupHotkey：注册成功时不显示告警且不打开 URL")
    func setupHotkey_successDoesNotShowAlertOrOpenURL() throws {
        let sut = makeDelegate()
        let optionalPort = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
        let port = try #require(optionalPort)
        sut.hotkeyManager = makeIsolatedHotkeyManager(
            accessibilityTrusted: true,
            tapResult: port
        )
        var alertCount = 0
        var openedURLs: [URL] = []
        sut.alertRunner = { _ in
            alertCount += 1
            return .alertFirstButtonReturn
        }
        sut.workspaceURLOpener = { openedURLs.append($0) }

        sut.setupHotkey()

        #expect(alertCount == 0)
        #expect(openedURLs.isEmpty)
        sut.hotkeyManager.unregisterGlobalHotkey()
    }

    // MARK: - onToggle / onKeyDown 回调

    @Test("onToggle 回调切换窗口")
    func onToggle_togglesWindow() throws {
        let sut = makeDelegate()
        let hm = makeIsolatedHotkeyManager()
        sut.hotkeyManager = hm
        let lifecycle = WindowLifecycle()
        sut.windowController = LaunchPadWindowController(lifecycle: lifecycle, viewController: try makeViewController())
        sut.setupHotkey()

        sut.hotkeyManager.onToggle?()
        #expect(lifecycle.state == .opening)
    }

    @Test("visible idle 的已处理特殊键被吞")
    func localMonitorVisibleHandledSpecialKeyReturnsNil() throws {
        let sut = makeDelegate()
        let viewController = try makeViewController()
        _ = viewController.view
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: viewController
        )
        defer { manager.unregisterLocalMonitor() }

        let handledKeyCodes: [UInt16] = [53, 36, 126, 125, 123, 124, 48]
        for keyCode in handledKeyCodes {
            #expect(manager.localMonitorHandler?(keyEvent(keyCode: keyCode)) == nil)
        }
    }

    @Test("visible search 的 ignored 方向键放行原事件")
    func localMonitorVisibleIgnoredSpecialKeyReturnsOriginal() throws {
        let sut = makeDelegate()
        let viewController = try makeViewController()
        _ = viewController.view
        viewController.keyboardNavigator.mode = .search(query: "sa")
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: viewController
        )
        defer { manager.unregisterLocalMonitor() }
        let event = keyEvent(keyCode: 123)

        #expect(manager.localMonitorHandler?(event) === event)
    }

    @Test("visible idle 的 ignored Delete 放行原事件")
    func localMonitorVisibleIdleDeleteReturnsOriginal() throws {
        let sut = makeDelegate()
        let viewController = try makeViewController()
        _ = viewController.view
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: viewController
        )
        defer { manager.unregisterLocalMonitor() }
        let event = keyEvent(keyCode: 51)

        #expect(manager.localMonitorHandler?(event) === event)
    }

    @Test("visible 连续字符建立查询且两个事件均被吞")
    func localMonitorVisibleCharactersBuildSearchAndReturnNil() throws {
        let sut = makeDelegate()
        let viewController = try makeViewController()
        _ = viewController.view
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: viewController
        )
        defer { manager.unregisterLocalMonitor() }

        #expect(manager.localMonitorHandler?(keyEvent(keyCode: 1, characters: "s")) == nil)
        #expect(manager.localMonitorHandler?(keyEvent(keyCode: 0, characters: "a")) == nil)
        #expect(viewController.keyboardNavigator.mode == .search(query: "sa"))
    }

    @Test("flagsChanged 放行原事件")
    func localMonitorFlagsChangedReturnsOriginal() throws {
        let sut = makeDelegate()
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: try makeViewController()
        )
        defer { manager.unregisterLocalMonitor() }
        let event = flagsChangedEvent()

        #expect(manager.localMonitorHandler?(event) === event)
    }

    @Test("未知且无字符的 keyDown 放行原事件")
    func localMonitorUnknownEmptyCharacterReturnsOriginal() throws {
        let sut = makeDelegate()
        let viewController = try makeViewController()
        _ = viewController.view
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: viewController
        )
        defer { manager.unregisterLocalMonitor() }
        let event = keyEvent(keyCode: 110)

        #expect(manager.localMonitorHandler?(event) === event)
    }

    @Test("hidden 生命周期放行原事件")
    func localMonitorHiddenReturnsOriginal() throws {
        let sut = makeDelegate()
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: WindowLifecycle(),
            viewController: try makeViewController()
        )
        defer { manager.unregisterLocalMonitor() }
        let event = keyEvent(keyCode: 53)

        #expect(manager.localMonitorHandler?(event) === event)
    }

    @Test("缺少 view controller 时放行原事件")
    func localMonitorMissingViewControllerReturnsOriginal() {
        let sut = makeDelegate()
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: nil
        )
        defer { manager.unregisterLocalMonitor() }
        let event = keyEvent(keyCode: 53)

        #expect(manager.localMonitorHandler?(event) === event)
    }

    @Test("存在但未加载的 view controller 放行且不强制加载")
    func localMonitorUnloadedViewControllerReturnsOriginal() throws {
        let sut = makeDelegate()
        let viewController = try makeViewController()
        let manager = prepareKeyboardMonitor(
            sut,
            lifecycle: visibleLifecycle(),
            viewController: viewController
        )
        defer { manager.unregisterLocalMonitor() }
        let event = keyEvent(keyCode: 125)

        #expect(viewController.isViewLoaded == false)
        #expect(manager.localMonitorHandler?(event) === event)
        #expect(viewController.isViewLoaded == false)
    }

    // MARK: - performInitialScan

    @Test("performInitialScan 传递空扫描和目标容量到 batch writer")
    func performInitialScanForwardsEmptyScanToBatchWriter() {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService(), excludedBundleIds: [])
        sut.targetWindowContentSizeProvider = { CGSize(width: 1440, height: 598) }

        sut.performInitialScan()

        #expect(writer.receivedApps == [[]])
        #expect(writer.receivedCapacities == [28])
    }

    @Test("performInitialScan 与 performIncrementalScan 共用 batch writer")
    func scanEntryPointsUseTheSameBatchWriter() {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: makeFileSystemWithApps(count: 1), excludedBundleIds: [])

        sut.performInitialScan()
        sut.performIncrementalScan()

        #expect(writer.receivedApps.count == 2)
        #expect(writer.receivedApps.allSatisfy { $0.map(\.bundleId) == ["com.test.app0"] })
    }

    // MARK: - 其余方法

    @Test("statusItemClicked 切换窗口")
    func statusItemClicked_toggles() throws {
        let sut = makeDelegate()
        let lifecycle = WindowLifecycle()
        let windowController = LaunchPadWindowController(
            lifecycle: lifecycle,
            viewController: try makeViewController()
        )
        windowController.mainActorDispatcher = { operation in
            MainActor.assumeIsolated { operation() }
        }
        windowController.targetScreenFrameProvider = { _ in nil }
        sut.windowController = windowController

        sut.statusItemClicked()

        #expect(lifecycle.state == .opening)
    }

    @Test("setupServices 仅转发注入的安全数据库路径")
    func setupServices_usesInjectedDatabasePath() throws {
        let sut = makeDelegate()
        let safePath = "/tmp/launchpad-appdelegate-\(UUID().uuidString).sqlite3"
        var providerCalls = 0
        var factoryPaths: [String] = []
        var removedPaths: [String] = []
        sut.databasePathProvider = {
            providerCalls += 1
            return safePath
        }
        sut.databaseRemover = { removedPaths.append($0) }
        sut.storageFactory = { path in
            factoryPaths.append(path)
            return try StorageManager(dbPath: ":memory:")
        }

        sut.setupServices()

        #expect(providerCalls == 1)
        #expect(factoryPaths == [safePath])
        #expect(removedPaths.isEmpty)
        #expect(sut.storage != nil)
    }

    @Test("setupFileWatcher：文件变更触发一次批量增量扫描")
    func setupFileWatcherTriggersIncrementalScan() async throws {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService(), excludedBundleIds: [])
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        sut.watchedPaths = ["/Applications"]
        sut.fileWatcherFactory = { FileWatcher(debounceInterval: 0.1, backend: backend, scheduler: scheduler) }
        sut.setupFileWatcher()
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 0.1)
        #expect(writer.receivedApps.count == 1)
    }

    @Test("setupFileWatcher：后端启动失败时不保留监控器并记录固定分类")
    func setupFileWatcherStartFailureClearsWatcherAndLogs() {
        let sut = makeDelegate()
        let backend = MockFileEventStream()
        backend.startResult = false
        var categories: [String] = []
        sut.watchedPaths = ["/Applications"]
        sut.scanFailureLogger = { categories.append($0) }
        sut.fileWatcherFactory = {
            FileWatcher(backend: backend, scheduler: MockScheduler())
        }

        sut.setupFileWatcher()

        #expect(sut.fileWatcher == nil)
        #expect(backend.stopCallCount == 0)
        #expect(categories == ["file-watcher-start-failed"])
    }

    @Test("applicationWillTerminate 重复调用只释放每项进程资源一次")
    func applicationWillTerminateIsIdempotent() throws {
        let sut = makeDelegate()
        let backend = MockFileEventStream()
        let watcher = FileWatcher(backend: backend, scheduler: MockScheduler())
        #expect(watcher.start(paths: ["/Applications"]) {})
        sut.fileWatcher = watcher

        let manager = makeIsolatedHotkeyManager(accessibilityTrusted: true)
        let optionalPort = CFMachPortCreate(nil, { _, _, _, _ in }, nil, nil)
        let port = try #require(optionalPort)
        let localToken = NSObject()
        var sourceRemovals = 0
        var tapStates: [Bool] = []
        var localRemovals = 0
        manager.eventTapCreator = { _, _, _ in port }
        manager.runLoopSourceRemover = { _ in sourceRemovals += 1 }
        manager.eventTapEnabler = { _, enabled in tapStates.append(enabled) }
        manager.localMonitorInstaller = { _ in localToken }
        manager.localMonitorRemover = { token in
            #expect(token as AnyObject === localToken)
            localRemovals += 1
        }
        #expect(manager.registerGlobalHotkey(keyCode: 49, modifiers: .option))
        manager.registerLocalMonitor()
        sut.hotkeyManager = manager

        let statusItem = MockStatusItem()
        var statusRemovals = 0
        sut.statusItem = statusItem
        sut.statusItemRemover = { item in
            #expect(item === statusItem)
            statusRemovals += 1
        }
        let notification = Notification(name: NSApplication.willTerminateNotification)

        sut.applicationWillTerminate(notification)
        sut.applicationWillTerminate(notification)

        #expect(backend.stopCallCount == 1)
        #expect(sourceRemovals == 1)
        #expect(tapStates == [true, false])
        #expect(localRemovals == 1)
        #expect(statusRemovals == 1)
        #expect(sut.fileWatcher == nil)
        #expect(sut.statusItem == nil)
    }

    @Test("applicationWillTerminate 在资源均为空时保持幂等")
    func applicationWillTerminateWithNoResourcesIsIdempotent() {
        let sut = AppDelegate()
        var statusRemovals = 0
        sut.statusItemRemover = { _ in statusRemovals += 1 }
        let notification = Notification(name: NSApplication.willTerminateNotification)

        sut.applicationWillTerminate(notification)
        sut.applicationWillTerminate(notification)

        #expect(statusRemovals == 0)
    }

    // MARK: - 默认闭包覆盖

    @Test("默认 storageFactory 可安全调用 - 真实 :memory: 数据库")
    func defaultStorageFactory_callable() throws {
        let sut = AppDelegate()
        let storage = try sut.storageFactory(":memory:")
        let expected = TestDataFactory.makePageItem(
            id: 0,
            uuid: "default-storage-factory-page",
            type: .page,
            ordering: 0
        )

        let insertedID = try storage.insertItem(expected)
        let roots = try storage.fetchAllItems(parentId: nil)

        #expect(insertedID > 0)
        #expect(roots.map(\.id) == [insertedID])
        #expect(roots.map(\.uuid) == [expected.uuid])
    }

    // MARK: - weak self 防御分支（guard let self else）

    @Test("setupHotkey onToggle：delegate 释放后 runner 仍交付安全 no-op action")
    func setupHotkey_onToggle_releasedDelegateRunsSafeNoOp() {
        let runnerCalls = CallRecorder()
        weak var weakDelegate: AppDelegate?
        var sut: AppDelegate? = makeDelegate()
        let hm = makeIsolatedHotkeyManager()
        weakDelegate = sut
        sut?.hotkeyToggleRunner = { action in
            MainActor.assumeIsolated {
                runnerCalls.count += 1
                action()
            }
        }
        sut?.hotkeyManager = hm
        sut?.setupHotkey()

        sut = nil
        #expect(weakDelegate == nil)

        hm.onToggle?()

        #expect(runnerCalls.count == 1)
    }

    @Test("setupHotkey onKeyDown: 闭包内 weak self 已 nil 时 guard else 分支（覆盖 L260）")
    func setupHotkey_onKeyDown_weakSelfNil_guardElse() {
        weak var weakDelegate: AppDelegate?
        var sut: AppDelegate? = makeDelegate()
        let hm = makeIsolatedHotkeyManager()
        weakDelegate = sut
        sut?.hotkeyManager = hm
        sut?.setupHotkey()
        defer { hm.unregisterLocalMonitor() }

        sut = nil
        #expect(weakDelegate == nil)

        let event = keyEvent(keyCode: 0)

        #expect(hm.localMonitorHandler?(event) === event)
    }

    @Test("首次扫描使用目标显示器真实容量")
    func initialScanUsesTargetViewportCapacity() {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: makeFileSystemWithApps(count: 29), excludedBundleIds: [])
        sut.targetWindowContentSizeProvider = { CGSize(width: 1440, height: 598) }

        sut.performInitialScan()

        #expect(writer.receivedApps.count == 1)
        #expect(writer.receivedApps.first?.count == 29)
        #expect(writer.receivedCapacities == [28])
    }

    @Test("成功扫描只刷新已加载 VC 一次")
    func successfulScanReloadsOnlyLoadedViewController() throws {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: makeFileSystemWithApps(count: 1), excludedBundleIds: [])
        let viewController = try makeViewController()
        sut.viewController = viewController
        var reloads = 0
        sut.viewControllerReloader = { _ in reloads += 1 }

        sut.performInitialScan()
        #expect(!viewController.isViewLoaded)
        #expect(reloads == 0)

        _ = viewController.view
        sut.performIncrementalScan()
        #expect(reloads == 1)
    }

    @Test("根目录读取失败禁止 destructive sync，后续完整扫描可恢复")
    func incompleteRootDiscoverySkipsWriteAndAcceptsLaterCompleteScan() throws {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        let fileSystem = makeFileSystemWithApps(count: 1)
        fileSystem.shouldThrowOnContentsOfDirectory = true
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: fileSystem, excludedBundleIds: [])
        let viewController = try makeViewController()
        _ = viewController.view
        sut.viewController = viewController
        var reloads = 0
        var categories: [String] = []
        sut.viewControllerReloader = { _ in reloads += 1 }
        sut.scanFailureLogger = { categories.append($0) }

        sut.performIncrementalScan()

        #expect(writer.receivedApps.isEmpty)
        #expect(reloads == 0)
        #expect(categories == ["app-discovery-incomplete"])

        fileSystem.shouldThrowOnContentsOfDirectory = false
        sut.performIncrementalScan()

        #expect(writer.receivedApps.map { $0.map(\.bundleId) } == [["com.test.app0"]])
        #expect(reloads == 1)
        #expect(categories == ["app-discovery-incomplete"])
    }

    @Test("已枚举 app 的 plist 不可读禁止 destructive sync，后续完整扫描可恢复")
    func unreadableBundleDiscoverySkipsWriteAndAcceptsLaterCompleteScan() throws {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        let fileSystem = MockFileSystemService()
        let root = URL(fileURLWithPath: "/Applications")
        let appURL = root.appendingPathComponent("Existing.app")
        fileSystem.directoryContentsMap[root] = [appURL]
        fileSystem.unreadableBundleURLs = [appURL]
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: fileSystem, excludedBundleIds: [])
        let viewController = try makeViewController()
        _ = viewController.view
        sut.viewController = viewController
        var reloads = 0
        var categories: [String] = []
        sut.viewControllerReloader = { _ in reloads += 1 }
        sut.scanFailureLogger = { categories.append($0) }

        sut.performIncrementalScan()

        #expect(writer.receivedApps.isEmpty)
        #expect(reloads == 0)
        #expect(categories == ["app-discovery-incomplete"])

        fileSystem.bundleInfos[appURL] = [
            "CFBundleName": "Existing",
            "CFBundleIdentifier": "com.test.existing",
        ]
        fileSystem.unreadableBundleURLs = []
        sut.performIncrementalScan()

        #expect(writer.receivedApps.map { $0.map(\.bundleId) } == [["com.test.existing"]])
        #expect(reloads == 1)
        #expect(categories == ["app-discovery-incomplete"])
    }

    @Test("批事务失败不刷新并只记录固定分类")
    func scanBatchFailureKeepsLoadedUIAndLogs() throws {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        writer.error = TestError.generic
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: makeFileSystemWithApps(count: 1), excludedBundleIds: [])
        let viewController = try makeViewController()
        _ = viewController.view
        sut.viewController = viewController
        var reloads = 0
        var categories: [String] = []
        sut.viewControllerReloader = { _ in reloads += 1 }
        sut.scanFailureLogger = { categories.append($0) }

        sut.performInitialScan()
        sut.performIncrementalScan()

        #expect(reloads == 0)
        #expect(categories == ["scan-batch-failed", "scan-batch-failed"])
    }

    @Test("批 writer 返回失败结果时不刷新并只记录固定分类")
    func unsuccessfulScanBatchResultKeepsLoadedUIAndLogs() throws {
        let sut = makeDelegate()
        let writer = RecordingScanBatchWriter()
        var failedResult = ScanSyncResult()
        failedResult.recordFailure()
        writer.result = failedResult
        sut.scanBatchWriter = writer
        sut.appScanner = AppScanner(fileSystemService: makeFileSystemWithApps(count: 1), excludedBundleIds: [])
        let viewController = try makeViewController()
        _ = viewController.view
        sut.viewController = viewController
        var reloads = 0
        var categories: [String] = []
        sut.viewControllerReloader = { _ in reloads += 1 }
        sut.scanFailureLogger = { categories.append($0) }

        sut.performInitialScan()

        #expect(reloads == 0)
        #expect(categories == ["scan-batch-failed"])
    }
}
#endif
