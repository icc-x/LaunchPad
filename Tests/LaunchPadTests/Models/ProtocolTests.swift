import Testing
import Dispatch
import Foundation
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

    @Test("ImageStoring existential 转发 exact image payload")
    func mockImageStore_conformsToImageStoring() throws {
        let store: ImageStoring = MockImageStore()
        let icon1x = Data([1, 2, 3])
        let icon2x = Data([4, 5, 6])

        try store.saveImage(itemId: 42, icon1x: icon1x, icon2x: icon2x)
        let fetched = try #require(try store.fetchImage(itemId: 42))

        #expect(fetched.0 == icon1x)
        #expect(fetched.1 == icon2x)
    }

    @Test("FileSystemService existential 转发目录与存在性查询")
    func mockFS_conformsToFileSystemService() throws {
        let root = URL(fileURLWithPath: "/Applications")
        let app = root.appendingPathComponent("Observed.app")
        let mock = MockFileSystemService()
        mock.directoryContentsMap[root] = [app]
        mock.existingFiles = [app]
        let fs: FileSystemService = mock

        #expect(try fs.contentsOfDirectory(at: root) == [app])
        #expect(fs.fileExists(at: app))
    }

    @Test("IconProviding existential 转发 exact modification date")
    func mockIconProvider_conformsToIconProviding() {
        let path = "/Applications/Observed.app"
        let expectedDate = Date(timeIntervalSince1970: 1_234)
        let mock = MockIconProvider()
        mock.modificationDates[path] = expectedDate
        let provider: IconProviding = mock

        #expect(provider.modificationDate(forPath: path) == expectedDate)
    }

    @Test("HotkeyManaging existential 转发注册与注销")
    func mockHotkey_conformsToHotkeyManaging() {
        let mock = MockHotkeyManager()
        let hotkey: HotkeyManaging = mock

        let registered = hotkey.registerGlobalHotkey(
            keyCode: 49,
            modifiers: []
        )
        hotkey.unregisterGlobalHotkey()

        #expect(registered)
        #expect(mock.registerCallCount == 1)
        #expect(mock.unregisterCallCount == 1)
    }

    @Test("Scheduler existential 转发并执行 exact action")
    func mockScheduler_conformsToScheduler() {
        let mock = MockScheduler()
        let scheduler: Scheduler = mock
        var values: [String] = []

        scheduler.schedule(after: 0.25) { values.append("fired") }
        mock.advance(by: 0.24)
        #expect(values.isEmpty)
        mock.advance(by: 0.01)

        #expect(values == ["fired"])
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
