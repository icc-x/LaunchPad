import Testing
import Foundation
import CoreGraphics
@testable import LaunchPad

/// Thread-safe helpers for @Sendable closure tests
private final class SendableState: @unchecked Sendable {
    var direction: DragController.PageChangeDirection?
    var boolFlag: Bool = false
    var targetId: Int64?
    var count: Int = 0
}

// MARK: - State Machine Tests

@Suite("DragController state machine")
struct DragControllerTests {

    // MARK: - DragState enum definition verification

    @Test("DragState contains all necessary states")
    func dragState_hasAllCases() {
        let allStates: [DragController.DragState] = [.idle, .jiggling, .dragging]
        #expect(allStates.count == 3)
    }

    @Test("DraggingSubstate contains overEdge and overIcon")
    func draggingSubstate_hasBothCases() {
        let substates: [DragController.DraggingSubstate] = [.none, .overEdge, .overIcon(targetId: 0)]
        #expect(substates.count == 3)
    }

    // MARK: - State transitions: idle -> jiggling

    @Test("idle state long press 0.5s with movement < 10px -> transitions to jiggling")
    func idle_to_jiggling_onLongPress() {
        let controller = DragController()
        #expect(controller.state == .idle)

        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)
    }

    // MARK: - State transitions: jiggling -> dragging

    @Test("jiggling state drag start -> transitions to dragging")
    func jiggling_to_dragging_onDragStart() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)

        controller.handleDragStart()
        #expect(controller.state == .dragging)
        #expect(controller.draggingSubstate == .none)
    }

    // MARK: - State transitions: dragging -> idle (drop)

    @Test("dragging state drop -> executes drop and transitions back to idle")
    func dragging_to_idle_onDrop() {
        let mockWriter = MockItemWriter()
        let controller = DragController(itemWriter: mockWriter)
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        #expect(controller.state == .dragging)

        controller.handleDrop()
        #expect(controller.state == .idle)
        #expect(controller.draggingSubstate == .none)
    }

    // MARK: - State transitions: dragging + ESC -> idle

    @Test("dragging state ESC -> cancels drag and transitions back to idle")
    func dragging_to_idle_onCancel() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        #expect(controller.state == .dragging)

        controller.handleCancel()
        #expect(controller.state == .idle)
    }

    // MARK: - State transitions: jiggling + ESC -> idle

    @Test("jiggling state ESC -> transitions back to idle")
    func jiggling_to_idle_onEscape() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)

        controller.handleCancel()
        #expect(controller.state == .idle)
    }

    // MARK: - Drag substate transitions

    @Test("Dragging over screen edge -> substate becomes overEdge")
    func dragging_overEdge_substate() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()

        controller.updateDragHover(location: .screenEdge)
        #expect(controller.draggingSubstate == .overEdge)
    }

    @Test("Dragging over icon -> substate becomes overIcon")
    func dragging_overIcon_substate() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()

        controller.updateDragHover(location: .overIcon(targetId: 42))
        #expect(controller.draggingSubstate == .overIcon(targetId: 42))
    }

    @Test("Dragging leaves edge/icon -> substate resets to none")
    func dragging_substate_reset_onLeave() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()

        controller.updateDragHover(location: .screenEdge)
        #expect(controller.draggingSubstate == .overEdge)

        controller.updateDragHover(location: .empty)
        #expect(controller.draggingSubstate == .none)
    }

    // MARK: - Boundary conditions

    @Test("Long press 0.49s interrupted -> stays idle (time boundary)")
    func longPress_interrupted_beforeThreshold_staysIdle() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)
        #expect(controller.state == .idle)

        controller.handlePressBegan(at: CGPoint(x: 100, y: 100))
        mockScheduler.advance(by: 0.49)
        controller.handlePressEnded()

        #expect(controller.state == .idle)
    }

    @Test("Drag cancel restores original order")
    func drag_cancel_restoresOriginalOrder() {
        let mockWriter = MockItemWriter()
        let controller = DragController(itemWriter: mockWriter)

        let originalOrder: [Int64] = [1, 2, 3, 4, 5]
        controller.beginEditing(originalOrder: originalOrder)

        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        controller.simulateReorder(from: 0, to: 3)
        #expect(controller.currentOrder != originalOrder)

        controller.handleCancel()
        #expect(controller.currentOrder == originalOrder)
    }

    @Test("idle state cancel is no-op")
    func idle_cancel_noop() {
        let controller = DragController()
        #expect(controller.state == .idle)

        controller.handleCancel()
        #expect(controller.state == .idle)
    }

    @Test("idle state handleDrop is no-op")
    func idle_drop_noop() {
        let controller = DragController()
        controller.handleDrop()
        #expect(controller.state == .idle)
    }

    @Test("already in dragging state -> handleDragStart guard returns early")
    func dragging_dragStart_guardElse() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        #expect(controller.state == .dragging)

        // handleDragStart is no-op when already dragging (guard else)
        controller.handleDragStart()
        #expect(controller.state == .dragging)
    }

    @Test("non-dragging state updateDragHover -> guard returns early")
    func idle_updateDragHover_guardElse() {
        let controller = DragController()
        controller.updateDragHover(location: .screenEdge)
        #expect(controller.state == .idle)
        #expect(controller.draggingSubstate == .none)
    }

    @Test("jiggling state updateDragHover -> guard returns early")
    func jiggling_updateDragHover_guardElse() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)

        controller.updateDragHover(location: .screenEdge)
        #expect(controller.state == .jiggling)
        #expect(controller.draggingSubstate == .none)
    }

    @Test("jiggling state handleDrop -> guard returns early")
    func jiggling_drop_guardElse() {
        let controller = DragController()
        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)

        controller.handleDrop()
        #expect(controller.state == .jiggling)
    }

    @Test("same hover location updateDragHover -> returns early, no timer restart")
    func dragging_sameHoverLocation_returnsEarly() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        var pageChangeCount = 0
        controller.onPageChange = { _ in pageChangeCount += 1 }

        // First hover triggers timer restart
        controller.updateDragHover(location: .screenEdge)
        // Same location again triggers early return
        controller.updateDragHover(location: .screenEdge)
        // After first timer fires
        mockScheduler.advance(by: 1.5)
        #expect(pageChangeCount == 1)
    }

    @Test("simulateReorder out of bounds -> guard returns early, no change")
    func simulateReorder_outOfBounds_guardElse() {
        let controller = DragController()
        controller.beginEditing(originalOrder: [1, 2, 3])

        controller.simulateReorder(from: -1, to: 2)
        #expect(controller.currentOrder == [1, 2, 3])

        controller.simulateReorder(from: 0, to: 5)
        #expect(controller.currentOrder == [1, 2, 3])

        controller.simulateReorder(from: 0, to: 0)
        #expect(controller.currentOrder == [1, 2, 3])
    }
}

