import Testing
import Dispatch
@testable import LaunchPad
import LaunchPadProtocols

@Suite("DI 协议定义验证")
@MainActor
struct ProtocolTests {

    @Test("layout mutator 记录稳定 intent 与容量")
    func layoutMutatorRecordsIntentAndCapacity() throws {
        let sut = MockLayoutMutator()
        let intent = LayoutDropIntent.moveTopLevel(
            itemID: 8,
            placement: .beforeItem(itemID: 3)
        )
        try sut.apply(intent, pageCapacity: 35)
        #expect(sut.appliedIntents == [intent])
        #expect(sut.appliedPageCapacities == [35])
    }

    @Test("item placement 暴露稳定 anchor ID")
    func placementAnchorID() {
        #expect(ItemPlacement.beforeItem(itemID: 4).anchorItemID == 4)
        #expect(ItemPlacement.afterItem(itemID: 9).anchorItemID == 9)
    }

    @Test("layout mutator 错误不记录未提交 intent")
    func layoutMutatorFailureDoesNotRecordIntent() {
        let sut = MockLayoutMutator()
        sut.applyError = TestError.generic

        #expect(throws: TestError.self) {
            try sut.apply(
                .deleteFolder(folderID: 7),
                pageCapacity: 35
            )
        }
        #expect(sut.appliedIntents.isEmpty)
        #expect(sut.appliedPageCapacities.isEmpty)
    }

    @Test("MockItemReader 遵循 ItemReading")
    func mockItemReader_conformsToItemReading() {
        let reader = MockItemReader()
        let _: ItemReading = reader
        #expect(reader.fetchAllItemsCallCount == 0)
    }

    @Test("MockItemWriter 遵循 ItemWriting")
    func mockItemWriter_conformsToItemWriting() throws {
        let writer: ItemWriting = MockItemWriter()
        let _ = try writer.insertItem(
            TestDataFactory.makePageItem(type: .app)
        )
    }

    @Test("MockImageStore 遵循 ImageStoring")
    func mockImageStore_conformsToImageStoring() {
        let store: ImageStoring = MockImageStore()
        #expect(store is ImageStoring)
    }

    @Test("MockFileSystemService 遵循 FileSystemService")
    func mockFS_conformsToFileSystemService() {
        let fs: FileSystemService = MockFileSystemService()
        #expect(fs is FileSystemService)
    }

    @Test("MockIconProvider 遵循 IconProviding")
    func mockIconProvider_conformsToIconProviding() {
        let provider: IconProviding = MockIconProvider()
        #expect(provider is IconProviding)
    }

    @Test("MockHotkeyManager 遵循 HotkeyManaging")
    func mockHotkey_conformsToHotkeyManaging() {
        let hk: HotkeyManaging = MockHotkeyManager()
        #expect(hk is HotkeyManaging)
    }

    @Test("MockScheduler 遵循 Scheduler")
    func mockScheduler_conformsToScheduler() {
        let s: Scheduler = MockScheduler()
        #expect(s is Scheduler)
    }

    @Test("真实 scheduler 的延迟 action 在 MainActor 执行")
    func dispatchQueueSchedulerRunsActionOnMainActor() async {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let scheduler = DispatchQueueScheduler()
        scheduler.schedule(after: 0) {
            MainActor.preconditionIsolated()
            continuation.yield("safari")
            continuation.finish()
        }
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == "safari")
    }

    @Test("替换、显式取消与释放均取消 exact work item")
    func dispatchQueueSchedulerCancelsOwnedWorkItems() {
        var first: DispatchWorkItem?
        var second: DispatchWorkItem?
        var third: DispatchWorkItem?
        weak var weakScheduler: DispatchQueueScheduler?
        do {
            let scheduler = DispatchQueueScheduler()
            weakScheduler = scheduler
            scheduler.workItemObserver = { item in
                if first == nil { first = item }
                else if second == nil { second = item }
                else { third = item }
            }
            scheduler.schedule(after: 60) {}
            scheduler.schedule(after: 60) {}
            #expect(first?.isCancelled == true)
            #expect(second?.isCancelled == false)
            scheduler.cancelPending()
            #expect(second?.isCancelled == true)
            scheduler.schedule(after: 60) {}
            #expect(third?.isCancelled == false)
        }
        #expect(weakScheduler == nil)
        #expect(third?.isCancelled == true)
    }
}
