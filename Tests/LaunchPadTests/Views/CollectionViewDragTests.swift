import Foundation
import Testing
import LaunchPadProtocols
@testable import LaunchPad

@MainActor
@Suite("NSCollectionView 拖拽 Delegate")
struct CollectionViewDragTests {

    @Test("DragController idle → handlePressBegan → jiggling after 0.5s")
    func dragStateMachine_idleToJiggling() {
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)

        controller.handlePressBegan(at: CGPoint(x: 100, y: 100))
        #expect(controller.state == .idle) // 还没到 0.5s

        scheduler.advance(by: 0.5)
        #expect(controller.state == .jiggling)
    }

    @Test("DragController jiggling → handleDragStart → dragging")
    func dragStateMachine_jigglingToDragging() {
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)

        controller.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.5)
        #expect(controller.state == .jiggling)

        controller.handleDragStart()
        #expect(controller.state == .dragging)
    }

    @Test("DragController dragging → handleDrop → idle + commit")
    func dragStateMachine_dropCommitsReorder() {
        let writer = MockItemWriter()
        let controller = DragController(itemWriter: writer)

        controller.beginEditing(originalOrder: [1, 2, 3])
        controller.handleDragStart()
        controller.simulateReorder(from: 0, to: 2)
        controller.handleDrop()

        #expect(controller.state == .idle)
        #expect(writer.reorderedParentIds.count == 1)
    }

    @Test("DragController dragging → handleCancel → idle + rollback")
    func dragStateMachine_cancelRollsback() {
        let controller = DragController()

        controller.beginEditing(originalOrder: [1, 2, 3])
        controller.handleDragStart()
        controller.simulateReorder(from: 0, to: 2)
        #expect(controller.currentOrder == [2, 3, 1])

        controller.handleCancel()
        #expect(controller.state == .idle)
        #expect(controller.currentOrder == [1, 2, 3]) // 回滚
    }

    @Test("DragController hover overEdge 1.5s triggers pageChange")
    func dragStateMachine_edgeHoverTriggersPageChange() {
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)
        var pageChangeCount = 0
        controller.onPageChange = { _ in pageChangeCount += 1 }

        controller.handleDragStart()
        controller.updateDragHover(location: .screenEdge)
        scheduler.advance(by: 1.5)

        #expect(pageChangeCount == 1)
    }

    @Test("DragController hover overIcon 0.8s triggers createGroup")
    func dragStateMachine_iconHoverTriggersCreateGroup() {
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)
        var createGroupTargetId: Int64?
        controller.onCreateGroup = { id in createGroupTargetId = id }

        controller.handleDragStart()
        controller.updateDragHover(location: .overIcon(targetId: 42))
        scheduler.advance(by: 0.8)

        #expect(createGroupTargetId == 42)
    }

    @Test("DragController movement > 10px during long press skips jiggling → dragging")
    func dragStateMachine_movementSkipsJiggling() {
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)

        controller.handlePressBegan(at: CGPoint(x: 100, y: 100))
        controller.handleDragMoved(to: CGPoint(x: 120, y: 100)) // 20px > 10px threshold

        #expect(controller.state == .dragging)
    }

    @Test("DragController handlePressBegan at 0.49s → still idle (boundary)")
    func dragStateMachine_boundaryBeforeLongPress() {
        let scheduler = MockScheduler()
        let controller = DragController(scheduler: scheduler)

        controller.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.49)
        #expect(controller.state == .idle)

        scheduler.advance(by: 0.01)
        #expect(controller.state == .jiggling)
    }
}
