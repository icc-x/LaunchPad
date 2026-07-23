import Foundation
import LaunchPadProtocols

struct ScanSyncResult: Sendable, Equatable {
    private(set) var attemptedWriteCount = 0
    private(set) var successfulWriteCount = 0
    private(set) var failedWriteCount = 0

    var isSuccessful: Bool { failedWriteCount == 0 }

    mutating func recordSuccess() {
        attemptedWriteCount += 1
        successfulWriteCount += 1
    }

    mutating func recordFailure() {
        attemptedWriteCount += 1
        failedWriteCount += 1
    }
}

struct ScanBatchWriteFailure: Error {
    let result: ScanSyncResult
    let primaryError: any Error
}

enum ScanBatchError: Error, Equatable {
    case invalidPageCapacity
    case missingPage
}

protocol ScanBatchWriting: Sendable {
    func synchronizeInstalledApps(
        _ apps: [ScannedApp],
        initialPageCapacity: Int
    ) throws -> ScanSyncResult
}
