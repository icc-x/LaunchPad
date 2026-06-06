import Testing
@testable import LaunchPad
import LaunchPadProtocols

@Suite("DI 协议定义验证")
struct ProtocolTests {

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
}
