import Foundation
import CoreGraphics
import LaunchPadProtocols

/// 拖拽状态机，管理从 idle → jiggling → dragging → idle 的完整生命周期
public final class DragController: @unchecked Sendable {

    // MARK: - 状态定义

    public enum DragState: Equatable {
        case idle
        case jiggling
        case dragging
    }

    public enum DraggingSubstate: Equatable {
        case none
        case overEdge
        case overIcon(targetId: Int64)
    }

    public enum HoverLocation: Equatable {
        case screenEdge
        case overIcon(targetId: Int64)
        case empty
    }

    public enum PageChangeDirection: Equatable {
        case forward
        case backward
    }

    // MARK: - 公开状态

    public private(set) var state: DragState = .idle
    public private(set) var draggingSubstate: DraggingSubstate = .none
    public private(set) var currentOrder: [Int64] = []
    public private(set) var pendingCrossPageMove: (itemId: Int64, fromPage: Int64, toPage: Int64)?

    private var originalOrder: [Int64] = []
    private var editingParentId: Int64 = 0

    // MARK: - 悬停回调

    public var onPageChange: ((PageChangeDirection) -> Void)?
    public var onCreateGroup: ((Int64) -> Void)?

    // MARK: - 依赖

    private let itemWriter: ItemWriting?
    private let scheduler: Scheduler
    private var pressStartPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var lastHoverLocation: HoverLocation = .empty

    // MARK: - 初始化

    public init(itemWriter: ItemWriting? = nil, scheduler: Scheduler = DispatchQueueScheduler()) {
        self.itemWriter = itemWriter
        self.scheduler = scheduler
    }

    // MARK: - 编辑模式管理

    public func beginEditing(originalOrder: [Int64], parentId: Int64? = nil) {
        self.originalOrder = originalOrder
        self.currentOrder = originalOrder
        self.editingParentId = parentId ?? 0
    }

    // MARK: - 状态转换入口

    public func handleLongPress(movementDistance: CGFloat) {
        guard state == .idle else { return }
        guard movementDistance <= DragController.movementThreshold else { return }
        state = .jiggling
    }

    public func handleDragStart() {
        guard state == .jiggling || state == .idle else { return }
        state = .dragging
        draggingSubstate = .none
    }

    public func updateDragHover(location: HoverLocation) {
        guard state == .dragging else { return }

        if location == lastHoverLocation { return }
        lastHoverLocation = location

        cancelHoverTimer()

        switch location {
        case .screenEdge:
            draggingSubstate = .overEdge
            scheduleEdgeHoverTimer()
        case .overIcon(let targetId):
            draggingSubstate = .overIcon(targetId: targetId)
            scheduleIconHoverTimer(targetId: targetId)
        case .empty:
            draggingSubstate = .none
        }
    }

    public func handleDrop() {
        guard state == .dragging else { return }
        commitReorder()
        resetToIdle()
    }

    public func handleCancel() {
        switch state {
        case .idle:
            return
        case .jiggling:
            resetToIdle()
        case .dragging:
            rollbackReorder()
            resetToIdle()
        }
    }

    // MARK: - 手势生命周期

    public func handlePressBegan(at point: CGPoint) {
        pressStartPoint = point
        currentPoint = point
        scheduler.schedule(after: DragController.longPressDuration) { [weak self] in
            guard let self, self.state == .idle else { return }
            let distance = self.calculateMovementDistance()
            if distance > DragController.movementThreshold {
                self.handleDragStart()
            } else {
                self.handleLongPress(movementDistance: distance)
            }
        }
    }

    public func handleDragMoved(to point: CGPoint) {
        currentPoint = point
        guard state == .idle else { return }
        let distance = calculateMovementDistance()
        if distance > DragController.movementThreshold {
            scheduler.cancelPending()
            handleDragStart()
        }
    }

    public func handlePressEnded() {
        scheduler.cancelPending()
    }

    // MARK: - 模拟重排（测试用）

    public func simulateReorder(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < currentOrder.count,
              destinationIndex >= 0, destinationIndex < currentOrder.count else { return }
        let item = currentOrder.remove(at: sourceIndex)
        currentOrder.insert(item, at: destinationIndex)
    }

    // MARK: - 内部实现

    private func calculateMovementDistance() -> CGFloat {
        let dx = currentPoint.x - pressStartPoint.x
        let dy = currentPoint.y - pressStartPoint.y
        return sqrt(dx * dx + dy * dy)
    }

    private func commitReorder() {
        guard currentOrder != originalOrder else { return }
        do {
            try itemWriter?.reorderItems(parentId: editingParentId, orderedIds: currentOrder)
        } catch {
            rollbackReorder()
        }
    }

    private func rollbackReorder() {
        currentOrder = originalOrder
    }

    private func resetToIdle() {
        state = .idle
        draggingSubstate = .none
        lastHoverLocation = .empty
        cancelHoverTimer()
    }

    // MARK: - 悬停定时器

    private func scheduleEdgeHoverTimer() {
        scheduler.schedule(after: DragController.edgeHoverDuration) { [weak self] in
            guard let self, self.state == .dragging,
                  self.draggingSubstate == .overEdge else { return }
            self.pendingCrossPageMove = (
                itemId: 0,
                fromPage: self.editingParentId,
                toPage: 0
            )
            self.onPageChange?(.forward)
        }
    }

    private func scheduleIconHoverTimer(targetId: Int64) {
        scheduler.schedule(after: DragController.iconHoverDuration) { [weak self] in
            guard let self, self.state == .dragging else { return }
            if case .overIcon(let currentId) = self.draggingSubstate,
               currentId == targetId {
                self.onCreateGroup?(targetId)
            }
        }
    }

    private func cancelHoverTimer() {
        scheduler.cancelPending()
    }

    // MARK: - 常量

    static let longPressDuration: TimeInterval = 0.5
    static let movementThreshold: CGFloat = 10.0
    static let edgeHoverDuration: TimeInterval = 1.5
    static let iconHoverDuration: TimeInterval = 0.8
}

/// 生产环境调度器
public final class DispatchQueueScheduler: Scheduler, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.launchpad.scheduler", qos: .userInitiated)
    private var currentWorkItem: DispatchWorkItem?
    private let lock = NSLock()

    public init() {}

    public func schedule(after interval: TimeInterval, action: @escaping @Sendable () -> Void) {
        lock.lock()
        currentWorkItem?.cancel()
        let workItem = DispatchWorkItem(block: action)
        currentWorkItem = workItem
        lock.unlock()
        queue.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    public func cancelPending() {
        lock.lock()
        currentWorkItem?.cancel()
        currentWorkItem = nil
        lock.unlock()
    }
}