// MARK: - Long Press Detection Tests

@Suite("DragController long press detection")
struct DragControllerLongPressTests {

    @Test("Hold 0.5s with movement < 10px -> enters jiggling")
    func longPress_0_5s_lowMovement_entersJiggling() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)

        controller.handlePressBegan(at: CGPoint(x: 200, y: 200))
        controller.handleDragMoved(to: CGPoint(x: 205, y: 205))
        mockScheduler.advance(by: 0.5)

        #expect(controller.state == .jiggling)
    }

    @Test("Hold 0.5s with movement > 10px -> enters dragging")
    func longPress_0_5s_highMovement_entersDragging() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)

        controller.handlePressBegan(at: CGPoint(x: 200, y: 200))
        controller.handleDragMoved(to: CGPoint(x: 220, y: 220))
        mockScheduler.advance(by: 0.5)

        #expect(controller.state == .dragging)
    }

    @Test("Hold < 0.5s release -> stays idle")
    func press_shorterThanThreshold_staysIdle() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)

        controller.handlePressBegan(at: CGPoint(x: 200, y: 200))
        mockScheduler.advance(by: 0.3)
        controller.handlePressEnded()

        #expect(controller.state == .idle)
    }

    @Test("Hold 0.5s but release before timer -> timer cancelled, stays idle")
    func press_releasedBeforeTimer_staysIdle() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)

        controller.handlePressBegan(at: CGPoint(x: 200, y: 200))
        mockScheduler.advance(by: 0.4)
        controller.handlePressEnded()

        mockScheduler.advance(by: 0.5)
        #expect(controller.state == .idle)
    }

    @Test("Movement distance exactly 10px -> still enters jiggling (boundary)")
    func longPress_exactlyAtThreshold_entersJiggling() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)

        controller.handlePressBegan(at: CGPoint(x: 200, y: 200))
        controller.handleDragMoved(to: CGPoint(x: 210, y: 200))
        mockScheduler.advance(by: 0.5)

        #expect(controller.state == .jiggling)
    }

    @Test("Movement distance 10.01px -> enters dragging (boundary+1)")
    func longPress_justAboveThreshold_entersDragging() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)

        controller.handlePressBegan(at: CGPoint(x: 200, y: 200))
        controller.handleDragMoved(to: CGPoint(x: 210.01, y: 200))
        mockScheduler.advance(by: 0.5)

        #expect(controller.state == .dragging)
    }

    @Test("长按定时器超阈值（currentPoint 注入）-> 进入 dragging（定时器路径）")
    func longPressTimer_highMovement_entersDragging() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)
        controller.handlePressBegan(at: CGPoint(x: 100, y: 100))
        controller.currentPoint = CGPoint(x: 250, y: 100) // distance 150 > 10
        mockScheduler.advance(by: 0.5)
        #expect(controller.state == .dragging)
    }

    @Test("Already jiggling state, long press callback does not re-trigger")
    func alreadyJiggling_longPressCallback_noop() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)

        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)

        controller.handlePressBegan(at: CGPoint(x: 200, y: 200))
        mockScheduler.advance(by: 0.5)

        #expect(controller.state == .jiggling)
    }
}

