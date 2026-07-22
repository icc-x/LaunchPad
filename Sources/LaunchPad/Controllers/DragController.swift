import Foundation
import CoreGraphics
import LaunchPadProtocols

/// 拖拽状态机，管理从 idle → jiggling → dragging → idle 的完整生命周期。
@MainActor
public final class DragController {

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

    // MARK: - 公开状态

    public private(set) var state: DragState = .idle
    /// The immutable snapshot for the active native drag, if one has begun.
    public private(set) var session: DragSession?
    public var draggingSubstate: DraggingSubstate {
        guard let session else { return legacyDraggingSubstate }
        switch session.hoverDestination {
        case .edge:
            return .overEdge
        case .item(let itemID, _):
            return .overIcon(targetId: itemID)
        case .empty, nil:
            return .none
        }
    }

    // MARK: - 悬停回调

    /// Called after a directional edge hover reaches its activation threshold.
    public var onPageChange: ((DragPageDirection) -> Void)?
    /// Called when the app-on-app folder preview target changes or is cleared.
    public var onFolderCreationPreviewChanged: ((Int64?) -> Void)?

    // MARK: - 依赖

    private let scheduler: Scheduler
    private var pressStartPoint: CGPoint = .zero
    var currentPoint: CGPoint = .zero
    // Invalidates delayed actions across otherwise value-equal session transitions.
    private var sessionRevision: UInt64 = 0
    // Task 16 compatibility only; this state never arms timers or emits callbacks.
    private var legacyDraggingSubstate: DraggingSubstate = .none

    // MARK: - 初始化

    public init(scheduler: Scheduler = DispatchQueueScheduler()) {
        self.scheduler = scheduler
    }

    // MARK: - 状态转换入口

    public func handleLongPress(movementDistance: CGFloat) {
        guard state == .idle else { return }
        guard movementDistance <= DragController.movementThreshold else { return }
        state = .jiggling
    }

    public func handleDragStart() {
        guard state == .jiggling || state == .idle else { return }
        legacyDraggingSubstate = .none
        state = .dragging
    }

    /// Starts a native drag with a complete immutable source snapshot.
    public func beginDrag(_ session: DragSession) {
        let shouldNotifyPreviewCleared = self.session?.folderCreationPreviewTargetID != nil
        cancelHoverTimer()
        advanceSessionRevision()
        legacyDraggingSubstate = .none
        state = .dragging
        self.session = session
        if shouldNotifyPreviewCleared {
            onFolderCreationPreviewChanged?(nil)
        }
    }

    /// Replaces transient hover state and schedules preview-only hover behavior.
    public func updateDragHover(_ destination: DragHoverDestination) {
        guard state == .dragging,
              let current = session,
              current.hoverDestination != destination else { return }

        cancelHoverTimer()
        let shouldNotifyPreviewCleared = current.folderCreationPreviewTargetID != nil
        let armedSession = current.updating(
            hoverDestination: destination,
            folderCreationPreviewTargetID: nil
        )
        advanceSessionRevision()
        session = armedSession
        let armedRevision = sessionRevision

        switch destination {
        case .edge(let direction):
            scheduler.schedule(after: Self.edgeHoverDuration) { [weak self] in
                guard let self,
                      self.state == .dragging,
                      self.sessionRevision == armedRevision,
                      self.session == armedSession else {
                    return
                }
                self.advanceSessionRevision()
                self.session = armedSession.updating(
                    hoverDestination: nil,
                    folderCreationPreviewTargetID: nil
                )
                self.onPageChange?(direction)
            }

        case .item(let targetID, let targetType):
            if current.itemType == .app,
               targetType == .app,
               current.itemID != targetID {
                scheduler.schedule(after: Self.iconHoverDuration) { [weak self] in
                    guard let self,
                          self.state == .dragging,
                          self.sessionRevision == armedRevision,
                          self.session == armedSession else { return }
                    self.advanceSessionRevision()
                    self.session = armedSession.updating(
                        hoverDestination: armedSession.hoverDestination,
                        folderCreationPreviewTargetID: targetID
                    )
                    self.onFolderCreationPreviewChanged?(targetID)
                }
            }

        case .empty:
            break
        }

        if shouldNotifyPreviewCleared {
            onFolderCreationPreviewChanged?(nil)
        }
    }

    public func updateDragHover(location: HoverLocation) {
        guard state == .dragging else { return }
        guard session != nil else {
            switch location {
            case .screenEdge:
                legacyDraggingSubstate = .none
            case .overIcon(let targetID):
                legacyDraggingSubstate = .overIcon(targetId: targetID)
            case .empty:
                legacyDraggingSubstate = .none
            }
            return
        }
        switch location {
        case .screenEdge:
            // The legacy location has no direction; Task 16 supplies one.
            updateDragHover(.empty)
        case .overIcon(let targetID):
            updateDragHover(.item(itemID: targetID, itemType: .group))
        case .empty:
            updateDragHover(.empty)
        }
    }

    /// Clears all transient drag state without committing a layout mutation.
    public func finishDrag() {
        let shouldNotifyPreviewCleared = session?.folderCreationPreviewTargetID != nil
        advanceSessionRevision()
        session = nil
        resetToIdle()
        if shouldNotifyPreviewCleared {
            onFolderCreationPreviewChanged?(nil)
        }
    }

    /// Cancels the active drag without committing a layout mutation.
    public func cancelDrag() {
        finishDrag()
    }

    public func handleDrop() {
        finishDrag()
    }

    public func handleCancel() {
        guard state != .idle else { return }
        cancelDrag()
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

    // MARK: - 内部实现

    private func calculateMovementDistance() -> CGFloat {
        let dx = currentPoint.x - pressStartPoint.x
        let dy = currentPoint.y - pressStartPoint.y
        return sqrt(dx * dx + dy * dy)
    }

    private func advanceSessionRevision() {
        sessionRevision &+= 1
    }

    private func resetToIdle() {
        scheduler.cancelPending()
        legacyDraggingSubstate = .none
        state = .idle
    }

    // MARK: - 悬停定时器

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
@MainActor
public final class DispatchQueueScheduler: Scheduler {
    private final class PendingWork: @unchecked Sendable {
        private var item: DispatchWorkItem?

        func replace(with newItem: DispatchWorkItem) {
            item?.cancel()
            item = newItem
        }

        func cancel() {
            item?.cancel()
            item = nil
        }

        deinit { item?.cancel() }
    }

    private let pendingWork = PendingWork()
    var workItemObserver: ((DispatchWorkItem) -> Void)?

    public init() {}

    public func schedule(
        after interval: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        cancelPending()
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { action() }
        }
        pendingWork.replace(with: item)
        workItemObserver?(item)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + interval,
            execute: item
        )
    }

    public func cancelPending() {
        pendingWork.cancel()
    }
}
