import Foundation
import os
import Testing
@testable import LaunchPad
import LaunchPadProtocols

@MainActor
@Suite("LayoutRepository background serialization")
struct LayoutRepositoryTests {
    private enum InjectedFailure: Error, Equatable {
        case read
        case apply
        case rename
    }

    private final class RecordingStorage: LayoutReading, LayoutMutating, ItemWriting {
        struct State {
            var readMainThreadFlags: [Bool] = []
            var applyMainThreadFlags: [Bool] = []
            var renameMainThreadFlags: [Bool] = []
            var appliedIntents: [LayoutDropIntent] = []
            var appliedCapacities: [Int] = []
            var updatedItems: [PageItem] = []
            var readShouldFail = false
            var applyShouldFail = false
            var renameShouldFail = false
        }

        let persistedSnapshot: PersistedLayoutSnapshot
        private let state = OSAllocatedUnfairLock(initialState: State())

        init(persistedSnapshot: PersistedLayoutSnapshot) {
            self.persistedSnapshot = persistedSnapshot
        }

        func persistedLayoutSnapshot() throws -> PersistedLayoutSnapshot {
            let shouldFail = state.withLock { state in
                state.readMainThreadFlags.append(Thread.isMainThread)
                return state.readShouldFail
            }
            if shouldFail { throw InjectedFailure.read }
            return persistedSnapshot
        }

        func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws {
            let shouldFail = state.withLock { state in
                state.applyMainThreadFlags.append(Thread.isMainThread)
                state.appliedIntents.append(intent)
                state.appliedCapacities.append(pageCapacity)
                return state.applyShouldFail
            }
            if shouldFail { throw InjectedFailure.apply }
        }

        func insertItem(_ item: PageItem) throws -> Int64 { item.id }

        func updateItem(_ item: PageItem) throws {
            let shouldFail = state.withLock { state in
                state.renameMainThreadFlags.append(Thread.isMainThread)
                state.updatedItems.append(item)
                return state.renameShouldFail
            }
            if shouldFail { throw InjectedFailure.rename }
        }

        func deleteItem(id: Int64) throws {}
        func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {}

        func snapshot() -> State { state.withLock { $0 } }

        func setFailures(read: Bool, apply: Bool, rename: Bool) {
            state.withLock { state in
                state.readShouldFail = read
                state.applyShouldFail = apply
                state.renameShouldFail = rename
            }
        }
    }

    private final class BlockingMutator: LayoutMutating {
        private let firstApplyEntered: AsyncStream<Int64>.Continuation
        private let releaseFirstApply = DispatchSemaphore(value: 0)
        private let appliedIDs = OSAllocatedUnfairLock(initialState: [Int64]())

        init(firstApplyEntered: AsyncStream<Int64>.Continuation) {
            self.firstApplyEntered = firstApplyEntered
        }

        func apply(_ intent: LayoutDropIntent, pageCapacity: Int) throws {
            guard case .deleteApp(let itemID) = intent else {
                Issue.record("Expected deleteApp intent")
                return
            }
            appliedIDs.withLock { $0.append(itemID) }
            firstApplyEntered.yield(itemID)
            if itemID == 1 {
                releaseFirstApply.wait()
            }
        }

        func releaseFirst() {
            releaseFirstApply.signal()
        }

        func observedIDs() -> [Int64] {
            appliedIDs.withLock { $0 }
        }
    }

    private func makePage(id: Int64 = 1) -> PageItem {
        PageItem(
            id: id,
            uuid: "page-\(id)",
            type: .page,
            ordering: 0,
            parentId: nil,
            app: nil,
            group: nil
        )
    }

    private func makeFolder(group: GroupInfo?) -> PageItem {
        PageItem(
            id: 5,
            uuid: "folder-5",
            type: .group,
            ordering: 2,
            parentId: 1,
            app: nil,
            group: group
        )
    }

