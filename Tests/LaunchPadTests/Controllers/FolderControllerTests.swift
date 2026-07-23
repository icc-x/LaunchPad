import Testing
@testable import LaunchPad

@Suite("FolderController folder metadata")
struct FolderControllerTests {

    private func makeSUT() -> (FolderController, MockItemWriter) {
        let writer = MockItemWriter()
        let controller = FolderController(itemWriter: writer)
        return (controller, writer)
    }

    @Test("Rename folder")
    func renameFolder_updatesTitle() throws {
        let (sut, writer) = makeSUT()
        let group = TestDataFactory.makeGroupInfo(id: 5, title: "Old Name")
        let item = TestDataFactory.makePageItem(id: 5, type: .group, group: group)

        try sut.renameFolder(item: item, newTitle: "New Name")

        #expect(writer.updatedItems.count == 1)
        #expect(writer.updatedItems.first?.group?.title == "New Name")
    }

    @Test("Rename folder - item.group 为 nil 时创建默认 GroupInfo")
    func renameFolder_nilGroup_createsDefaultGroup() throws {
        let (sut, writer) = makeSUT()
        let item = TestDataFactory.makePageItem(id: 5, type: .group, group: nil)

        try sut.renameFolder(item: item, newTitle: "Created Folder")

        #expect(writer.updatedItems.count == 1)
        #expect(writer.updatedItems.first?.group?.title == "Created Folder")
    }
}
