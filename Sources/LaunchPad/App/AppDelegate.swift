import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols
import ServiceManagement

@MainActor
protocol StatusItemManaging: AnyObject {
    var button: NSStatusBarButton? { get }
    var menu: NSMenu? { get set }
}

@MainActor
extension NSStatusItem: StatusItemManaging {}

/// 应用入口 — 菜单栏图标、服务初始化、热键注册
/// Agent 应用模式（无 Dock 图标）
@preconcurrency @MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    var storage: (any DataStoring)!
    var layoutMutator: (any LayoutMutating)!
    var scanBatchWriter: (any ScanBatchWriting)!
    var iconCache: IconCache!
    var appScanner: AppScanner!
    var searchEngine: SearchEngine!
    var hotkeyManager: HotkeyManager!
    var fileWatcher: FileWatcher?

    // MARK: - Controllers

    var lifecycle: WindowLifecycle!
    var windowController: LaunchPadWindowController!
    var viewController: LaunchPadViewController?

    // MARK: - Menu Bar

    var statusItem: (any StatusItemManaging)?

    // MARK: - Test Injection Points

    /// 数据库工厂（默认创建真实 StorageManager，测试可注入以触发 SQLite 损坏恢复分支）
    var storageFactory: (String) throws -> StorageManager = { try StorageManager(dbPath: $0) }

    /// 数据库路径提供器（默认沿用生产路径创建逻辑，测试注入临时路径以隔离用户数据）
    lazy var databasePathProvider: () -> String = { [unowned self] in self.databasePath() }

    /// 数据库删除器（默认删除生产数据库，测试注入以隔离文件系统副作用）
    var databaseRemover: (String) throws -> Void = { try FileManager.default.removeItem(atPath: $0) }

    /// 激活策略设置器（默认走 NSApp，测试注入避免无 NSApplication 实例时崩溃）
    var activationPolicySetter: (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }

    /// 告警展示器（默认弹真实 NSAlert，测试注入为同步记录以避免 runModal 阻塞）
    var alertRunner: (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }

    /// 多实例检测（默认查系统运行实例，测试可注入以触发/跳过终止分支）
    var runningInstanceChecker: () -> Bool = {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).count > 1
    }

    /// 激活已有实例（默认调用系统 API，测试注入避免真实激活）
    var existingInstanceActivator: () -> Void = {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
    }

    /// 应用终止器（默认 NSApp.terminate，测试注入避免真实退出）
    var appTerminator: () -> Void = { NSApp.terminate(nil) }

    /// SQLite 损坏处理策略（默认走 ErrorRecovery，测试可强制 .deleteAndRescan）
    var corruptionHandler: (String) -> ErrorRecovery.ErrorStrategy = { ErrorRecovery.handleSQLiteCorruption(dbPath: $0) }

    /// 主线程异步派发（默认 DispatchQueue.main.async，测试注入为同步执行以覆盖告警分支）
    var mainAsyncRunner: (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }

    /// 登录项状态读取（默认 SMAppService.mainApp.status，测试注入）
    var loginItemStatusProvider: () -> SMAppService.Status = { SMAppService.mainApp.status }

    /// 登录项注销（默认 SMAppService.mainApp.unregister，测试注入）
    var loginItemUnregister: () throws -> Void = { try SMAppService.mainApp.unregister() }

    /// 登录项注册（默认 SMAppService.mainApp.register，测试注入）
    var loginItemRegister: () throws -> Void = { try SMAppService.mainApp.register() }

    /// 登录项切换失败记录边界；测试可观察精确错误而不依赖系统日志。
    var loginItemFailureLogger: (any Error) -> Void = { error in
        NSLog("[AppDelegate] Failed to toggle login item: \(error)")
    }

    /// 状态栏图标工厂（默认创建真实 item，测试返回纯协议实现）。
    var statusItemFactory: () -> any StatusItemManaging = {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    }

    /// 状态栏图标释放边界；测试替换后不会触碰进程级 NSStatusBar。
    var statusItemRemover: (any StatusItemManaging) -> Void = { item in
        guard let statusItem = item as? NSStatusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    /// 文件监控器工厂（默认创建真实 FileWatcher，测试注入安全检查版本避免真实 FSEvent 监听）
    var fileWatcherFactory: () -> FileWatcher = { FileWatcher(debounceInterval: 2.0) }

    /// 热键管理器工厂（测试注入隔离系统边界）
    var hotkeyManagerFactory: () -> HotkeyManager = { HotkeyManager() }

    /// 系统设置 URL 打开边界（测试可注入）
    var workspaceURLOpener: (URL) -> Void = {
        _ = NSWorkspace.shared.open($0)
    }

    /// 应用启动边界；由 AppDelegate 统一持有生产 NSWorkspace 适配器。
    var applicationOpener: (URL) -> Void = { url in
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: url,
            configuration: configuration
        )
    }

    /// 热键切换交付器（测试可同步执行）
    var hotkeyToggleRunner:
        @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = {
        action in
        Task { @MainActor in action() }
    }

    /// 应用发现根；用户 Applications 缺失是权威空根，其余根必须可枚举。
    var discoveryRoots: [AppDiscoveryRoot] = [
        AppDiscoveryRoot(
            url: URL(fileURLWithPath: "/Applications"),
            missingPolicy: .required
        ),
        AppDiscoveryRoot(
            url: URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
            missingPolicy: .optional
        ),
        AppDiscoveryRoot(
            url: URL(fileURLWithPath: "/System/Applications"),
            missingPolicy: .required
        ),
    ]

    /// 测试注入兼容入口；显式替换的路径默认都属于 required root。
    var watchedPaths: [String] {
        get { discoveryRoots.map(\.url.path) }
        set {
            discoveryRoots = newValue.map {
                AppDiscoveryRoot(
                    url: URL(fileURLWithPath: $0),
                    missingPolicy: .required
                )
            }
        }
    }

    var targetWindowContentSizeProvider: () -> CGSize = {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.main
        return screen?.frame.size ?? CGSize(width: 1440, height: 900)
    }

    var viewControllerReloader: (LaunchPadViewController) -> Void = { $0.loadData() }
    var scanFailureLogger: (String) -> Void = { NSLog("[AppDelegate] %@", $0) }

    // MARK: - Application Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 多实例防护：激活已有实例，退出当前
        if runningInstanceChecker() {
            existingInstanceActivator()
            appTerminator()
            return
        }

        // Agent app: no Dock icon
        activationPolicySetter(.accessory)

        setupServices()
        guard storage != nil, layoutMutator != nil, scanBatchWriter != nil else {
            NSLog("[AppDelegate] Fatal: could not initialize database, aborting launch")
            return
        }
        setupControllers()
        setupMenuBar()
        setupHotkey()
        performInitialScan()
        setupFileWatcher()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        fileWatcher?.stop()
        fileWatcher = nil
        hotkeyManager?.unregisterLocalMonitor()
        hotkeyManager?.unregisterGlobalHotkey()
        if let statusItem {
            statusItemRemover(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Service Setup

    private func installStorage(_ manager: StorageManager) {
        storage = manager
        layoutMutator = manager
        scanBatchWriter = manager
    }

    func setupServices() {
        // Database
        storage = nil
        layoutMutator = nil
        scanBatchWriter = nil
        let dbPath = databasePathProvider()
        do {
            installStorage(try storageFactory(dbPath))
        } catch {
            // If DB is corrupted, delete and retry
            let strategy = corruptionHandler(dbPath)
            if case .deleteAndRescan = strategy {
                try? databaseRemover(dbPath)
                if let recovered = try? storageFactory(dbPath) {
                    installStorage(recovered)
                }
            }
        }
        // 数据库仍不可用则放弃启动，交由 applicationDidFinishLaunching 记录并退出
        guard storage != nil else { return }

        // Icon cache
        let iconProvider = SystemIconProvider()
        iconCache = IconCache(iconProvider: iconProvider, imageStore: storage)

        // Scanner
        let fileSystemService = SystemFileSystemService()
        appScanner = AppScanner(fileSystemService: fileSystemService)

        // Search
        searchEngine = SearchEngine()

        // Hotkey
        hotkeyManager = hotkeyManagerFactory()
    }

    func setupControllers() {
        guard let storage, let layoutMutator else { return }

        // Drag controller
        let dragController = DragController()

        // Folder controller
        let folderController = FolderController(itemWriter: storage)

        // View controller
        let vc = LaunchPadViewController(
            storage: storage,
            layoutMutator: layoutMutator,
            iconCache: iconCache,
            searchEngine: searchEngine,
            dragController: dragController,
            folderController: folderController,
            applicationOpener: applicationOpener
        )
        viewController = vc

        // Lifecycle
        lifecycle = WindowLifecycle()

        // Window controller
        windowController = LaunchPadWindowController(
            lifecycle: lifecycle,
            viewController: vc
        )
        // ESC 关闭窗口：ViewController.onClose → lifecycle.handleEscape()
        vc.onClose = { [weak self] in
            self?.windowController?.escape()
        }
    }

    // MARK: - Menu Bar

    func setupMenuBar() {
        let statusItem = statusItemFactory()
        self.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.applicationIconName)
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle LaunchPad", action: #selector(statusItemClicked), keyEquivalent: ""))

        // 登录自启动开关
        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.state = loginItemStatusProvider() == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func statusItemClicked() {
        windowController.toggle()
    }

    @objc func toggleLoginItem() {
        do {
            if loginItemStatusProvider() == .enabled {
                try loginItemUnregister()
            } else {
                try loginItemRegister()
            }
            // 更新菜单状态
            if let menu = statusItem?.menu,
               let item = menu.items.first(where: { $0.action == #selector(toggleLoginItem) }) {
                item.state = loginItemStatusProvider() == .enabled ? .on : .off
            }
        } catch {
            loginItemFailureLogger(error)
        }
    }

    // MARK: - Hotkey

    func setupHotkey() {
        let runner = hotkeyToggleRunner
        hotkeyManager.onToggle = { @Sendable [weak self] in
            runner { [weak self] in self?.windowController.toggle() }
        }

        let registered = hotkeyManager.registerGlobalHotkey(keyCode: 49, modifiers: .option) // Option+Space

        if !registered && hotkeyManager.hasConflict {
            // 快捷键被其他应用占用，提示用户
            mainAsyncRunner {
                let alert = NSAlert()
                alert.messageText = "Option+Space 快捷键已被占用"
                alert.informativeText = "另一个应用正在使用 Option+Space 快捷键。请关闭冲突应用或在 LaunchPad 设置中选择其他快捷键。"
                alert.addButton(withTitle: "OK")
                self.alertRunner(alert)
            }
        } else if !registered {
            // 无 Input Monitoring 权限，引导用户授权
            mainAsyncRunner {
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = "LaunchPad 需要 Input Monitoring（输入监控）权限才能响应 Option+Space 快捷键。\n\n请在「系统设置 → 隐私与安全性 → 输入监控」中启用 LaunchPad。"
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "稍后设置")
                let response = self.alertRunner(alert)
                if response == .alertFirstButtonReturn {
                    // 打开 Input Monitoring 设置页面
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        self.workspaceURLOpener(url)
                    }
                }
            }
        }

        hotkeyManager.onKeyDown = { @Sendable [weak self] event in
            guard let self else { return event }
            guard event.type == .keyDown else { return event }

            // 提取非 Sendable NSEvent 的数据，避免跨 actor 边界发送
            let keyCode = event.keyCode
            let characters = event.characters
            // 本地事件监视器在主线程运行，此处通过 MainActor.assumeIsolated 安全访问 @MainActor 状态
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard self.lifecycle.state == .visible,
                      let viewController = self.viewController,
                      viewController.isViewLoaded else {
                    return false
                }

                let key: KeyboardNavigator.Key? = switch keyCode {
                case 53:  .escape
                case 36:  .enter
                case 126: .upArrow
                case 125: .downArrow
                case 123: .leftArrow
                case 124: .rightArrow
                case 48:  .tab
                case 51:  .delete
                default:  nil
                }

                if let key {
                    return viewController.handleKeyEvent(key) != .ignored
                }
                guard let characters, !characters.isEmpty else { return false }
                return viewController.handleCharacterInput(characters) != .ignored
            }
            return handled ? nil : event
        }
        hotkeyManager.registerLocalMonitor()
    }

    // MARK: - File System Monitoring

    func setupFileWatcher() {
        let watcher = fileWatcherFactory()
        guard watcher.start(paths: watchedPaths, onChange: { [weak self] in
            self?.performIncrementalScan()
        }) else {
            fileWatcher = nil
            scanFailureLogger("file-watcher-start-failed")
            return
        }
        self.fileWatcher = watcher
    }

    private func reloadLoadedViewControllerAfterScan() {
        mainAsyncRunner { [weak self] in
            guard let self,
                  let viewController = self.viewController,
                  viewController.isViewLoaded else { return }
            self.viewControllerReloader(viewController)
        }
    }

    private func performScan() {
        let discovery = appScanner.scanDirectories(discoveryRoots)
        guard discovery.isComplete else {
            scanFailureLogger("app-discovery-incomplete")
            return
        }
        let viewport = LaunchPadViewController.gridViewportSize(
            forWindowContentSize: targetWindowContentSizeProvider()
        )
        let capacity = GridLayoutCalculator.calculate(viewportSize: viewport).itemsPerPage
        do {
            let result = try scanBatchWriter.synchronizeInstalledApps(
                discovery.apps,
                initialPageCapacity: capacity
            )
            guard result.isSuccessful else {
                scanFailureLogger("scan-batch-failed")
                return
            }
            reloadLoadedViewControllerAfterScan()
        } catch {
            scanFailureLogger("scan-batch-failed")
        }
    }

    func performIncrementalScan() { performScan() }
    func performInitialScan() { performScan() }

    // MARK: - Database Path

    func databasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LaunchPad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("launchpad.db").path
    }
}

// MARK: - System Service Implementations

/// 生产环境文件系统服务
struct SystemFileSystemService: FileSystemService {
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
    }

    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func bundleInfo(at bundleURL: URL) throws -> [String: any Sendable] {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ) as? [String: any Sendable] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return plist
    }

    func enumerateAppBundles(
        at url: URL, maxDepth: Int,
        options: FileManager.DirectoryEnumerationOptions
    ) throws -> [URL] {
        // TODO: GREEN - use FileManager.enumerator
        return []
    }
}

/// 生产环境图标提供者
struct SystemIconProvider: IconProviding {
    func icon(forPath path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    func modificationDate(forPath path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
#endif