    @Test("load/apply/rename 的同步存储工作都离开 MainActor")
    func storageWorkRunsOffMainActor() async throws {
        let page = makePage()
        let storage = RecordingStorage(
            persistedSnapshot: PersistedLayoutSnapshot(allItems: [page])
        )
        let repository = LayoutRepository(
            reader: storage,
            mutator: storage,
            writer: storage
        )

        _ = try await repository.load()
        try await repository.apply(.deleteFolder(folderID: 9), pageCapacity: 35)
        try await repository.renameFolder(
            makeFolder(group: GroupInfo(id: 5, title: "Old")),
            newTitle: "New"
        )

        let observed = storage.snapshot()
        #expect(observed.readMainThreadFlags == [false])
        #expect(observed.applyMainThreadFlags == [false])
        #expect(observed.renameMainThreadFlags == [false])
        #expect(observed.appliedIntents == [.deleteFolder(folderID: 9)])
        #expect(observed.appliedCapacities == [35])
        #expect(observed.updatedItems.first?.group?.title == "New")
    }

    @Test("rename 在 group 缺失时补齐 metadata 并保留 item identity")
    func renameFolderCreatesMissingGroupMetadata() async throws {
        let page = makePage()
        let storage = RecordingStorage(
            persistedSnapshot: PersistedLayoutSnapshot(allItems: [page])
        )
        let repository = LayoutRepository(
            reader: storage,
            mutator: storage,
            writer: storage
        )
        let folder = makeFolder(group: nil)

        try await repository.renameFolder(folder, newTitle: "Created Folder")

        let updated = try #require(storage.snapshot().updatedItems.first)
        #expect(updated.id == folder.id)
        #expect(updated.uuid == folder.uuid)
        #expect(updated.ordering == folder.ordering)
        #expect(updated.parentId == folder.parentId)
        #expect(updated.group == GroupInfo(id: folder.id, title: "Created Folder"))
    }

    @Test("load/apply/rename 的错误保持原样传播")
    func operationFailuresPropagate() async throws {
        let storage = RecordingStorage(
            persistedSnapshot: PersistedLayoutSnapshot(allItems: [makePage()])
        )
        let repository = LayoutRepository(
            reader: storage,
            mutator: storage,
            writer: storage
        )

        storage.setFailures(read: true, apply: false, rename: false)
        do {
            _ = try await repository.load()
            Issue.record("Expected read failure")
        } catch {
            #expect(error as? InjectedFailure == .read)
        }

        storage.setFailures(read: false, apply: true, rename: false)
        do {
            try await repository.apply(.deleteApp(itemID: 1), pageCapacity: 35)
            Issue.record("Expected apply failure")
        } catch {
            #expect(error as? InjectedFailure == .apply)
        }

        storage.setFailures(read: false, apply: false, rename: true)
        do {
            try await repository.renameFolder(
                makeFolder(group: nil),
                newTitle: "New"
            )
            Issue.record("Expected rename failure")
        } catch {
            #expect(error as? InjectedFailure == .rename)
        }
    }

    @Test("并发提交按 actor 顺序串行执行")
    func concurrentMutationsAreSerialized() async throws {
        let firstApplyEntered = AsyncStream<Int64>.makeStream()
        var entries = firstApplyEntered.stream.makeAsyncIterator()
        let storage = RecordingStorage(
            persistedSnapshot: PersistedLayoutSnapshot(allItems: [makePage()])
        )
        let mutator = BlockingMutator(
            firstApplyEntered: firstApplyEntered.continuation
        )
        let repository = LayoutRepository(
            reader: storage,
            mutator: mutator,
            writer: storage
        )

        let first = Task {
            try await repository.apply(.deleteApp(itemID: 1), pageCapacity: 35)
        }
        #expect(await entries.next() == 1)

        let secondAttempted = AsyncStream<Void>.makeStream()
        var attempts = secondAttempted.stream.makeAsyncIterator()
        let second = Task {
            secondAttempted.continuation.yield()
            try await repository.apply(.deleteApp(itemID: 2), pageCapacity: 35)
        }
        _ = await attempts.next()
        #expect(mutator.observedIDs() == [1])

        mutator.releaseFirst()
        try await first.value
        try await second.value
        #expect(mutator.observedIDs() == [1, 2])
    }
}
