import Foundation
#if canImport(AppKit)
import AppKit

/// 文件系统监控器 — 使用 FSEvents API 监控目录变化
/// 提供防抖机制，避免批量安装/卸载时频繁触发
public final class FileWatcher: @unchecked Sendable {

    private var stream: FSEventStreamRef?
    private var retainedSelfPtr: UnsafeMutableRawPointer?
    private let debounceInterval: TimeInterval
    /// 测试注入：非 nil 时用它替代 FSEventStreamCreate，返回 nil 模拟创建失败（正常流程不可达的防御分支）
    private let streamCreationOverride: (() -> FSEventStreamRef?)?
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.launchpad.filewatcher", qos: .utility)
    private let lock = NSLock()

    /// - Parameters:
    ///   - debounceInterval: 防抖间隔，默认 2.0s（避免批量操作频繁触发）
    ///   - streamCreationOverride: 测试注入，返回 nil 模拟 FSEventStreamCreate 失败
    public init(debounceInterval: TimeInterval = 2.0,
                streamCreationOverride: (() -> FSEventStreamRef?)? = nil) {
        self.debounceInterval = debounceInterval
        self.streamCreationOverride = streamCreationOverride
    }

    /// 开始监控指定目录
    /// - Parameters:
    ///   - paths: 要监控的目录路径列表
    ///   - onChange: 变化回调（防抖后触发，保证在主线程调用）
    public func start(paths: [String], onChange: @escaping @Sendable @MainActor () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard paths.isEmpty == false else { return }

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.handleEvents(numEvents: numEvents)
        }

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: selfPtr,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

        if let override = streamCreationOverride {
            stream = override()
        } else {
            stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                1.0, // latency: 1s 内的事件合并
                flags
            )
        }

        guard let stream = stream else {
            _ = Unmanaged<FileWatcher>.fromOpaque(selfPtr).takeRetainedValue()
            return
        }

        // 保存 onChange 回调和 retained 引用
        self.onChange = onChange
        self.retainedSelfPtr = selfPtr

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    /// 停止监控
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        // 释放 start() 中 passRetained 的引用，平衡引用计数
        if let ptr = retainedSelfPtr {
            Unmanaged<FileWatcher>.fromOpaque(ptr).release()
            retainedSelfPtr = nil
        }

        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        onChange = nil
    }

    // MARK: - Private

    private var onChange: (@Sendable @MainActor () -> Void)?

    private func handleEvents(numEvents: Int) {
        lock.lock()
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let onChange = self.onChange else { return }
            Task { @MainActor in
                onChange()
            }
        }
        debounceWorkItem = workItem
        lock.unlock()

        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    deinit {
        stop()
    }
}
#endif
