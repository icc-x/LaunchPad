import Foundation

enum AppBootstrapError: Error, Sendable, Equatable {
    case storageUnavailable
}

/// 在串行后台队列完成数据库创建与损坏恢复，并在 MainActor 交付结果。
final class AppBootstrapper: Sendable {
    typealias StorageFactory = @Sendable (String) throws -> StorageManager
    typealias CorruptionHandler = @Sendable (String) -> ErrorRecovery.ErrorStrategy
    typealias DatabaseRemover = @Sendable (String) throws -> Void
    typealias Completion = @MainActor @Sendable (
        Result<StorageManager, AppBootstrapError>
    ) -> Void

    private let queue = DispatchQueue(
        label: "com.launchpad.bootstrap",
        qos: .userInitiated
    )
    private let storageFactory: StorageFactory
    private let corruptionHandler: CorruptionHandler
    private let databaseRemover: DatabaseRemover

    init(
        storageFactory: @escaping StorageFactory,
        corruptionHandler: @escaping CorruptionHandler,
        databaseRemover: @escaping DatabaseRemover
    ) {
        self.storageFactory = storageFactory
        self.corruptionHandler = corruptionHandler
        self.databaseRemover = databaseRemover
    }

    func bootstrap(databasePath: String, completion: @escaping Completion) {
        queue.async { [storageFactory, corruptionHandler, databaseRemover] in
            let result: Result<StorageManager, AppBootstrapError>
            do {
                result = .success(try storageFactory(databasePath))
            } catch {
                switch corruptionHandler(databasePath) {
                case .deleteAndRescan:
                    try? databaseRemover(databasePath)
                    do {
                        result = .success(try storageFactory(databasePath))
                    } catch {
                        result = .failure(.storageUnavailable)
                    }
                default:
                    result = .failure(.storageUnavailable)
                }
            }

            Task { @MainActor in
                completion(result)
            }
        }
    }
}