// MARK: - Hover Timer Tests

@Suite("DragController hover timers")
struct DragControllerHoverTimerTests {

    private func makeDraggingController(
        scheduler: MockScheduler,
        itemWriter: MockItemWriter = MockItemWriter()
    ) -> DragController {
        let controller = DragController(itemWriter: itemWriter, scheduler: scheduler)
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        return controller
    }

    // MARK: - Edge Hover

    @Test("Dragging hover screen edge 1.5s -> triggers pageChange event")
    func edgeHover_1_5s_triggersPageChange() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onPageChange = { direction in
            state.direction = direction
        }

        controller.updateDragHover(location: .screenEdge)
        mockScheduler.advance(by: 1.5)

        #expect(state.direction != nil)
    }

    @Test("Dragging hover screen edge 1.4s -> no pageChange triggered")
    func edgeHover_1_4s_noPageChange() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onPageChange = { _ in
            state.boolFlag = true
        }

        controller.updateDragHover(location: .screenEdge)
        mockScheduler.advance(by: 1.4)

        #expect(state.boolFlag == false)
    }

    @Test("Edge hover then leave -> timer reset, no pageChange")
    func edgeHover_leave_resetsTimer() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onPageChange = { _ in
            state.boolFlag = true
        }

        controller.updateDragHover(location: .screenEdge)
        mockScheduler.advance(by: 1.0)
        controller.updateDragHover(location: .empty)
        mockScheduler.advance(by: 1.0)

        #expect(state.boolFlag == false)
    }

    @Test("Edge hover -> leave -> re-hover -> restarts 1.5s timer")
    func edgeHover_leave_rehover_restartsTimer() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onPageChange = { _ in
            state.count += 1
        }

        controller.updateDragHover(location: .screenEdge)
        mockScheduler.advance(by: 1.0)
        controller.updateDragHover(location: .empty)
        mockScheduler.advance(by: 0.5)

        controller.updateDragHover(location: .screenEdge)
        mockScheduler.advance(by: 1.0)
        #expect(state.count == 0)

        mockScheduler.advance(by: 0.5)
        #expect(state.count == 1)
    }

    // MARK: - Icon Hover

    @Test("Dragging hover icon 0.8s -> triggers createGroup event")
    func iconHover_0_8s_triggersCreateGroup() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onCreateGroup = { targetId in
            state.targetId = targetId
        }

        controller.updateDragHover(location: .overIcon(targetId: 42))
        mockScheduler.advance(by: 0.8)

        #expect(state.targetId == 42)
    }

    @Test("Dragging hover icon 0.7s -> no createGroup triggered")
    func iconHover_0_7s_noCreateGroup() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onCreateGroup = { _ in
            state.boolFlag = true
        }

        controller.updateDragHover(location: .overIcon(targetId: 42))
        mockScheduler.advance(by: 0.7)

        #expect(state.boolFlag == false)
    }

    @Test("Icon hover then leave -> timer reset")
    func iconHover_leave_resetsTimer() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onCreateGroup = { _ in
            state.boolFlag = true
        }

        controller.updateDragHover(location: .overIcon(targetId: 42))
        mockScheduler.advance(by: 0.5)
        controller.updateDragHover(location: .empty)
        mockScheduler.advance(by: 0.5)

        #expect(state.boolFlag == false)
    }

    @Test("Switch from one icon to another -> timer resets")
    func iconHover_switchTarget_resetsTimer() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onCreateGroup = { targetId in
            state.targetId = targetId
        }

        controller.updateDragHover(location: .overIcon(targetId: 10))
        mockScheduler.advance(by: 0.6)
        controller.updateDragHover(location: .overIcon(targetId: 20))
        mockScheduler.advance(by: 0.6)

        #expect(state.targetId == nil)

        mockScheduler.advance(by: 0.2)
        #expect(state.targetId == 20)
    }

    // MARK: - Non-dragging state does not trigger

    @Test("idle state does not trigger hover timer")
    func idle_hover_noTimer() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)
        let state = SendableState()

        controller.onPageChange = { _ in state.boolFlag = true }
        controller.onCreateGroup = { _ in state.boolFlag = true }

        controller.updateDragHover(location: .screenEdge)
        mockScheduler.advance(by: 2.0)

        #expect(state.boolFlag == false)
    }
}

