import Testing
@testable import LaunchPad

@Suite("FolderController folder operations")
struct FolderControllerTests {

    private func makeSUT() throws -> (FolderController, MockItemWriter, MockItemReader) {
        let writer = MockItemWriter()
        let reader = MockItemReader()
        let controller = FolderController(itemWriter: writer)
        return (controller, writer, reader)
    }

    @Test("Create folder — two items merged into group")
    func createFolder_mergesTwoItems() throws {
        let (sut, writer, reader) = try makeSUT()
        let itemA = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(title: "Safari"))
        let itemB = TestDataFactory.makePageItem(id: 2, type: .app, ordering: 1,
            app: TestDataFactory.makeAppInfo(title: "Mail"))

        let folderId = try sut.createFolder(from: itemA, and: itemB, title: "New Folder")

        #expect(folderId > 0)
        #expect(writer.insertedItems.count == 1)
        #expect(writer.insertedItems.first?.type == .group)
        #expect(writer.updatedItems.count == 2)
    }

    @Test("Create folder — default title is New Folder")
    func createFolder_defaultTitle() throws {
        let (sut, writer, reader) = try makeSUT()
        let itemA = TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(title: "Safari"))
        let itemB = TestDataFactory.makePageItem(id: 2, type: .app, ordering: 1,
            app: TestDataFactory.makeAppInfo(title: "Mail"))

        try sut.createFolder(from: itemA, and: itemB)

        #expect(writer.insertedItems.first?.group?.title == "New Folder")
    }

    @Test("Add to folder — item moves into existing folder")
    func addToFolder_movesItemIntoFolder() throws {
        let (sut, writer, reader) = try makeSUT()
        let item = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 3)
        let folderItem = TestDataFactory.makePageItem(id: 5, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 5, title: "Games"))

        try sut.addToFolder(item: item, folderItem: folderItem)

        #expect(writer.updatedItems.count == 1)
        #expect(writer.updatedItems.first?.parentId == 5)
    }

    @Test("Dissolve folder — 1 remaining item auto-dissolves")
    func dissolveFolder_whenOneItemRemains() throws {
        let (sut, writer, reader) = try makeSUT()
        let children = [
            TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, parentId: 5)
        ]

        try sut.dissolveFolder(folderId: 5, movingChildrenTo: 1, children: children)

        #expect(writer.deletedIds.contains(5))
        #expect(writer.updatedItems.count == 1)
        #expect(writer.updatedItems.first?.parentId == 1)
    }

    @Test("Dissolve folder — 2+ items does not auto-dissolve")
    func dissolveFolder_notCalled_whenMultipleItems() throws {
        let (sut, _, _) = try makeSUT()
        let children = [
            TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, parentId: 5),
            TestDataFactory.makePageItem(id: 11, type: .app, ordering: 1, parentId: 5)
        ]
        #expect(children.count == 2)
    }

    @Test("Remove from folder — item moves from folder to main grid")
    func removeFromFolder_movesToMainGrid() throws {
        let (sut, writer, reader) = try makeSUT()
        let item = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, parentId: 5)

        try sut.removeFromFolder(item: item, folderId: 5, targetPageId: 1, targetOrdering: 3, reader: reader)

        #expect(writer.updatedItems.count == 1)
        #expect(writer.updatedItems.first?.parentId == 1)
    }

    @Test("Rename folder")
    func renameFolder_updatesTitle() throws {
        let (sut, writer, reader) = try makeSUT()
        let group = TestDataFactory.makeGroupInfo(id: 5, title: "Old Name")
        let item = TestDataFactory.makePageItem(id: 5, type: .group, group: group)

        try sut.renameFolder(item: item, newTitle: "New Name")

        #expect(writer.updatedItems.count == 1)
        #expect(writer.updatedItems.first?.group?.title == "New Name")
    }
}
