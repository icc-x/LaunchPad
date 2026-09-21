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

    /// 已安装服务（applicationDidFinishLaunching 后可用）；消费方必须 guard。
    var storage: (any DataStoring)?
    var layoutRepository: (any LayoutRepositoryProtocol)?
    var scanBatchWriter: (any ScanBatchWriting)? {
        didSet { scanCoordinator = nil }
    }
    var iconCache: IconCache?
    var appScanner: (any AppScanning)? {
        didSet { scanCoordinator = nil }
    }
    var hotkeyManager: HotkeyManager?
    var fileWatcher: FileWatcher?
    var appBootstrapper: AppBootstrapper?

    // MARK: - Controllers

    /// 已安装控制器；windowController 与 lifecycle 由 applicationDidFinishLaunching 建立。
    var lifecycle: WindowLifecycle?
    var windowController: LaunchPadWindowController?
    var viewController: LaunchPadViewController?

    // MARK: - Menu Bar

    var statusItem: (any StatusItemManaging)?

    // MARK: - Test Injection Points

    /// 数据库工厂（默认创建真实 StorageManager，测试可注入以触发 SQLite 损坏恢复分支）
    var storageFactory: AppBootstrapper.StorageFactory = {
        try StorageManager(dbPath: $0)
    }

    /// 数据库路径提供器（默认沿用生产路径创建逻辑，测试注入临时路径以隔离用户数据）
    lazy var databasePathProvider: () -> String = { [unowned self] in self.databasePath() }

    /// 数据库删除器（默认删除生产数据库文件；拒绝目录，避免误删整个文件夹）
    var databaseRemover: AppBootstrapper.DatabaseRemover = { path in
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return
        }
        try FileManager.default.removeItem(atPath: path)
    }

    /// 激活策略设置器（默认走 NSApp，测试注入避免无 NSApplication 实例时崩溃）
    var activationPolicySetter: (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }

    /// 非阻塞告警展示器（默认以 sheet 挂到主窗口；测试注入为同步记录并回调完成）。
    /// 用于热键失败等非致命提示——历史实现用 runModal 模态会话，会拦截窗口
    /// 的 ESC/分页/滚轮等全部交互，改为 sheet 后不再阻塞。
    var alertPresenter: (NSAlert, NSWindow, @escaping (NSApplication.ModalResponse) -> Void) -> Void = { alert, window, completion in
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    /// 热键注册失败状态（注册失败时记录，供窗口呼出时提示，避免启动即模态弹窗）
    private(set) var hotkeyRegistrationFailed = false
    /// 热键失败原因是否为"与其他应用冲突"（false 表示无输入监控权限）
    private(set) var hotkeyRegistrationConflict = false
    /// 无权限提示仅展示一次的持久化标记
    private static let hotkeyPermissionAlertKey = "launchpad.hotkeyPermissionAlertShown"
    /// 延迟展示进行中：避免 0.8s 窗口内重复 toggle 挂多个 sheet
    private var isHotkeyPermissionHintInFlight = false
    /// 无权限提示标记的持久化存储（默认 standard；测试注入隔离实例避免宿主状态突变）
    var hotkeyPermissionDefaults: UserDefaults = .standard

    /// 热键提示延迟执行器（默认 0.8s，测试可注入同步块以便确定性驱动）
    var hotkeyHintDelayRunner: (@escaping @MainActor @Sendable () -> Void) -> Void = { block in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: block)
    }

    /// 提示展示所依赖的可见窗口（默认取 windowController；测试可注入）
    var hotkeyPermissionHintWindowProvider: (() -> NSWindow?)?

    /// 启动期存储失败的非模态提示；完成后调用 completion（默认随后终止）。
    var storageFailurePresenter: (
        _ message: String,
        _ completion: @escaping @MainActor @Sendable () -> Void
    ) -> Void = { message, completion in
        let alert = NSAlert()
        alert.messageText = "LaunchPad 无法启动"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "退出")
        // 非模态：挂到独立浮动 panel 的 sheet，避免 runModal 阻塞主 run loop。
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "LaunchPad"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: panel) { _ in
            panel.orderOut(nil)
            completion()
        }
    }

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
    var corruptionHandler: AppBootstrapper.CorruptionHandler = {
        ErrorRecovery.handleSQLiteCorruption(dbPath: $0)
    }

    /// 主线程异步派发（默认 DispatchQueue.main.async，测试注入为同步执行以覆盖告警分支）
    var mainAsyncRunner: (@escaping @MainActor @Sendable () -> Void) -> Void = {
        DispatchQueue.main.async(execute: $0)
    }

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
    /// 测试观察扫描结果已完成 MainActor 回填的边界。
    var scanOutcomeObserver: (@MainActor @Sendable (ScanOutcome) -> Void)?
    private var scanCoordinator: AppScanCoordinator?
    private var isTerminating = false

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

        bootstrapServices()

    }


    private func finishLaunch() {
        setupControllers()
        setupMenuBar()
        setupHotkey()
        performInitialScan()
        setupFileWatcher()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        appBootstrapper = nil
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
        layoutRepository = LayoutRepository(
            reader: manager,
            mutator: manager,
            writer: manager
        )
        scanBatchWriter = manager
    }

    func bootstrapServices() {
        storage = nil
        layoutRepository = nil
        scanBatchWriter = nil
        let bootstrapper = AppBootstrapper(
            storageFactory: storageFactory,
            corruptionHandler: corruptionHandler,
            databaseRemover: databaseRemover
        )
        appBootstrapper = bootstrapper
        bootstrapper.bootstrap(databasePath: databasePathProvider()) { [weak self] result in
            self?.handleBootstrapResult(result)
        }
    }

    func handleBootstrapResult(
        _ result: Result<StorageManager, AppBootstrapError>
    ) {
        appBootstrapper = nil
        guard !isTerminating else { return }
        switch result {
        case .success(let manager):
            installServices(manager)
            finishLaunch()
        case .failure:
            NSLog("[AppDelegate] Fatal: could not initialize database, aborting launch")
            let message = "无法初始化本地数据库（可能被占用或权限不足）。应用将退出，请检查磁盘与权限后重试。"
            storageFailurePresenter(message) { [weak self] in
                self?.appTerminator()
            }
        }
    }

    func installServices(_ manager: StorageManager) {
        installStorage(manager)

        // Icon cache
        let iconProvider = SystemIconProvider()
        iconCache = IconCache(iconProvider: iconProvider, imageStore: manager)

        // Scanner
        let fileSystemService = SystemFileSystemService()
        appScanner = AppScanner(fileSystemService: fileSystemService)

        // Hotkey
        hotkeyManager = hotkeyManagerFactory()
    }

    func setupControllers() {
        guard let layoutRepository, let iconCache else { return }

        // Drag controller
        let dragController = DragController()

        // View controller
        let vc = LaunchPadViewController(
            layoutRepository: layoutRepository,
            iconCache: iconCache,
            dragController: dragController,
            applicationOpener: applicationOpener
        )
        viewController = vc

        // Lifecycle
        let lifecycle = WindowLifecycle()
        self.lifecycle = lifecycle
        vc.lifecycle = lifecycle

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
        guard let windowController else { return }
        windowController.toggle()
        maybeShowHotkeyPermissionHint()
    }

    /// 热键注册失败时，在窗口呼出后以非阻塞 sheet 提示一次（无权限提示仅首次）。
    internal func maybeShowHotkeyPermissionHint() {
        guard hotkeyRegistrationFailed else { return }
        let alreadyShown = hotkeyPermissionDefaults.bool(
            forKey: Self.hotkeyPermissionAlertKey
        )
        guard !alreadyShown else { return }
        // 0.8s 延迟窗口内重复 toggle 只允许一次调度，避免挂多个 sheet。
        guard !isHotkeyPermissionHintInFlight else { return }
        isHotkeyPermissionHintInFlight = true

        // 等待窗口显示动画完成后再挂 sheet，避免窗口未就绪。
        // 仅在真正展示成功后才写入 shown 标记，避免窗口未出现导致提示被永久吞掉。
        hotkeyHintDelayRunner { [weak self] in
            guard let self else { return }
            self.isHotkeyPermissionHintInFlight = false
            let window = self.hotkeyPermissionHintWindowProvider?()
                ?? self.windowController?.window
            guard let window, window.isVisible else { return }
            hotkeyPermissionDefaults.set(true, forKey: Self.hotkeyPermissionAlertKey)
            self.presentHotkeyFailureHint(on: window)
        }
    }

    /// 以非阻塞 sheet 展示热键失败提示，并处理按钮回调（打开系统设置）。无副作用，便于测试。
    internal func presentHotkeyFailureHint(on window: NSWindow) {
        let alert = makeHotkeyFailureAlert()
        alertPresenter(alert, window) { [weak self] response in
            guard let self,
                  !self.hotkeyRegistrationConflict,
                  response == .alertFirstButtonReturn,
                  let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
                return
            }
            self.workspaceURLOpener(url)
        }
    }

    /// 构造热键失败提示 alert（无副作用，便于测试）。冲突与无权限两种原因给出不同文案。
    internal func makeHotkeyFailureAlert() -> NSAlert {
        let alert = NSAlert()
        if hotkeyRegistrationConflict {
            alert.messageText = "Option+Space 快捷键已被占用"
            alert.informativeText = "另一个应用正在使用 Option+Space 快捷键。请关闭冲突应用或在 LaunchPad 设置中选择其他快捷键。"
            alert.addButton(withTitle: "OK")
        } else {
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "LaunchPad 需要 Input Monitoring（输入监控）权限才能响应 Option+Space 快捷键。\n\n请在「系统设置 → 隐私与安全性 → 输入监控」中启用 LaunchPad。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后设置")
        }
        return alert
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
        guard let hotkeyManager else { return }
        let runner = hotkeyToggleRunner
        hotkeyManager.onToggle = { @Sendable [weak self] in
            runner { [weak self] in self?.windowController?.toggle() }
        }

        let registered = hotkeyManager.registerGlobalHotkey(
            keyCode: UInt32(KeyboardKeyCode.space),
            modifiers: .option
        ) // Option+Space

        if !registered {
            // 记录失败状态，由窗口呼出时以非阻塞 sheet 提示一次。
            // 历史实现在此直接 runModal 弹模态 alert，会阻塞主线程并拦截
            // 窗口的 ESC/分页/滚轮等全部交互（启动时窗口尚未显示，阻塞尤其明显）。
            hotkeyRegistrationFailed = true
            hotkeyRegistrationConflict = hotkeyManager.hasConflict
        }

        hotkeyManager.onKeyDown = { @Sendable [weak self] event in
            guard let self else { return event }
            guard event.type == .keyDown else { return event }

            // 提取非 Sendable NSEvent 的数据，避免跨 actor 边界发送
            let keyCode = event.keyCode
            let characters = event.characters
            // 本地事件监视器在主线程运行，此处通过 MainActor.assumeIsolated 安全访问 @MainActor 状态
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let lifecycle = self.lifecycle,
                      lifecycle.state == .visible,
                      let viewController = self.viewController,
                      viewController.isViewLoaded else {
                    return false
                }

                let key = KeyboardKeyCode.navigationKey(for: keyCode)

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
        let viewport = LaunchPadViewController.gridViewportSize(
            forWindowContentSize: targetWindowContentSizeProvider()
        )
        let capacity = GridLayoutCalculator.calculate(viewportSize: viewport).itemsPerPage
        guard let appScanner, let scanBatchWriter else { return }

        let coordinator: AppScanCoordinator
        if let scanCoordinator {
            coordinator = scanCoordinator
        } else {
            let created = AppScanCoordinator(
                scanner: appScanner,
                writer: scanBatchWriter
            )
            scanCoordinator = created
            coordinator = created
        }

        coordinator.scan(
            roots: discoveryRoots,
            pageCapacity: capacity
        ) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success:
                self.reloadLoadedViewControllerAfterScan()
            case .discoveryIncomplete:
                self.scanFailureLogger("app-discovery-incomplete")
            case .writeFailed:
                self.scanFailureLogger("scan-batch-failed")
            }
            self.scanOutcomeObserver?(outcome)
        }
    }

    func performIncrementalScan() { performScan() }
    func performInitialScan() { performScan() }

    // MARK: - Database Path

    func databasePath() -> String {
        // 优先使用系统 Application Support 目录；不可用时回退到主目录下的确定路径。
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
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
        var enumerationError: (any Error)?
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: options,
            errorHandler: { _, error in
                enumerationError = error
                // 返回 false 中止枚举；静默截断会让调用方误判目录内容完整，
                // 进而在同步时把“本次没扫到”的已安装应用删掉。
                return false
            }
        ) else { return [] }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
            let depth = relativePath.split(separator: "/").count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard fileURL.pathExtension == "app" else { continue }
            results.append(fileURL)
        }
        if let enumerationError {
            throw enumerationError
        }
        return results
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
