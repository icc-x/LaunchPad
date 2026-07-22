import CoreGraphics
import Testing
@testable import LaunchPad

@MainActor
@Suite("NSCollectionView 拖拽手势状态")
struct CollectionViewDragTests {
    @Test("长按不足 0.5 秒保持 idle，release 取消 pending")
    func releaseBeforeLongPressThresholdStaysIdle() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)

        sut.handlePressBegan(at: CGPoint(x: 100, y: 100))
        scheduler.advance(by: 0.49)
        #expect(sut.state == .idle)
        sut.handlePressEnded()
        scheduler.advance(by: 1.0)

        #expect(sut.state == .idle)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("长按 0.5 秒且移动小于阈值进入 jiggling")
    func longPressWithinMovementThresholdEntersJiggling() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)

        sut.handlePressBegan(at: CGPoint(x: 100, y: 100))
        sut.handleDragMoved(to: CGPoint(x: 105, y: 105))
        scheduler.advance(by: 0.5)

        #expect(sut.state == .jiggling)
    }

    @Test("移动恰好 10 点仍进入 jiggling")
    func movementAtThresholdEntersJiggling() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)

        sut.handlePressBegan(at: CGPoint(x: 100, y: 100))
        sut.handleDragMoved(to: CGPoint(x: 110, y: 100))
        scheduler.advance(by: 0.5)

        #expect(sut.state == .jiggling)
    }

    @Test("移动超过 10 点立即进入 gesture-only dragging")
    func movementAboveThresholdEntersDraggingWithoutSession() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)

        sut.handlePressBegan(at: CGPoint(x: 100, y: 100))
        sut.handleDragMoved(to: CGPoint(x: 110.01, y: 100))

        #expect(sut.state == .dragging)
        #expect(sut.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("长按定时器按当前点选择 dragging 分支")
    func timerUsesCurrentMovementForDraggingBranch() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        sut.handlePressBegan(at: CGPoint(x: 100, y: 100))
        sut.currentPoint = CGPoint(x: 120, y: 100)

        scheduler.advance(by: 0.5)

        #expect(sut.state == .dragging)
        #expect(sut.session == nil)
    }

    @Test("非 idle 状态的移动不改变现有状态")
    func movementOutsideIdleDoesNotReenterStateMachine() {
        let sut = DragController(scheduler: MockScheduler())
        sut.handleLongPress(movementDistance: 0)

        sut.handleDragMoved(to: CGPoint(x: 100, y: 100))

        #expect(sut.state == .jiggling)
    }

    @Test("long press 拒绝非 idle 和超阈值重复进入")
    func longPressRejectsRepeatedAndExcessMovementEntry() {
        let sut = DragController(scheduler: MockScheduler())
        sut.handleLongPress(movementDistance: 11)
        #expect(sut.state == .idle)

        sut.handleLongPress(movementDistance: 10)
        sut.handleLongPress(movementDistance: 0)

        #expect(sut.state == .jiggling)
    }

    @Test("drag start 只接受 idle 或 jiggling，重复进入保持 dragging")
    func dragStartAcceptsExpectedStatesOnly() {
        let idleSUT = DragController(scheduler: MockScheduler())
        idleSUT.handleDragStart()
        #expect(idleSUT.state == .dragging)

        let jigglingSUT = DragController(scheduler: MockScheduler())
        jigglingSUT.handleLongPress(movementDistance: 0)
        jigglingSUT.handleDragStart()
        jigglingSUT.handleDragStart()

        #expect(jigglingSUT.state == .dragging)
    }
}
