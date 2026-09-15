import Foundation
import LaunchPadProtocols
import os

enum ScanOutcome: Sendable, Equatable {
    case success
    case discoveryIncomplete
    case writeFailed
}

/// 在单一后台队列中串行发现应用并同步持久化扫描结果。
/// 扫描进行中到达的请求会合并为一次后续扫描，避免 FSEvent 风暴时队列线性堆积。
final class AppScanCoordinator: Sendable {
    private struct PendingRequest: Sendable {
        var roots: [AppDiscoveryRoot]
        var pageCapacity: Int
        var completions: [@MainActor @Sendable (ScanOutcome) -> Void]
    }

    private struct State: Sendable {
        var isRunning = false
        var pending: PendingRequest?
    }

    private let queue = DispatchQueue(
        label: "com.launchpad.scan",
        qos: .userInitiated
    )
    private let scanner: any AppScanning
    private let writer: any ScanBatchWriting
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(scanner: any AppScanning, writer: any ScanBatchWriting) {
        self.scanner = scanner
        self.writer = writer
    }

    func scan(
        roots: [AppDiscoveryRoot],
        pageCapacity: Int,
        completion: @escaping @MainActor @Sendable (ScanOutcome) -> Void
    ) {
        let shouldStartImmediately = state.withLock { state -> Bool in
            if state.isRunning {
                if state.pending == nil {
                    state.pending = PendingRequest(
                        roots: roots,
                        pageCapacity: pageCapacity,
                        completions: [completion]
                    )
                } else {
                    // 已有合并槽：保留最新参数，累积全部 completion
                    state.pending?.roots = roots
                    state.pending?.pageCapacity = pageCapacity
                    state.pending?.completions.append(completion)
                }
                return false
            }
            state.isRunning = true
            return true
        }

        guard shouldStartImmediately else { return }
        queue.async { [scanner, writer] in
            self.performScan(
                scanner: scanner,
                writer: writer,
                roots: roots,
                pageCapacity: pageCapacity,
                completions: [completion]
            )
        }
    }

    private func performScan(
        scanner: any AppScanning,
        writer: any ScanBatchWriting,
        roots: [AppDiscoveryRoot],
        pageCapacity: Int,
        completions: [@MainActor @Sendable (ScanOutcome) -> Void]
    ) {
        let discovery = scanner.scanDirectories(roots)
        let outcome: ScanOutcome

        if !discovery.isComplete {
            outcome = .discoveryIncomplete
        } else {
            do {
                let result = try writer.synchronizeInstalledApps(
                    discovery.apps,
                    initialPageCapacity: pageCapacity
                )
                outcome = result.isSuccessful ? .success : .writeFailed
            } catch {
                outcome = .writeFailed
            }
        }

        Task { @MainActor in
            for completion in completions {
                completion(outcome)
            }
        }

        let next = state.withLock { state -> PendingRequest? in
            guard let pending = state.pending else {
                state.isRunning = false
                return nil
            }
            state.pending = nil
            return pending
        }

        if let next {
            queue.async {
                self.performScan(
                    scanner: scanner,
                    writer: writer,
                    roots: next.roots,
                    pageCapacity: next.pageCapacity,
                    completions: next.completions
                )
            }
        }
    }
}
