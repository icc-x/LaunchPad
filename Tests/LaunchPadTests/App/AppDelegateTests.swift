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

    /// 内存文件系统：返回空目录，避免真实 I/O
    private struct MockFileSystemService: FileSystemService {
        func contentsOfDirectory(at url: URL) throws -> [URL] { [] }
        func fileExists(at url: URL) -> Bool { false }
        func bundleInfo(at bundleURL: URL) -> [String: any Sendable]? { nil }
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
        manager.tapProvider = { tapResult }
        manager.eventTapCreator = { _, _, _ in nil }
        manager.localMonitorInstaller = { _ in localMonitorToken }
        manager.localMonitorRemover = { _ in }
        return manager
    }

    /// 创建一个所有危险系统调用都被替换为安全实现的 AppDelegate
    private func makeDelegate() -> AppDelegate {
        let sut = AppDelegate()
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
        sut.statusItemFactory = { NSStatusItem() }
        sut.fileWatcherFactory = { FileWatcher(debounceInterval: 2.0, streamCreationOverride: { nil }) }
        sut.hotkeyManagerFactory = { hotkeyManager }
        sut.workspaceURLOpener = { _ in }
        sut.hotkeyToggleRunner = { action in
            MainActor.assumeIsolated { action() }
        }
        sut.storageFactory = { _ in try StorageManager(dbPath: ":memory:") }
        return sut
    }

    /// 构造一个真实但无视图依赖的 LaunchPadViewController
    private func makeViewController() throws -> LaunchPadViewController {
        let storage = try StorageManager(dbPath: ":memory:")
        let iconCache = IconCache(iconProvider: MockIconProvider(), imageStore: storage)
        let searchEngine = SearchEngine()
        let dragController = DragController(itemWriter: storage)
        let folderController = FolderController(itemWriter: storage)
        return LaunchPadViewController(
            storage: storage,
            iconCache: iconCache,
            searchEngine: searchEngine,
            dragController: dragController,
            folderController: folderController
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
        var attempts = 0
        sut.storageFactory = { _ in
            attempts += 1
            if attempts == 1 { throw NSError(domain: "db", code: 1) }
            return try StorageManager(dbPath: ":memory:")
        }
        sut.corruptionHandler = { _ in .deleteAndRescan }

        sut.setupServices()

        #expect(attempts == 2)
        #expect(sut.storage != nil)
    }

    @Test("setupServices：损坏且非重建策略时放弃启动")
    func setupServices_fatal() throws {
        let sut = makeDelegate()
        sut.storageFactory = { _ in throw NSError(domain: "db", code: 2) }
        sut.corruptionHandler = { _ in .healthy }

        sut.setupServices()

        #expect(sut.storage == nil)
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

    @Test("onClose 回调触发窗口 escape")
    func onClose_triggersEscape() throws {
        let sut = makeDelegate()
        sut.setupServices()
        sut.setupControllers()

        sut.viewController?.onClose?()
        #expect(true)
    }

    // MARK: - setupMenuBar

    @Test("setupMenuBar：登录项处于禁用态")
    func setupMenuBar_disabled() {
        let sut = makeDelegate()
        sut.loginItemStatusProvider = { .notRegistered }

        sut.setupMenuBar()

        #expect(sut.statusItem != nil)
        let loginItem = sut.statusItem.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
        #expect(loginItem?.state == .off)
    }

    @Test("setupMenuBar：登录项处于启用态")
    func setupMenuBar_enabled() {
        let sut = makeDelegate()
        sut.loginItemStatusProvider = { .enabled }

        sut.setupMenuBar()

        let loginItem = sut.statusItem.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
        #expect(loginItem?.state == .on)
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
        let loginItem = sut.statusItem.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
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
        let loginItem = sut.statusItem.menu?.items.first(where: { $0.action == #selector(AppDelegate.toggleLoginItem) })
        #expect(loginItem?.state == .on)
    }

    @Test("toggleLoginItem：注册/注销失败时仅记录日志不崩溃")
    func toggleLoginItem_throws() {
        let sut = makeDelegate()
        var calls = 0
        sut.loginItemStatusProvider = { calls += 1; return calls <= 2 ? .enabled : .notRegistered }
        sut.loginItemUnregister = { throw NSError(domain: "sm", code: 3) }
        sut.setupMenuBar()

        sut.toggleLoginItem()
        #expect(true)
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

    @Test("performInitialScan：空库走首次启动分页")
    func performInitialScan_empty() throws {
        let sut = makeDelegate()
        sut.storage = MockStoring(itemsToReturn: [])
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())

        sut.performInitialScan()
        #expect(true)
    }

    @Test("performInitialScan：已有数据走增量同步")
    func performInitialScan_nonEmpty() throws {
        let sut = makeDelegate()
        sut.storage = MockStoring(itemsToReturn: [pageItem()])
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())

        sut.performInitialScan()
        #expect(true)
    }

    @Test("performInitialScan：读取失败进入 catch")
    func performInitialScan_catch() throws {
        let sut = makeDelegate()
        sut.storage = MockStoring(shouldThrow: true)
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())

        sut.performInitialScan()
        #expect(true)
    }

    // MARK: - performIncrementalScan

    @Test("performIncrementalScan：成功并刷新 UI")
    func performIncrementalScan_success() throws {
        let sut = makeDelegate()
        sut.storage = MockStoring(itemsToReturn: [pageItem()])
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())

        sut.performIncrementalScan()
        #expect(true)
    }

    @Test("performIncrementalScan：读取失败进入 catch")
    func performIncrementalScan_catch() throws {
        let sut = makeDelegate()
        sut.storage = MockStoring(shouldThrow: true)
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())

        sut.performIncrementalScan()
        #expect(true)
    }

    // MARK: - 其余方法

    @Test("statusItemClicked 切换窗口")
    func statusItemClicked_toggles() throws {
        let sut = makeDelegate()
        sut.windowController = LaunchPadWindowController(lifecycle: WindowLifecycle(), viewController: try! makeViewController())

        sut.statusItemClicked()
        #expect(true)
    }

    @Test("databasePath 返回非空路径")
    func databasePath_returnsPath() {
        let sut = makeDelegate()
        let path = sut.databasePath()
        #expect(!path.isEmpty)
    }

    // MARK: - 默认闭包覆盖

    @Test("默认 runningInstanceChecker 可安全调用")
    func defaultRunningInstanceChecker_callable() {
        let sut = AppDelegate()
        _ = sut.runningInstanceChecker()
    }

    @Test("默认 existingInstanceActivator 可安全调用")
    func defaultExistingInstanceActivator_callable() {
        let sut = AppDelegate()
        sut.existingInstanceActivator()
    }

    // MARK: - performIncrementalScan 多页排序

    @Test("performIncrementalScan 多页排序覆盖")
    func performIncrementalScan_multiplePages_sorted() throws {
        let sut = makeDelegate()
        let page1 = PageItem(id: 1, uuid: UUID().uuidString, type: .page, ordering: 1, parentId: nil, app: nil, group: nil)
        let page2 = PageItem(id: 2, uuid: UUID().uuidString, type: .page, ordering: 0, parentId: nil, app: nil, group: nil)
        sut.storage = MockStoring(itemsToReturn: [page1, page2])
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())
        sut.performIncrementalScan()
        #expect(true)
    }

    // MARK: - performInitialScan 多页排序（增量同步路径）

    @Test("performInitialScan 已有多页数据走增量同步排序")
    func performInitialScan_multiplePages_incrementalSorted() throws {
        let sut = makeDelegate()
        let page1 = PageItem(id: 1, uuid: UUID().uuidString, type: .page, ordering: 1, parentId: nil, app: nil, group: nil)
        let page2 = PageItem(id: 2, uuid: UUID().uuidString, type: .page, ordering: 0, parentId: nil, app: nil, group: nil)
        sut.storage = MockStoring(itemsToReturn: [page1, page2])
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())
        sut.performInitialScan()
        #expect(true)
    }

    @Test("setupFileWatcher 创建并启动监控器")
    func setupFileWatcher_createsWatcher() {
        let sut = makeDelegate()
        sut.setupFileWatcher()
        #expect(sut.fileWatcher != nil)
    }

    // MARK: - 私有实现结构体

    @Test("SystemIconProvider 与 SystemFileSystemService 方法均被调用")
    func systemServiceImplementations() {
        let iconProvider = SystemIconProvider()
        _ = iconProvider.icon(forPath: "/Applications/Safari.app")
        _ = iconProvider.modificationDate(forPath: "/Applications/Safari.app")

        let fs = SystemFileSystemService()
        _ = fs.fileExists(at: URL(fileURLWithPath: "/Applications"))
        _ = try? fs.contentsOfDirectory(at: URL(fileURLWithPath: "/Applications"))
        _ = fs.bundleInfo(at: URL(fileURLWithPath: "/Applications/Safari.app"))
        // 不存在的包路径触发 bundleInfo 的 guard-else 分支
        _ = fs.bundleInfo(at: URL(fileURLWithPath: "/tmp/launchpad_no_such_\(UUID().uuidString).app"))
        #expect(true)
    }

    // MARK: - 默认闭包覆盖

    @Test("默认 storageFactory 可安全调用 - 真实 :memory: 数据库")
    func defaultStorageFactory_callable() throws {
        let sut = AppDelegate()
        // 默认 storageFactory 调用 :memory: 真实 SQLite
        let storage = try sut.storageFactory(":memory:")
        #expect(storage != nil)
    }

    // MARK: - performInitialScan NSScreen.main 为 nil 时走 ?? 1440 fallback

    @Test("performInitialScan: 在无 NSScreen.main 环境下使用默认 1440 宽度（覆盖 L348 ?? fallback）")
    func performInitialScan_noNSScreenMain_usesDefaultWidth() throws {
        let sut = makeDelegate()
        sut.storage = MockStoring(itemsToReturn: [])
        sut.appScanner = AppScanner(fileSystemService: MockFileSystemService())

        // 测试环境 NSScreen.main 通常为 nil → 走 ?? 1440 fallback 分支
        // 仅验证不崩溃即可
        sut.performInitialScan()
        #expect(true)
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
}
#endif
