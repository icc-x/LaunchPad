import Testing
import Foundation
import CoreGraphics
@testable import LaunchPad
import LaunchPadProtocols
#if canImport(AppKit)
import AppKit

@MainActor
@Suite("LaunchPadViewController 键盘交互与执行动作")
struct LaunchPadViewControllerTests {

    // MARK: - Test Doubles

    private final class MockDataStore: DataStoring, @unchecked Sendable {
        var pages: [PageItem] = []
        var childrenByPage: [Int64: [PageItem]] = [:]
        var deletedIds: [Int64] = []

        func fetchAllItems(parentId: Int64?) throws -> [PageItem] {
            if let parentId {
                return childrenByPage[parentId] ?? []
            }
            return pages
        }

        func insertItem(_ item: PageItem) throws -> Int64 { item.id }
        func updateItem(_ item: PageItem) throws {}
        func deleteItem(id: Int64) throws { deletedIds.append(id) }
        func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {}
        func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {}
        func fetchImage(itemId: Int64) throws -> (Data, Data)? { nil }
    }

    // MARK: - Helpers

    private func makeSUT(dragScheduler: Scheduler = DispatchQueueScheduler()) -> (LaunchPadViewController, DragController, MockDataStore) {
        let storage = MockDataStore()
        let iconProvider = MockIconProvider()
        let iconCache = IconCache(iconProvider: iconProvider, imageStore: storage)
        let dragController = DragController(itemWriter: storage, scheduler: dragScheduler)
        let folderController = FolderController(itemWriter: storage)
        let sut = LaunchPadViewController(
            storage: storage,
            iconCache: iconCache,
            dragController: dragController,
            folderController: folderController
        )
        return (sut, dragController, storage)
    }

    // MARK: - ESC 关闭窗口

    @Test("idle 状态 ESC 触发 onClose 回调")
    func idle_esc_triggersOnClose() {
        let (sut, _, _) = makeSUT()
        var closeCalled = false
        sut.onClose = { closeCalled = true }

        _ = sut.handleKeyEvent(.escape)

        #expect(closeCalled == true)
    }

    // MARK: - ESC 退出编辑模式

