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

    // MARK: - ESC 关闭窗口 (Task: 修复 .closeWindow 空实现)

    @Test("idle 状态 ESC 触发 onClose 回调")
    func idle_esc_triggersOnClose() {
        let (sut, _, _) = makeSUT()
        var closeCalled = false
        sut.onClose = { closeCalled = true }

        _ = sut.handleKeyEvent(.escape)

        #expect(closeCalled == true)
    }

    // MARK: - ESC 退出编辑模式 (Task: 修复 .exitEditMode 空实现)

    @Test("edit 状态 ESC 退出编辑模式 — dragController 回到 idle")
    func edit_esc_exitsEditMode() {
        let scheduler = MockScheduler()
        let (sut, dragController, _) = makeSUT(dragScheduler: scheduler)
        // 进入 jiggling（编辑模式）：beginEditing + handlePressBegan + 推进 0.5s
        dragController.beginEditing(originalOrder: [1, 2, 3])
        dragController.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)
        #expect(dragController.state == .jiggling)
        // 同步 keyboardNavigator 到 edit 模式（模拟 updateJiggleState 的行为）
        sut.keyboardNavigator.mode = .edit

        _ = sut.handleKeyEvent(.escape)

        #expect(dragController.state == .idle)
        #expect(sut.keyboardNavigator.mode == .idle)
    }

    // MARK: - 方向键导航 (Task: 修复 .moveUp/.moveDown 空实现)
    // 这些测试需要视图已加载 + 数据填充，否则 moveSelection 会因
    // collectionView 未初始化而崩溃。guard isViewLoaded 在未加载时安全返回。

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
}
#endif
