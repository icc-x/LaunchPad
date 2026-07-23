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

@Suite("FileWatcher 生命周期与 FSEvents 边界")
struct FileWatcherLifecycleTests {

    @Test("真实 FSEvents 在 UUID 临时目录变更后触发 callback")
    @MainActor
    func realTemporaryDirectoryChangeTriggersCallback() async throws {
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

    @Test("生产 FSEvent backend 启动失败不调用 Stop 但完整释放")
    func systemBackendStartFailureSkipsStopAndReleasesEverything() {
        let fakeStream: FSEventStreamRef = unsafeBitCast(UInt(1), to: FSEventStreamRef.self)
        var stopCalls = 0
        var invalidateCalls = 0
        var releaseCalls = 0
        let functions = FSEventStreamFunctions(
            create: { _, _, _, _, _, _ in fakeStream },
            setDispatchQueue: { _, _ in },
            start: { _ in false },
            stop: { _ in stopCalls += 1 },
            invalidate: { _ in invalidateCalls += 1 },
            release: { _ in releaseCalls += 1 }
        )
        let stream = SystemFileEventStream(functions: functions)

        #expect(!stream.start(paths: ["/Applications"]) {})
        #expect(stopCalls == 0)
        #expect(invalidateCalls == 1)
        #expect(releaseCalls == 1)
    }

    @Test("生产 FSEvent backend create 失败不安装或释放不存在的 stream")
    func systemBackendCreateFailureDoesNotStartOrRelease() {
        var setQueueCalls = 0
        var startCalls = 0
        var stopCalls = 0
        var invalidateCalls = 0
        var releaseCalls = 0
        let functions = FSEventStreamFunctions(
            create: { _, _, _, _, _, _ in nil },
            setDispatchQueue: { _, _ in setQueueCalls += 1 },
            start: { _ in startCalls += 1; return true },
            stop: { _ in stopCalls += 1 },
            invalidate: { _ in invalidateCalls += 1 },
            release: { _ in releaseCalls += 1 }
        )
        let stream = SystemFileEventStream(functions: functions)

        #expect(!stream.start(paths: ["/Applications"]) {})
        stream.stop()

        #expect(setQueueCalls == 0)
        #expect(startCalls == 0)
        #expect(stopCalls == 0)
        #expect(invalidateCalls == 0)
        #expect(releaseCalls == 0)
    }

    @Test("生产 FSEvent backend 成功启动、停止和重复停止精确平衡资源")
    func systemBackendActiveAndRepeatedStopBalanceResources() {
        let fakeStream: FSEventStreamRef = unsafeBitCast(UInt(1), to: FSEventStreamRef.self)
        var setQueueCalls = 0
        var startCalls = 0
        var stopCalls = 0
        var invalidateCalls = 0
        var releaseCalls = 0
        let functions = FSEventStreamFunctions(
            create: { _, _, _, _, _, _ in fakeStream },
            setDispatchQueue: { _, _ in setQueueCalls += 1 },
            start: { _ in startCalls += 1; return true },
            stop: { _ in stopCalls += 1 },
            invalidate: { _ in invalidateCalls += 1 },
            release: { _ in releaseCalls += 1 }
        )
        let stream = SystemFileEventStream(functions: functions)

        #expect(stream.start(paths: ["/Applications"]) {})
        stream.stop()
        stream.stop()

        #expect(setQueueCalls == 1)
        #expect(startCalls == 1)
        #expect(stopCalls == 1)
        #expect(invalidateCalls == 1)
        #expect(releaseCalls == 1)
    }

    @Test("生产 FSEvent backend 析构释放活动 stream 一次")
    func systemBackendDeinitBalancesActiveResourcesOnce() {
        let fakeStream: FSEventStreamRef = unsafeBitCast(UInt(1), to: FSEventStreamRef.self)
        var stopCalls = 0
        var invalidateCalls = 0
        var releaseCalls = 0
        let functions = FSEventStreamFunctions(
            create: { _, _, _, _, _, _ in fakeStream },
            setDispatchQueue: { _, _ in },
            start: { _ in true },
            stop: { _ in stopCalls += 1 },
            invalidate: { _ in invalidateCalls += 1 },
            release: { _ in releaseCalls += 1 }
        )
        var stream: SystemFileEventStream? = SystemFileEventStream(functions: functions)

        #expect(stream?.start(paths: ["/Applications"]) {} == true)
        stream = nil

        #expect(stopCalls == 1)
        #expect(invalidateCalls == 1)
        #expect(releaseCalls == 1)
    }

    @Test("FSEvent callback 忽略 nil context，保留 context 只调用一次")
    func systemBackendCallbackContextIsSafeAndBalanced() {
        let fakeStream: FSEventStreamRef = unsafeBitCast(UInt(1), to: FSEventStreamRef.self)
        final class EventRecorder: @unchecked Sendable {
            var count = 0
        }
        var capturedContext: UnsafeMutableRawPointer?
        var releaseCalls = 0
        let recorder = EventRecorder()
        let functions = FSEventStreamFunctions(
            create: { callback, context, _, _, _, _ in
                capturedContext = context.pointee.info
                return fakeStream
            },
            setDispatchQueue: { _, _ in },
            start: { _ in true },
            stop: { _ in },
            invalidate: { _ in },
            release: { _ in releaseCalls += 1 }
        )
        let stream = SystemFileEventStream(functions: functions)

        #expect(stream.start(paths: ["/Applications"]) { recorder.count += 1 })
        SystemFileEventStream.handleEvents(context: nil)
        #expect(recorder.count == 0)
        SystemFileEventStream.handleEvents(context: capturedContext)
        #expect(recorder.count == 1)

        stream.stop()
        stream.stop()
        #expect(releaseCalls == 1)
    }

    @Test("CallbackBox 在全部创建和释放分支恰好释放闭包捕获")
    func callbackBoxReleasesCapturedLifetimeProbeOnEveryExitPath() {
        final class LifetimeProbe: @unchecked Sendable {}
        let fakeStream: FSEventStreamRef = unsafeBitCast(UInt(1), to: FSEventStreamRef.self)

        weak var createNilProbe: LifetimeProbe?
        do {
            let probe = LifetimeProbe()
            createNilProbe = probe
            let stream = SystemFileEventStream(functions: FSEventStreamFunctions(
                create: { _, _, _, _, _, _ in nil },
                setDispatchQueue: { _, _ in }, start: { _ in true },
                stop: { _ in }, invalidate: { _ in }, release: { _ in }
            ))
            #expect(!stream.start(paths: ["/Applications"]) { _ = probe })
        }
        #expect(createNilProbe == nil)

        weak var startFailureProbe: LifetimeProbe?
        do {
            let probe = LifetimeProbe()
            startFailureProbe = probe
            let stream = SystemFileEventStream(functions: FSEventStreamFunctions(
                create: { _, _, _, _, _, _ in fakeStream },
                setDispatchQueue: { _, _ in }, start: { _ in false },
                stop: { _ in }, invalidate: { _ in }, release: { _ in }
            ))
            #expect(!stream.start(paths: ["/Applications"]) { _ = probe })
        }
        #expect(startFailureProbe == nil)

        weak var stopProbe: LifetimeProbe?
        do {
            let probe = LifetimeProbe()
            stopProbe = probe
            let stream = SystemFileEventStream(functions: FSEventStreamFunctions(
                create: { _, _, _, _, _, _ in fakeStream },
                setDispatchQueue: { _, _ in }, start: { _ in true },
                stop: { _ in }, invalidate: { _ in }, release: { _ in }
            ))
            #expect(stream.start(paths: ["/Applications"]) { _ = probe })
            stream.stop()
        }
        #expect(stopProbe == nil)

        weak var deinitProbe: LifetimeProbe?
        do {
            let probe = LifetimeProbe()
            deinitProbe = probe
            var stream: SystemFileEventStream? = SystemFileEventStream(functions: FSEventStreamFunctions(
                create: { _, _, _, _, _, _ in fakeStream },
                setDispatchQueue: { _, _ in }, start: { _ in true },
                stop: { _ in }, invalidate: { _ in }, release: { _ in }
            ))
            #expect(stream?.start(paths: ["/Applications"]) { _ = probe } == true)
            stream = nil
        }
        #expect(deinitProbe == nil)
    }

    @Test("空路径不启动；重复启动先停止旧 backend")
    @MainActor
    func startEmptyAndRestartBalanceBackend() {
        let backend = MockFileEventStream()
        let watcher = FileWatcher(backend: backend, scheduler: MockScheduler())

        #expect(!watcher.start(paths: []) {})
        #expect(backend.startedPaths.isEmpty)
        #expect(backend.stopCallCount == 0)

        #expect(watcher.start(paths: ["/Applications"]) {})
        #expect(watcher.start(paths: ["/System/Applications"]) {})
        #expect(backend.startedPaths == [["/Applications"], ["/System/Applications"]])
        #expect(backend.stopCallCount == 1)
    }

    @Test("stop 取消 debounce、停止 backend 并丢弃回调")
    @MainActor
    func stopDropsPendingCallback() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(backend: backend, scheduler: scheduler)
        var changes = 0

        #expect(watcher.start(paths: ["/Applications"]) { changes += 1 })
        backend.emit()
        await Task.yield()
        watcher.stop()
        scheduler.advance(by: 3)

        #expect(changes == 0)
        #expect(scheduler.scheduledActions.isEmpty)
        #expect(backend.stopCallCount == 1)
    }

