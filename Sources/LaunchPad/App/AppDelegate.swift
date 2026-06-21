import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols
import ServiceManagement

/// 应用入口 — 菜单栏图标、服务初始化、热键注册
/// Agent 应用模式（无 Dock 图标）
@preconcurrency @MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    private var storage: StorageManager!
    private var iconCache: IconCache!
    private var appScanner: AppScanner!
    private var searchEngine: SearchEngine!
    private var hotkeyManager: HotkeyManager!
    private var fileWatcher: FileWatcher?

    // MARK: - Controllers

    private var lifecycle: WindowLifecycle!
    private var windowController: LaunchPadWindowController!
    private var viewController: LaunchPadViewController!

    // MARK: - Menu Bar

    private var statusItem: NSStatusItem!

    // MARK: - Application Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 多实例防护：激活已有实例，退出当前
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if running.count > 1 {
            running.first?.activate()
            NSApp.terminate(nil)
            return
        }

        // Agent app: no Dock icon
        NSApp.setActivationPolicy(.accessory)

        setupServices()
        guard storage != nil else {
            NSLog("[AppDelegate] Fatal: could not initialize database, aborting launch")
            return
        }
        setupControllers()
        setupMenuBar()
        setupHotkey()
        performInitialScan()
        setupFileWatcher()
    }

    // MARK: - Service Setup

    private func setupServices() {
        // Database
        let dbPath = databasePath()
        do {
            storage = try StorageManager(dbPath: dbPath)
        } catch {
            // If DB is corrupted, delete and retry
            let strategy = ErrorRecovery.handleSQLiteCorruption(dbPath: dbPath)
            if case .deleteAndRescan = strategy {
                try? FileManager.default.removeItem(atPath: dbPath)
                storage = try? StorageManager(dbPath: dbPath)
            }
        }

        // Icon cache
        let iconProvider = SystemIconProvider()
        iconCache = IconCache(iconProvider: iconProvider, imageStore: storage)

        // Scanner
        let fileSystemService = SystemFileSystemService()
        appScanner = AppScanner(fileSystemService: fileSystemService)

        // Search
        searchEngine = SearchEngine()

        // Hotkey
        hotkeyManager = HotkeyManager()
    }

    private func setupControllers() {
        // Drag controller
        let dragController = DragController(itemWriter: storage)

        // Folder controller
        let folderController = FolderController(itemWriter: storage)

        // View controller
        viewController = LaunchPadViewController(
            storage: storage,
            iconCache: iconCache,
            searchEngine: searchEngine,
            dragController: dragController,
            folderController: folderController
        )

        // Lifecycle
        lifecycle = WindowLifecycle()

        // Window controller
        windowController = LaunchPadWindowController(
            lifecycle: lifecycle,
            viewController: viewController
        )
        // ESC 关闭窗口：ViewController.onClose → lifecycle.handleEscape()
        viewController.onClose = { [weak self] in
            self?.windowController.escape()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

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
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func statusItemClicked() {
        windowController.toggle()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            // 更新菜单状态
            if let menu = statusItem.menu,
               let item = menu.items.first(where: { $0.action == #selector(toggleLoginItem) }) {
                item.state = SMAppService.mainApp.status == .enabled ? .on : .off
            }
        } catch {
            NSLog("[AppDelegate] Failed to toggle login item: \(error)")
        }
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onToggle = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.windowController.toggle()
            }
        }

        let registered = hotkeyManager.registerGlobalHotkey(keyCode: 49, modifiers: .option) // Option+Space

        if !registered && hotkeyManager.hasConflict {
            // 快捷键被其他应用占用，提示用户
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Option+Space 快捷键已被占用"
                alert.informativeText = "另一个应用正在使用 Option+Space 快捷键。请关闭冲突应用或在 LaunchPad 设置中选择其他快捷键。"
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        hotkeyManager.onKeyDown = { @Sendable [weak self] event in
            guard let self else { return event }
            // 本地事件监视器在主线程运行，此处通过 nonisolated(unsafe) 访问 @MainActor 状态
            nonisolated(unsafe) let unsafeSelf = self
            guard unsafeSelf.lifecycle.state == .visible else { return event }

            let key: KeyboardNavigator.Key? = switch event.keyCode {
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
                _ = unsafeSelf.viewController.handleKeyEvent(key)
            } else if let chars = event.characters {
                _ = unsafeSelf.viewController.handleCharacterInput(chars)
            }
            return nil
        }
        hotkeyManager.registerLocalMonitor()
    }

    // MARK: - File System Monitoring

    private func setupFileWatcher() {
        let watcher = FileWatcher(debounceInterval: 2.0)
        let paths = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
        ]
        watcher.start(paths: paths) { [weak self] in
            self?.performIncrementalScan()
        }
        self.fileWatcher = watcher
    }

    /// 增量扫描（由 FileWatcher 触发）
    private func performIncrementalScan() {
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]
        do {
            let existingItems = try storage.fetchAllItems(parentId: nil)
            let scanned = appScanner.scanDirectories(directories)
            let pages = existingItems.filter { $0.type == .page }
                .sorted { $0.ordering < $1.ordering }
            let lastPageId = pages.last?.id

            appScanner.incrementalSync(
                scannedApps: scanned,
                existingItems: existingItems,
                lastPageId: lastPageId,
                writer: storage
            )
            // 刷新 UI
            DispatchQueue.main.async { [weak self] in
                self?.viewController.loadData()
            }
        } catch {
            NSLog("[AppDelegate] Incremental scan failed: \(error)")
        }
    }

    // MARK: - Initial Scan

    private func performInitialScan() {
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
        ]

        do {
            let existingItems = try storage.fetchAllItems(parentId: nil)

            if existingItems.isEmpty {
                // First launch
                let scanned = appScanner.scanDirectories(directories)
                appScanner.firstLaunchPaginate(
                    scannedApps: scanned,
                    maxPerPage: GridLayoutCalculator.calculate(screenWidth: NSScreen.main?.frame.width ?? 1440).itemsPerPage,
                    writer: storage
                )
            } else {
                // Incremental sync
                let scanned = appScanner.scanDirectories(directories)
                let pages = existingItems.filter { $0.type == .page }
                    .sorted { $0.ordering < $1.ordering }
                let lastPageId = pages.last?.id

                appScanner.incrementalSync(
                    scannedApps: scanned,
                    existingItems: existingItems,
                    lastPageId: lastPageId,
                    writer: storage
                )
            }
        } catch {
            NSLog("[AppDelegate] Scan failed: \(error)")
        }
    }

    // MARK: - Database Path

    private func databasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LaunchPad")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("launchpad.db").path
    }
}

// MARK: - System Service Implementations

/// 生产环境文件系统服务
private struct SystemFileSystemService: FileSystemService {
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

    func bundleInfo(at bundleURL: URL) -> [String: any Sendable]? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: any Sendable] else {
            return nil
        }
        return plist
    }
}

/// 生产环境图标提供者
private struct SystemIconProvider: IconProviding {
    func icon(forPath path: String) -> NSImage {
        NSWorkspace.shared.icon(forFile: path)
    }

    func modificationDate(forPath path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
#endif
