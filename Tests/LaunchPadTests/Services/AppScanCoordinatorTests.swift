import Foundation
import os
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@MainActor
@Suite("AppScanCoordinator 串行扫描")
struct AppScanCoordinatorTests {

    private enum TestFailure: Error, Sendable {
        case writerFailed
    }

    private final class RecordingScanner: AppScanning {
        struct State {
            var invocationCount = 0
            var invokedOnMainThread: [Bool] = []
        }

        let discoveryResult: AppDiscoveryResult
        private let state = OSAllocatedUnfairLock(initialState: State())

        init(discoveryResult: AppDiscoveryResult) {
            self.discoveryResult = discoveryResult
        }

        func scanDirectories(_ roots: [AppDiscoveryRoot]) -> AppDiscoveryResult {
            state.withLock { state in
                state.invocationCount += 1
                state.invokedOnMainThread.append(Thread.isMainThread)
            }
            return discoveryResult
        }

        func isExcluded(bundleId: String) -> Bool { false }

        func snapshot() -> State { state.withLock { $0 } }
    }

    private final class RecordingWriter: ScanBatchWriting {
        struct State {
            var invocationCount = 0
            var invokedOnMainThread: [Bool] = []
            var receivedApps: [[ScannedApp]] = []
            var receivedCapacities: [Int] = []
        }

        enum Behavior: Sendable {
            case result(ScanSyncResult)
            case fail
        }

        let behavior: Behavior
        private let state = OSAllocatedUnfairLock(initialState: State())

        init(behavior: Behavior) {
            self.behavior = behavior
        }

        func synchronizeInstalledApps(
            _ apps: [ScannedApp],
            initialPageCapacity: Int
        ) throws -> ScanSyncResult {
            state.withLock { state in
                state.invocationCount += 1
                state.invokedOnMainThread.append(Thread.isMainThread)
                state.receivedApps.append(apps)
                state.receivedCapacities.append(initialPageCapacity)
            }
            switch behavior {
            case .result(let result): return result
            case .fail: throw TestFailure.writerFailed
            }
        }

        func snapshot() -> State { state.withLock { $0 } }
    }

    private final class BlockingScanner: AppScanning {
        struct State {
            var invocationCount = 0
            var activeInvocationCount = 0
            var maximumConcurrentInvocations = 0
            var firstInvocationStarted = false
            var firstInvocationStartContinuation: CheckedContinuation<Void, Never>?
        }

        let discoveryResult: AppDiscoveryResult
        private let releaseGate = DispatchSemaphore(value: 0)
        private let state = OSAllocatedUnfairLock(initialState: State())

        init(discoveryResult: AppDiscoveryResult) {
            self.discoveryResult = discoveryResult
        }

        func scanDirectories(_ roots: [AppDiscoveryRoot]) -> AppDiscoveryResult {
            let isFirstInvocation = state.withLock { state -> Bool in
                state.invocationCount += 1
                state.activeInvocationCount += 1
                state.maximumConcurrentInvocations = max(
                    state.maximumConcurrentInvocations,
                    state.activeInvocationCount
                )
                guard state.invocationCount == 1 else { return false }
                state.firstInvocationStarted = true
                return true
            }

            if isFirstInvocation {
                let startContinuation = state.withLock { state in
                    defer { state.firstInvocationStartContinuation = nil }
                    return state.firstInvocationStartContinuation
                }
                startContinuation?.resume()
                releaseGate.wait()
            }

            state.withLock { state in
                state.activeInvocationCount -= 1
            }
            return discoveryResult
        }

        func isExcluded(bundleId: String) -> Bool { false }

        func waitForFirstInvocation() async {
            await withCheckedContinuation { continuation in
                let started = state.withLock { state in
                    if state.firstInvocationStarted { return true }
                    state.firstInvocationStartContinuation = continuation
                    return false
                }
                if started { continuation.resume() }
            }
        }

        func releaseFirstInvocation() {
            releaseGate.signal()
        }

        func maximumConcurrentInvocations() -> Int {
            state.withLock { $0.maximumConcurrentInvocations }
        }
    }

    private final class OutcomeCollector {
        private let expectedCount: Int
        private var outcomes: [ScanOutcome] = []
        private var continuation: CheckedContinuation<[ScanOutcome], Never>?

        init(expectedCount: Int) {
            self.expectedCount = expectedCount
        }

        func record(_ outcome: ScanOutcome) {
            outcomes.append(outcome)
            guard outcomes.count == expectedCount else { return }
            continuation?.resume(returning: outcomes)
            continuation = nil
        }

