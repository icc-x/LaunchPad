import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - 数据读取协议

/// 只读操作 — SearchEngine / AppScanner 查询使用
public protocol ItemReading: Sendable {
    func fetchAllItems(parentId: Int64?) throws -> [PageItem]
}

// MARK: - 数据写入协议

/// 写操作 — AppScanner 同步、DragController 重排使用
public protocol ItemWriting: Sendable {
    func insertItem(_ item: PageItem) throws -> Int64
    func updateItem(_ item: PageItem) throws
    func deleteItem(id: Int64) throws
    func reorderItems(parentId: Int64, orderedIds: [Int64]) throws
}

/// Applies one stable layout mutation with the current page capacity.
public protocol LayoutMutating: Sendable {
    /// Applies the requested mutation using the supplied page capacity.
    func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws
}

// MARK: - 图标存储协议

/// IconCache 专用 — 磁盘层读写
public protocol ImageStoring: Sendable {
    func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws
    func fetchImage(itemId: Int64) throws -> (Data, Data)?
}

// MARK: - 组合存储协议

/// StorageManager 同时实现三个子协议
public protocol DataStoring: ItemReading, ItemWriting, ImageStoring {}

// MARK: - 应用扫描协议

/// 描述一个应用发现根目录及其缺失时的权威性策略。
public struct AppDiscoveryRoot: Sendable, Equatable {
    public enum MissingPolicy: Sendable, Equatable {
        case required
        case optional
    }

    public let url: URL
    public let missingPolicy: MissingPolicy

    public init(url: URL, missingPolicy: MissingPolicy) {
        self.url = url
        self.missingPolicy = missingPolicy
    }
}

/// 测试时可注入 mock 目录内容
public protocol AppScanning: Sendable {
    func scanDirectories(_ roots: [AppDiscoveryRoot]) -> AppDiscoveryResult
    func isExcluded(bundleId: String) -> Bool
}

/// 完整描述一次应用发现结果；任何读取失败都禁止 destructive sync。
public struct AppDiscoveryResult: Sendable, Equatable {
    public let apps: [ScannedApp]
    public let failedRootPaths: [String]
    public let failedBundlePaths: [String]

    public init(
        apps: [ScannedApp],
        failedRootPaths: [String] = [],
        failedBundlePaths: [String] = []
    ) {
        self.apps = apps
        self.failedRootPaths = failedRootPaths
        self.failedBundlePaths = failedBundlePaths
    }

    public var isComplete: Bool {
        failedRootPaths.isEmpty && failedBundlePaths.isEmpty
    }
}

/// AppScanner 返回的中间结构
public struct ScannedApp: Sendable, Equatable {
    public let name: String
    public let bundleId: String
    public let path: String

    public init(name: String, bundleId: String, path: String) {
        self.name = name
        self.bundleId = bundleId
        self.path = path
    }
}

// MARK: - 图标提供协议

/// 测试时可返回预设图标
public protocol IconProviding: Sendable {
    #if canImport(AppKit)
    func icon(forPath path: String) -> NSImage
    #endif
    func modificationDate(forPath path: String) -> Date?
}

// MARK: - 文件系统协议

/// 测试时可使用内存文件系统
public protocol FileSystemService: Sendable {
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func fileExists(at url: URL) -> Bool
    func bundleInfo(at bundleURL: URL) throws -> [String: any Sendable]
}

// MARK: - 图标缓存协议

/// 图标缓存抽象 — AppGridCollectionView 不应直接依赖具体 IconCache 类
public protocol IconCaching: Sendable {
    #if canImport(AppKit)
    func icon(forItemId itemId: Int64, path: String) -> NSImage
    #endif
}

/// 测试时可模拟按键事件
@MainActor
public protocol HotkeyManaging: Sendable {
    var onToggle: (@Sendable () -> Void)? { get set }
    func registerGlobalHotkey(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) -> Bool
    func unregisterGlobalHotkey()
}

// MARK: - 调度器协议

/// 测试时可精确控制时间，避免 flaky test
@MainActor
public protocol Scheduler: Sendable {
    func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    )
    func cancelPending()
}
