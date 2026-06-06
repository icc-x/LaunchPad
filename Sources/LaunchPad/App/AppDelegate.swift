import Foundation
#if canImport(AppKit)
import AppKit
import LaunchPadProtocols

/// 应用入口 — 菜单栏图标、服务初始化、热键注册
/// Agent 应用模式（无 Dock 图标）
@preconcurrency @MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Services

    nonisolated(unsafe) private var storage: StorageManager!
    nonisolated(unsafe) private var iconCache: IconCache!
    nonisolated(unsafe) private var appScanner: AppScanner!
    nonisolated(unsafe) private var searchEngine: SearchEngine!
    nonisolated(unsafe) private var hotkeyManager: HotkeyManager!

    // MARK: - Controllers

    nonisolated(unsafe) private var lifecycle: WindowLifecycle!
    nonisolated(unsafe) private var windowController: LaunchPadWindowController!
    nonisolated(unsafe) private var viewController: LaunchPadViewController!

    // MARK: - Menu Bar

    nonisolated(unsafe) private var statusItem: NSStatusItem!

    // MARK: - Application Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon
        NSApp.setActivationPolicy(.accessory)

        setupServices()
        setupControllers()
        setupMenuBar()
        setupHotkey()
        performInitialScan()
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
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func statusItemClicked() {
        windowController.toggle()
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager.onToggle = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.windowController.toggle()
            }
        }

        hotkeyManager.registerGlobalHotkey(keyCode: 49, modifiers: .option) // Option+Space

        hotkeyManager.onKeyDown = { @Sendable [weak self] event in
            nonisolated(unsafe) let unsafeEvent = event
            guard let self else { return unsafeEvent }
            if Thread.isMainThread {
                return self.handleLocalKeyEvent(unsafeEvent)
            } else {
                nonisolated(unsafe) var result: NSEvent? = unsafeEvent
                DispatchQueue.main.sync {
                    result = self.handleLocalKeyEvent(unsafeEvent)
                }
                return result
            }
        }
        hotkeyManager.registerLocalMonitor()
    }

    @preconcurrency
    nonisolated private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        nonisolated(unsafe) let e = event
        nonisolated(unsafe) var result: NSEvent? = e
        MainActor.assumeIsolated { [self] in
            guard lifecycle.state == .visible else { return }

            if e.keyCode == 53 { // ESC
                let action = viewController.handleKeyEvent(.escape)
                if case .closeWindow = action {
                    windowController.escape()
                    result = nil
                    return
                }
                result = nil
                return
            }

            if e.keyCode == 36 { _ = viewController.handleKeyEvent(.enter); result = nil; return }
            if e.keyCode == 126 { _ = viewController.handleKeyEvent(.upArrow); result = nil; return }
            if e.keyCode == 125 { _ = viewController.handleKeyEvent(.downArrow); result = nil; return }
            if e.keyCode == 123 { _ = viewController.handleKeyEvent(.leftArrow); result = nil; return }
            if e.keyCode == 124 { _ = viewController.handleKeyEvent(.rightArrow); result = nil; return }
            if e.keyCode == 48 { _ = viewController.handleKeyEvent(.tab); result = nil; return }
            if e.keyCode == 51 { _ = viewController.handleKeyEvent(.delete); result = nil; return }

            if let chars = e.characters {
                _ = viewController.handleCharacterInput(chars)
                result = nil
                return
            }
        }
        return result
    }

    // MARK: - Initial Scan

    private func performInitialScan() {
        let directories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications"),
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