// MARK: - Drop + Reorder Tests

@Suite("DragController Drop + Reorder")
struct DragControllerDropTests {

    private func makeDraggingController(
        scheduler: MockScheduler,
        itemWriter: MockItemWriter = MockItemWriter()
    ) -> DragController {
        let controller = DragController(itemWriter: itemWriter, scheduler: scheduler)
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        return controller
    }

    @Test("drop -> commits reorder via ItemWriting")
    func drop_commitsReorderViaItemWriter() {
        let mockWriter = MockItemWriter()
        let controller = DragController(itemWriter: mockWriter)

        let originalOrder: [Int64] = [1, 2, 3, 4, 5]
        controller.beginEditing(originalOrder: originalOrder, parentId: 100)

        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()

        controller.simulateReorder(from: 0, to: 3)
        #expect(controller.currentOrder == [2, 3, 4, 1, 5])

        controller.handleDrop()

        #expect(mockWriter.reorderedParentIds.count == 1)
        #expect(mockWriter.reorderedParentIds[0].parentId == 100)
        #expect(mockWriter.reorderedParentIds[0].orderedIds == [2, 3, 4, 1, 5])
    }

    @Test("drop 时 reorderItems 抛错 -> 回滚到原始顺序")
    func drop_reorderThrows_rollsBack() {
        let mockWriter = MockItemWriter()
        mockWriter.reorderError = TestError.generic
        let controller = DragController(itemWriter: mockWriter)
        let original: [Int64] = [1, 2, 3, 4, 5]
        controller.beginEditing(originalOrder: original, parentId: 100)
        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        controller.simulateReorder(from: 0, to: 3)
        #expect(controller.currentOrder != original)
        controller.handleDrop() // commitReorder -> reorderItems 抛错 -> rollbackReorder
        #expect(controller.currentOrder == original)
    }

    @Test("drop returns to idle state")
    func drop_returnsToIdle() {
        let mockWriter = MockItemWriter()
        let controller = DragController(itemWriter: mockWriter)
        controller.beginEditing(originalOrder: [1, 2, 3], parentId: 1)

        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        controller.handleDrop()

        #expect(controller.state == .idle)
    }

    @Test("cross-page drag -> records cross-page move info")
    func crossPageDrop_recordsMove() throws {
        let mockWriter = MockItemWriter()
        let mockScheduler = MockScheduler()
        let sut = DragController(itemWriter: mockWriter, scheduler: mockScheduler)

        sut.beginEditing(originalOrder: [1, 2, 3], parentId: 1)
        sut.handlePressBegan(at: CGPoint(x: 100, y: 100))
        sut.handleDragStart()

        sut.updateDragHover(location: .screenEdge)
        mockScheduler.advance(by: 1.5)
        sut.handleDrop()

        #expect(sut.pendingCrossPageMove != nil)
    }

    @Test("cancel -> restores original order, no ItemWriting call")
    func cancel_restoresOriginalOrder_noWrite() {
        let mockWriter = MockItemWriter()
        let controller = DragController(itemWriter: mockWriter)

        let originalOrder: [Int64] = [1, 2, 3, 4, 5]
        controller.beginEditing(originalOrder: originalOrder, parentId: 100)

        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        controller.simulateReorder(from: 0, to: 4)
        controller.handleCancel()

        #expect(controller.currentOrder == originalOrder)
        #expect(mockWriter.reorderedParentIds.isEmpty)
    }

