import Foundation
import Testing
@testable import LaunchPad

#if canImport(AppKit)
import AppKit

private enum WatcherTimeout: Error { case elapsed }

private func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await ContinuousClock().sleep(for: duration)
            throw WatcherTimeout.elapsed
        }
        guard let result = try await group.next() else {
            throw WatcherTimeout.elapsed
        }
        group.cancelAll()
        return result
    }
}

@MainActor
@Suite("FileWatcher")
struct FileWatcherTests {

    @Test("初始化不启动 backend")
    func init_doesNotCrash() {
        let backend = MockFileEventStream()

        _ = makeWatcher(backend: backend)

        #expect(backend.startedPaths.isEmpty)
        #expect(backend.stopCallCount == 0)
    }

    @Test("自定义 debounce interval 精确生效")
    func init_customDebounceInterval() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(
            debounceInterval: 5,
            backend: backend,
            scheduler: scheduler
        )
        var changes = 0
        #expect(watcher.start(paths: ["/Applications"]) { changes += 1 })

        backend.emit()
        await Task.yield()
        scheduler.advance(by: 4.99)
        #expect(changes == 0)
        scheduler.advance(by: 0.01)

        #expect(changes == 1)
    }

    @Test("未启动时 stop 不停止 backend")
    func stop_withoutStart_doesNotCrash() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)

        watcher.stop()

        #expect(backend.stopCallCount == 0)
    }

    @Test("空路径不启动 backend")
    func start_emptyPaths_doesNotCrash() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)

        #expect(!watcher.start(paths: []) {})
        #expect(backend.startedPaths.isEmpty)
    }

    @Test("启动后重复 stop 只停止 backend 一次")
    func start_thenStop_releasesProperly() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)

        #expect(watcher.start(paths: ["/Applications"]) {})
        watcher.stop()
        watcher.stop()

        #expect(backend.stopCallCount == 1)
    }

    @Test("活动 watcher 析构停止 backend 一次")
    func deinit_afterStart_doesNotCrash() {
        let backend = MockFileEventStream()
        var watcher: FileWatcher? = makeWatcher(backend: backend)
        #expect(watcher?.start(paths: ["/Applications"]) {} == true)

        watcher = nil

        #expect(backend.stopCallCount == 1)
    }

    @Test("多个路径原样交给 backend")
    func start_withMultiplePaths_doesNotCrash() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)
        let paths = ["/Applications", "/System/Applications"]

        #expect(watcher.start(paths: paths) {})
        #expect(backend.startedPaths == [paths])
    }

    @Test("stop 后可再次启动且旧 backend 精确停止")
    func start_stopThenStartAgain_doesNotCrash() {
        let backend = MockFileEventStream()
        let watcher = makeWatcher(backend: backend)

        #expect(watcher.start(paths: ["/Applications"]) {})
        watcher.stop()
        #expect(watcher.start(paths: ["/System/Applications"]) {})

        #expect(backend.stopCallCount == 1)
        #expect(backend.startedPaths == [
            ["/Applications"], ["/System/Applications"],
        ])
    }

    @Test("零 debounce interval 在 scheduler 推进时触发")
    func init_zeroDebounceInterval_doesNotCrash() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(
            debounceInterval: 0,
            backend: backend,
            scheduler: scheduler
        )
        var changes = 0

        #expect(watcher.start(paths: ["/Applications"]) { changes += 1 })
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 0)

        #expect(changes == 1)
    }

    @Test("未启动 watcher 析构不停止 backend")
    func deinit_withoutStart_isSafe() {
        let backend = MockFileEventStream()
        var watcher: FileWatcher? = makeWatcher(backend: backend)

        #expect(watcher != nil)
        watcher = nil

        #expect(backend.stopCallCount == 0)
    }

    @Test("真实 FSEvents 在 UUID 临时目录变更后触发 callback")
    func start_realFileChange_triggersOnChange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchPadWatcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = AsyncStream<Void>.makeStream()
        let watcher = FileWatcher(debounceInterval: 0.05)
        #expect(watcher.start(paths: [directory.path]) {
            events.continuation.yield()
        })
        defer {
            watcher.stop()
            events.continuation.finish()
        }

        try Data("event".utf8).write(
            to: directory.appendingPathComponent("probe.txt"),
            options: .atomic
        )
        let received = try await withTimeout(.seconds(10)) {
            for await _ in events.stream { return true }
            return false
        }
        #expect(received)
    }

    @Test("backend 启动失败不保留活动所有权")
    func start_streamCreationFails_doesNotCrash() {
        let backend = MockFileEventStream()
        backend.startResult = false
        let watcher = makeWatcher(backend: backend)

        #expect(!watcher.start(paths: ["/Applications"]) {})
        watcher.stop()

        #expect(backend.startedPaths == [["/Applications"]])
        #expect(backend.stopCallCount == 0)
    }

    @Test("backend 启动失败后重复 stop 安全")
    func start_streamCreationFails_thenStop_isSafe() {
        let backend = MockFileEventStream()
        backend.startResult = false
        let watcher = makeWatcher(backend: backend)

        #expect(!watcher.start(paths: ["/Applications"]) {})
        watcher.stop()
        watcher.stop()

        #expect(backend.stopCallCount == 0)
    }

    @Test("停止后迟到 backend callback 被丢弃")
    func handleEvents_clientCallBackInfoNil_returnsEarly() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(
            debounceInterval: 0,
            backend: backend,
            scheduler: scheduler
        )
        var changes = 0

        #expect(watcher.start(paths: ["/Applications"]) { changes += 1 })
        watcher.stop()
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 0)

        #expect(changes == 0)
    }

    private func makeWatcher(
        debounceInterval: TimeInterval = 2,
        backend: MockFileEventStream = MockFileEventStream()
    ) -> FileWatcher {
        FileWatcher(
            debounceInterval: debounceInterval,
            backend: backend,
            scheduler: MockScheduler()
        )
    }
}
#endif