        func waitForOutcomes() async -> [ScanOutcome] {
            if outcomes.count == expectedCount { return outcomes }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    private func successfulResult() -> ScanSyncResult {
        var result = ScanSyncResult()
        result.recordSuccess()
        return result
    }

    private func failedResult() -> ScanSyncResult {
        var result = ScanSyncResult()
        result.recordFailure()
        return result
    }

    private func app() -> ScannedApp {
        ScannedApp(
            name: "Test App",
            bundleId: "com.launchpad.test",
            path: "/Applications/Test.app"
        )
    }

    @Test("完整发现与成功写入在 worker 执行，并在 MainActor 交付成功")
    func completeDiscoveryAndSuccessfulWrite() async {
        let scannedApp = app()
        let scanner = RecordingScanner(
            discoveryResult: AppDiscoveryResult(apps: [scannedApp])
        )
        let writer = RecordingWriter(behavior: .result(successfulResult()))
        let coordinator = AppScanCoordinator(scanner: scanner, writer: writer)

        let outcome = await withCheckedContinuation { continuation in
            coordinator.scan(
                roots: [AppDiscoveryRoot(url: URL(fileURLWithPath: "/Applications"), missingPolicy: .required)],
                pageCapacity: 28
            ) { outcome in
                #expect(Thread.isMainThread)
                continuation.resume(returning: outcome)
            }
        }

        #expect(outcome == .success)
        #expect(scanner.snapshot().invokedOnMainThread == [false])
        #expect(writer.snapshot().invokedOnMainThread == [false])
        #expect(writer.snapshot().receivedApps == [[scannedApp]])
        #expect(writer.snapshot().receivedCapacities == [28])
    }

    @Test("发现不完整时不写入，并在 MainActor 交付固定结果")
    func incompleteDiscoverySkipsWrite() async {
        let scanner = RecordingScanner(
            discoveryResult: AppDiscoveryResult(
                apps: [],
                failedRootPaths: ["/Applications"]
            )
        )
        let writer = RecordingWriter(behavior: .result(successfulResult()))
        let coordinator = AppScanCoordinator(scanner: scanner, writer: writer)

        let outcome = await withCheckedContinuation { continuation in
            coordinator.scan(roots: [], pageCapacity: 1) { outcome in
                #expect(Thread.isMainThread)
                continuation.resume(returning: outcome)
            }
        }

        #expect(outcome == .discoveryIncomplete)
        #expect(scanner.snapshot().invokedOnMainThread == [false])
        #expect(writer.snapshot().invocationCount == 0)
    }

    @Test("writer 抛错时在 MainActor 交付写入失败")
    func writerThrowProducesWriteFailure() async {
        let scanner = RecordingScanner(discoveryResult: AppDiscoveryResult(apps: [app()]))
        let writer = RecordingWriter(behavior: .fail)
        let coordinator = AppScanCoordinator(scanner: scanner, writer: writer)

        let outcome = await withCheckedContinuation { continuation in
            coordinator.scan(roots: [], pageCapacity: 1) { outcome in
                #expect(Thread.isMainThread)
                continuation.resume(returning: outcome)
            }
        }

        #expect(outcome == .writeFailed)
        #expect(scanner.snapshot().invokedOnMainThread == [false])
        #expect(writer.snapshot().invokedOnMainThread == [false])
    }

    @Test("writer 返回失败结果时在 MainActor 交付写入失败")
    func unsuccessfulWriteResultProducesWriteFailure() async {
        let scanner = RecordingScanner(discoveryResult: AppDiscoveryResult(apps: [app()]))
        let writer = RecordingWriter(behavior: .result(failedResult()))
        let coordinator = AppScanCoordinator(scanner: scanner, writer: writer)

        let outcome = await withCheckedContinuation { continuation in
            coordinator.scan(roots: [], pageCapacity: 1) { outcome in
                #expect(Thread.isMainThread)
                continuation.resume(returning: outcome)
            }
        }

        #expect(outcome == .writeFailed)
        #expect(scanner.snapshot().invokedOnMainThread == [false])
        #expect(writer.snapshot().invokedOnMainThread == [false])
    }

    @Test("连续请求在同一串行 worker 上依次执行")
    func consecutiveRequestsAreSerialized() async {
        let scanner = BlockingScanner(discoveryResult: AppDiscoveryResult(apps: [app()]))
        let writer = RecordingWriter(behavior: .result(successfulResult()))
        let coordinator = AppScanCoordinator(scanner: scanner, writer: writer)
        let outcomes = OutcomeCollector(expectedCount: 2)

        coordinator.scan(roots: [], pageCapacity: 1) { outcomes.record($0) }
        coordinator.scan(roots: [], pageCapacity: 1) { outcomes.record($0) }

        await scanner.waitForFirstInvocation()
        #expect(scanner.maximumConcurrentInvocations() == 1)
        scanner.releaseFirstInvocation()

        #expect(await outcomes.waitForOutcomes() == [.success, .success])
        #expect(scanner.maximumConcurrentInvocations() == 1)
        #expect(writer.snapshot().invocationCount == 2)
    }
}