    @Test("drop without reorder -> no ItemWriting call")
    func drop_withoutReorder_noWrite() {
        let mockWriter = MockItemWriter()
        let controller = DragController(itemWriter: mockWriter)
        controller.beginEditing(originalOrder: [1, 2, 3], parentId: 1)

        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()
        controller.handleDrop()

        #expect(mockWriter.reorderedParentIds.isEmpty)
    }

    @Test("multiple reorder operations -> drop commits final order")
    func multipleReorder_drop_commitsFinalOrder() {
        let mockWriter = MockItemWriter()
        let controller = DragController(itemWriter: mockWriter)
        controller.beginEditing(originalOrder: [1, 2, 3, 4, 5], parentId: 100)

        controller.handleLongPress(movementDistance: 5)
        controller.handleDragStart()

        controller.simulateReorder(from: 0, to: 4)
        controller.simulateReorder(from: 0, to: 3)

        controller.handleDrop()

        #expect(mockWriter.reorderedParentIds.count == 1)
        #expect(mockWriter.reorderedParentIds[0].parentId == 100)
    }

    // MARK: - 边界分支覆盖

    @Test("handleLongPress: state != .idle 时 guard else 早返回（覆盖 L74 guard else）")
    func handleLongPress_notIdle_guardElse() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)
        // 先进入 jiggling 状态
        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)
        // 再次 handleLongPress → state != .idle 走 guard else
        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling) // 状态不变
    }

    @Test("handleLongPress: movementDistance > threshold 时 guard else 早返回（覆盖 L75 guard else）")
    func handleLongPress_movementExceedsThreshold_guardElse() {
        let controller = DragController()
        #expect(controller.state == .idle)
        // movementDistance > 10 → 不进入 jiggling
        controller.handleLongPress(movementDistance: 20)
        #expect(controller.state == .idle)
    }

    @Test("handleDragMoved: state != .idle 时 guard else 早返回（覆盖 L141 guard else）")
    func handleDragMoved_notIdle_guardElse() {
        let mockScheduler = MockScheduler()
        let controller = DragController(scheduler: mockScheduler)
        // 先进入 jiggling
        controller.handlePressBegan(at: .zero)
        controller.handleLongPress(movementDistance: 5)
        #expect(controller.state == .jiggling)
        // handleDragMoved: state != .idle 走 guard else
        controller.handleDragMoved(to: CGPoint(x: 1, y: 1))
        #expect(controller.state == .jiggling)
    }

    @Test("scheduleEdgeHoverTimer: 触发时 draggingSubstate != .overEdge 走 guard else（覆盖 L196）")
    func scheduleEdgeHoverTimer_substateChanged_guardElse() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        var pageChangeCount = 0
        controller.onPageChange = { _ in pageChangeCount += 1 }

        // 先设置 overEdge，触发 timer 注册
        controller.updateDragHover(location: .screenEdge)
        // 在 timer 触发前改变 substate
        controller.updateDragHover(location: .empty)
        // 推进 scheduler 触发原 timer
        mockScheduler.advance(by: 1.5)
        // draggingSubstate 已变为 .empty，不是 .overEdge → guard else
        #expect(pageChangeCount == 0)
    }

    @Test("scheduleIconHoverTimer: 触发时 draggingSubstate 不是 overIcon 走 if-else 分支（覆盖 L208）")
    func scheduleIconHoverTimer_substateChanged_ifElse() {
        let mockScheduler = MockScheduler()
        let controller = makeDraggingController(scheduler: mockScheduler)
        var createGroupCalled = false
        controller.onCreateGroup = { _ in createGroupCalled = true }

        // 先设置 overIcon(42)，触发 timer
        controller.updateDragHover(location: .overIcon(targetId: 42))
        // 在 timer 触发前改变为 overEdge
        controller.updateDragHover(location: .screenEdge)
        // 推进 scheduler 触发原 timer
        mockScheduler.advance(by: 0.8)
        // draggingSubstate 已变为 .overEdge，不匹配 .overIcon → 不触发 onCreateGroup
        #expect(createGroupCalled == false)
    }
}