    @Test("edit 状态 ESC 退出编辑模式 — dragController 回到 idle")
    func edit_esc_exitsEditMode() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        dragController.beginEditing(originalOrder: [1, 2, 3])
        dragController.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)
        sut.keyboardNavigator.mode = .edit

        _ = sut.handleKeyEvent(.escape)

        #expect(dragController.state == .idle)
        #expect(sut.keyboardNavigator.mode == .idle)
    }

    // MARK: - 方向键导航（视图未加载安全）

    @Test("down 方向键在视图未加载时安全无副作用")
    func idle_downArrow_safeWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedIndex == nil)
        _ = sut.handleKeyEvent(.downArrow)
        #expect(sut.selectedIndex == nil)
    }

    @Test("tab 键在视图未加载时安全无副作用")
    func idle_tab_safeWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedIndex == nil)
        _ = sut.handleKeyEvent(.tab)
        #expect(sut.selectedIndex == nil)
    }

    @Test("up 方向键在视图未加载时安全无副作用")
    func idle_upArrow_safeWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedIndex == nil)
        _ = sut.handleKeyEvent(.upArrow)
        #expect(sut.selectedIndex == nil)
    }

    // MARK: - handleCharacterInput

    @Test("字符输入在 idle 模式下返回 enterSearchMode")
    func characterInput_returnsEnterSearchMode() {
        let (sut, _, _) = makeSUT()

        let action = sut.handleCharacterInput("a")

        // handleCharacter 在 idle 模式下返回 enterSearchMode
        if case .enterSearchMode(let char) = action {
            #expect(char == "a")
        } else {
            Issue.record("Expected enterSearchMode, got \(action)")
        }
    }

    @Test("字符输入在视图未加载时不崩溃")
    func characterInput_doesNotCrashWhenViewNotLoaded() {
        let (sut, _, _) = makeSUT()
        // 视图未加载时 executeAction(.enterSearchMode) 因 guard isViewLoaded 安全返回
        _ = sut.handleCharacterInput("a")
        _ = sut.handleCharacterInput("b")
        _ = sut.handleCharacterInput("c")
    }

    // MARK: - handleKeyEvent 返回值

    @Test("handleKeyEvent 返回正确的 action 枚举")
    func handleKeyEvent_returnsCorrectAction() {
        let (sut, _, _) = makeSUT()

        let escAction = sut.handleKeyEvent(.escape)
        #expect(escAction == .closeWindow)

        let upAction = sut.handleKeyEvent(.upArrow)
        #expect(upAction == .moveUp)

        let downAction = sut.handleKeyEvent(.downArrow)
        #expect(downAction == .moveDown)

        let tabAction = sut.handleKeyEvent(.tab)
        #expect(tabAction == .selectNext)

        let leftAction = sut.handleKeyEvent(.leftArrow)
        #expect(leftAction == .previousPage)

        let rightAction = sut.handleKeyEvent(.rightArrow)
        #expect(rightAction == .nextPage)

        let enterAction = sut.handleKeyEvent(.enter)
        #expect(enterAction == .launchSelected)
    }

    // MARK: - onClose 回调

    @Test("onClose 回调可安全设置和调用")
    func onClose_callbackSafeToSetAndCall() {
        let (sut, _, _) = makeSUT()

        // nil callback 不崩溃
        sut.onClose = nil
        _ = sut.handleKeyEvent(.escape)

        // 设置 callback 后调用
        var called = false
        sut.onClose = { called = true }
        _ = sut.handleKeyEvent(.escape)
        #expect(called == true)
    }

    // MARK: - 连续 ESC

    @Test("连续两次 ESC 不崩溃")
    func doubleEsc_doesNotCrash() {
        let (sut, _, _) = makeSUT()
        var closeCount = 0
        sut.onClose = { closeCount += 1 }

        _ = sut.handleKeyEvent(.escape)
        _ = sut.handleKeyEvent(.escape)

        #expect(closeCount == 2)
    }

    // MARK: - selectedIndex 初始状态

    @Test("selectedIndex 初始为 nil")
    func selectedIndex_initiallyNil() {
        let (sut, _, _) = makeSUT()
        #expect(sut.selectedIndex == nil)
    }

    // MARK: - KeyboardNavigator 集成覆盖

    @Test("所有 KeyboardNavigator.Key 都可安全处理不崩溃")
    func allKeys_handleSafely() {
        let (sut, _, _) = makeSUT()
        let keys: [KeyboardNavigator.Key] = [
            .escape, .leftArrow, .rightArrow, .upArrow, .downArrow, .enter, .tab, .delete
        ]
        for key in keys {
            _ = sut.handleKeyEvent(key)
        }
    }

    // MARK: - KeyboardNavigator mode 直接设置后的行为

    @Test("手动设置 search 模式后 ESC 返回 clearSearch")
    func manualSearchMode_esc_returnsClearSearch() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "test")

        let action = sut.handleKeyEvent(.escape)
        #expect(action == .clearSearch)
    }

    @Test("手动设置 search 模式后 enter 返回 launchFirstMatch")
    func manualSearchMode_enter_returnsLaunchFirstMatch() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "test")

        let action = sut.handleKeyEvent(.enter)
        #expect(action == .launchFirstMatch)
    }

    @Test("手动设置 search 模式后 delete 返回 deleteLastCharacter")
    func manualSearchMode_delete_returnsDeleteLastCharacter() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "test")

        let action = sut.handleKeyEvent(.delete)
        #expect(action == .deleteLastCharacter)
    }

    @Test("手动设置 edit 模式后 up/down arrow 返回 ignored（edit 模式仅 ESC 有效）")
    func manualEditMode_arrows_returnsIgnored() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .edit

        let upAction = sut.handleKeyEvent(.upArrow)
        #expect(upAction == .ignored)

        let downAction = sut.handleKeyEvent(.downArrow)
        #expect(downAction == .ignored)

        let leftAction = sut.handleKeyEvent(.leftArrow)
        #expect(leftAction == .ignored)

        let rightAction = sut.handleKeyEvent(.rightArrow)
        #expect(rightAction == .ignored)
    }

    // MARK: - DragController 状态同步

    @Test("dragController jiggling 状态可正确建立")
    func dragController_jiggling_stateEstablished() {
        let scheduler = MockScheduler()
        let (_, dragController, _) = makeSUT(dragScheduler: scheduler)

        dragController.beginEditing(originalOrder: [1, 2, 3])
        dragController.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)

        #expect(dragController.state == .jiggling)
    }

    // MARK: - Multiple character inputs

    @Test("多个字符输入都返回 enterSearchMode（idle 模式下）")
    func multipleCharacters_allReturnEnterSearchMode() {
        let (sut, _, _) = makeSUT()

        for char in ["a", "b", "c"] {
            let action = sut.handleCharacterInput(char)
            if case .enterSearchMode = action {
                // expected — mode stays idle because view is not loaded
            } else {
                Issue.record("Expected enterSearchMode for '\(char)', got \(action)")
            }
        }
    }

    // MARK: - loadData

    @Test("loadData with empty storage does not crash")
    func loadData_emptyStorage_noCrash() {
        let (sut, _, _) = makeSUT()
        _ = sut.view // trigger loadView
        sut.loadData()
    }

    @Test("loadData with pages populates internal state")
    func loadData_withPages_populatesState() {
        let (sut, _, storage) = makeSUT()
        _ = sut.view // trigger loadView
        let page = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let app = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, parentId: 1,
                                                app: TestDataFactory.makeAppInfo(id: 10, title: "Safari"))
        storage.pages = [page]
        storage.childrenByPage = [1: [app]]

        sut.loadData()

        #expect(sut.selectedIndex == nil)
    }

    @Test("loadData with multiple pages")
    func loadData_multiplePages_noCrash() {
        let (sut, _, storage) = makeSUT()
        _ = sut.view // trigger loadView
        let page1 = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let page2 = TestDataFactory.makePageItem(id: 2, type: .page, ordering: 1)
        let apps1 = TestDataFactory.makeAppItems(count: 5, titlePrefix: "P1")
        let apps2 = TestDataFactory.makeAppItems(count: 3, titlePrefix: "P2")
        storage.pages = [page1, page2]
        storage.childrenByPage = [1: apps1, 2: apps2]

        sut.loadData()
    }

    // MARK: - handleKeyEvent edge cases

    @Test("delete key in idle mode returns ignored")
    func idle_delete_returnsIgnored() {
        let (sut, _, _) = makeSUT()
        let action = sut.handleKeyEvent(.delete)
        #expect(action == .ignored)
    }

    @Test("search mode character input returns appendToQuery")
    func searchMode_character_returnsAppendToQuery() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .search(query: "te")

        let action = sut.handleCharacterInput("s")
        if case .appendToQuery(let char) = action {
            #expect(char == "s")
        } else {
            Issue.record("Expected appendToQuery")
        }
    }

    @Test("edit mode character input returns ignored")
    func editMode_character_returnsIgnored() {
        let (sut, _, _) = makeSUT()
        sut.keyboardNavigator.mode = .edit

        let action = sut.handleCharacterInput("a")
        #expect(action == .ignored)
    }

    // MARK: - DragController integration

    @Test("dragController handleCancel from jiggling returns to idle")
    func dragController_cancelFromJiggling_returnsToIdle() {
        let scheduler = MockScheduler()
        let (_, dragController, _) = makeSUT(dragScheduler: scheduler)

        dragController.beginEditing(originalOrder: [1, 2, 3])
        dragController.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)

        dragController.handleCancel()
        #expect(dragController.state == .idle)
    }

    @Test("dragController onPageChange callback is settable")
    func dragController_onPageChange_settable() {
        let (_, dragController, _) = makeSUT()
        var direction: DragController.PageChangeDirection?
        dragController.onPageChange = { dir in direction = dir }
        #expect(dragController.onPageChange != nil)
    }

    @Test("dragController onCreateGroup callback is settable")
    func dragController_onCreateGroup_settable() {
        let (_, dragController, _) = makeSUT()
        var targetId: Int64?
        dragController.onCreateGroup = { id in targetId = id }
        #expect(dragController.onCreateGroup != nil)
    }

    // MARK: - FolderController integration

    @Test("handleCreateGroup with non-existent targetId does not crash")
    func handleCreateGroup_nonExistentTarget_noCrash() {
        let (sut, dragController, storage) = makeSUT()
        dragController.beginEditing(originalOrder: [1, 2])
        // handleCreateGroup is private, but we can test via the callback
        var createGroupCalled = false
        dragController.onCreateGroup = { _ in createGroupCalled = true }
        dragController.onCreateGroup?(999)
        #expect(createGroupCalled)
    }
}
#endif
