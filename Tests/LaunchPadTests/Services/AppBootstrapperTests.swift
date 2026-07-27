import Foundation
import Testing
@testable import LaunchPad

@Suite("AppBootstrapper database startup branches")
struct AppBootstrapperTests {
    private enum FactoryFailure: Error {
        case unavailable
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchPadBootstrap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private static func recordCall(_ name: String, in directory: URL) throws -> Int {
        let url = directory.appendingPathComponent(name)
        let nextCount = ((try? Data(contentsOf: url).count) ?? 0) + 1
        try Data(repeating: 1, count: nextCount).write(to: url)
        return nextCount
    }

    private static func callCount(_ name: String, in directory: URL) -> Int {
        (try? Data(contentsOf: directory.appendingPathComponent(name)).count) ?? 0
    }

    @Test("首次创建成功且后台执行，completion 回到 MainActor")
    func firstAttemptSucceedsOffMainThread() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrapper = AppBootstrapper(
            storageFactory: { _ in
                #expect(!Thread.isMainThread)
                _ = try Self.recordCall("factory", in: directory)
                return try StorageManager(dbPath: ":memory:")
            },
            corruptionHandler: { _ in .deleteAndRescan },
            databaseRemover: { _ in
                Issue.record("remover must not run after first-attempt success")
            }
        )

        await withCheckedContinuation { continuation in
            bootstrapper.bootstrap(databasePath: "/tmp/bootstrap.sqlite3") { result in
                #expect(Thread.isMainThread)
                guard case .success = result else {
                    Issue.record("expected successful storage bootstrap")
                    continuation.resume()
                    return
                }
                continuation.resume()
            }
        }

        #expect(Self.callCount("factory", in: directory) == 1)
        #expect(Self.callCount("remover", in: directory) == 0)
    }

    @Test("首次失败后删除并在后台恢复成功")
    func deleteAndRescanRecoversOffMainThread() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrapper = AppBootstrapper(
            storageFactory: { _ in
                #expect(!Thread.isMainThread)
                let attempt = try Self.recordCall("factory", in: directory)
                if attempt == 1 { throw FactoryFailure.unavailable }
                return try StorageManager(dbPath: ":memory:")
            },
            corruptionHandler: { _ in
                #expect(!Thread.isMainThread)
                _ = try? Self.recordCall("handler", in: directory)
                return .deleteAndRescan
            },
            databaseRemover: { _ in
                #expect(!Thread.isMainThread)
                _ = try Self.recordCall("remover", in: directory)
            }
        )

        await withCheckedContinuation { continuation in
            bootstrapper.bootstrap(databasePath: "/tmp/bootstrap.sqlite3") { result in
                #expect(Thread.isMainThread)
                guard case .success = result else {
                    Issue.record("expected recovered storage")
                    continuation.resume()
                    return
                }
                continuation.resume()
            }
        }

        #expect(Self.callCount("factory", in: directory) == 2)
        #expect(Self.callCount("handler", in: directory) == 1)
        #expect(Self.callCount("remover", in: directory) == 1)
    }

    @Test("删除后的第二次创建失败时返回稳定失败")
    func recoveryFailureReturnsUnavailable() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrapper = AppBootstrapper(
            storageFactory: { _ in
                #expect(!Thread.isMainThread)
                _ = try Self.recordCall("factory", in: directory)
                throw FactoryFailure.unavailable
            },
            corruptionHandler: { _ in .deleteAndRescan },
            databaseRemover: { _ in
                #expect(!Thread.isMainThread)
                _ = try Self.recordCall("remover", in: directory)
            }
        )

        await withCheckedContinuation { continuation in
            bootstrapper.bootstrap(databasePath: "/tmp/bootstrap.sqlite3") { result in
                #expect(Thread.isMainThread)
                #expect(throws: AppBootstrapError.storageUnavailable) {
                    _ = try result.get()
                }
                continuation.resume()
            }
        }

        #expect(Self.callCount("factory", in: directory) == 2)
        #expect(Self.callCount("remover", in: directory) == 1)
    }

    @Test("非删除恢复策略不删除也不重试")
    func nonDeleteStrategyFailsWithoutRetry() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrapper = AppBootstrapper(
            storageFactory: { _ in
                _ = try Self.recordCall("factory", in: directory)
                throw FactoryFailure.unavailable
            },
            corruptionHandler: { _ in .healthy },
            databaseRemover: { _ in
                Issue.record("non-delete strategy must not remove the database")
            }
        )

        await withCheckedContinuation { continuation in
            bootstrapper.bootstrap(databasePath: "/tmp/bootstrap.sqlite3") { result in
                #expect(throws: AppBootstrapError.storageUnavailable) {
                    _ = try result.get()
                }
                continuation.resume()
            }
        }

        #expect(Self.callCount("factory", in: directory) == 1)
        #expect(Self.callCount("remover", in: directory) == 0)
    }

    @Test("删除器失败仍按既有恢复语义重试")
    func removerFailureStillRetries() async throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bootstrapper = AppBootstrapper(
            storageFactory: { _ in
                let attempt = try Self.recordCall("factory", in: directory)
                if attempt == 1 { throw FactoryFailure.unavailable }
                return try StorageManager(dbPath: ":memory:")
            },
            corruptionHandler: { _ in .deleteAndRescan },
            databaseRemover: { _ in
                #expect(!Thread.isMainThread)
                _ = try Self.recordCall("remover", in: directory)
                throw FactoryFailure.unavailable
            }
        )

        await withCheckedContinuation { continuation in
            bootstrapper.bootstrap(databasePath: "/tmp/bootstrap.sqlite3") { result in
                guard case .success = result else {
                    Issue.record("expected retry after remover failure")
                    continuation.resume()
                    return
                }
                continuation.resume()
            }
        }

        #expect(Self.callCount("factory", in: directory) == 2)
        #expect(Self.callCount("remover", in: directory) == 1)
    }
}