    @Test("活动 watcher 析构只停止 backend 一次")
    @MainActor
    func deinitStopsBackendExactlyOnce() {
        let backend = MockFileEventStream()
        var watcher: FileWatcher? = FileWatcher(backend: backend, scheduler: MockScheduler())

        #expect(watcher?.start(paths: ["/Applications"]) {} == true)
        watcher = nil

        #expect(backend.stopCallCount == 1)
    }

    @Test("文件事件 burst 只触发最后一次防抖回调")
    @MainActor
    func eventBurstFiresLatestOnce() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(backend: backend, scheduler: scheduler)
        var changes = 0

        #expect(watcher.start(paths: ["/Applications"]) { changes += 1 })
        backend.emit()
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 1.99)
        #expect(changes == 0)
        scheduler.advance(by: 0.01)
        #expect(changes == 1)
    }

    @Test("旧 backend emit 在 restart 后不触发新 generation")
    @MainActor
    func staleBackendEventCannotTriggerReplacementGeneration() async {
        let backend = MockFileEventStream()
        let scheduler = MockScheduler()
        let watcher = FileWatcher(backend: backend, scheduler: scheduler)
        var oldChanges = 0
        var newChanges = 0

        #expect(watcher.start(paths: ["/Applications"]) { oldChanges += 1 })
        backend.emit()
        #expect(watcher.start(paths: ["/System/Applications"]) { newChanges += 1 })
        await Task.yield()
        scheduler.advance(by: 2)

        #expect(oldChanges == 0)
        #expect(newChanges == 0)
        backend.emit()
        await Task.yield()
        scheduler.advance(by: 2)
        #expect(newChanges == 1)
    }
}
#endif
