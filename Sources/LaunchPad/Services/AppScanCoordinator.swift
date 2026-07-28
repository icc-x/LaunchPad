import Foundation
import LaunchPadProtocols

enum ScanOutcome: Sendable, Equatable {
    case success
    case discoveryIncomplete
    case writeFailed
}

/// 在单一后台队列中串行发现应用并同步持久化扫描结果。
final class AppScanCoordinator: Sendable {
    private let queue = DispatchQueue(
        label: "com.launchpad.scan",
        qos: .userInitiated
    )
    private let scanner: any AppScanning
    private let writer: any ScanBatchWriting

    init(scanner: any AppScanning, writer: any ScanBatchWriting) {
        self.scanner = scanner
        self.writer = writer
    }

    func scan(
        roots: [AppDiscoveryRoot],
        pageCapacity: Int,
        completion: @escaping @MainActor @Sendable (ScanOutcome) -> Void
    ) {
        queue.async { [scanner, writer] in
            let discovery = scanner.scanDirectories(roots)
            let outcome: ScanOutcome

            guard discovery.isComplete else {
                outcome = .discoveryIncomplete
                Task { @MainActor in completion(outcome) }
                return
            }

            do {
                let result = try writer.synchronizeInstalledApps(
                    discovery.apps,
                    initialPageCapacity: pageCapacity
                )
                outcome = result.isSuccessful ? .success : .writeFailed
            } catch {
                outcome = .writeFailed
            }

            Task { @MainActor in completion(outcome) }
        }
    }
}
