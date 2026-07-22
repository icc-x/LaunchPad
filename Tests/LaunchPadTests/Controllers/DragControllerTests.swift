import CoreGraphics
import Foundation
import LaunchPadProtocols
import Testing
@testable import LaunchPad

@MainActor
@Suite("DragController immutable drag session")
struct DragControllerTests {
    private func makeSession(
        itemID: Int64 = 11,
        type: ItemType = .app,
        sourceKind: DragSourceKind = .topLevel,
        parentID: Int64 = 100,
        visualIndex: Int = 3
    ) -> DragSession {
        DragSession(
            itemID: itemID,
            itemUUID: "00000000-0000-0000-0000-\(String(format: "%012lld", itemID))",
            itemType: type,
            sourceKind: sourceKind,
            sourceParentID: parentID,
            sourceVisualIndex: visualIndex,
            hoverDestination: nil,
            folderCreationPreviewTargetID: nil
        )
    }

    @Test("更新 hover 产生新会话值，不修改原值")
    func hoverUpdateKeepsOriginalSessionImmutable() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        let original = makeSession()

        sut.beginDrag(original)
        sut.updateDragHover(.item(itemID: 22, itemType: .app))

        #expect(original.hoverDestination == nil)
        #expect(sut.session?.hoverDestination == .item(itemID: 22, itemType: .app))
    }

    @Test("会话保留来源稳定标识")
    func sessionKeepsStableSourceIdentity() {
        let session = makeSession(
            itemID: 12,
            type: .group,
            sourceKind: .folderChild,
            parentID: 88,
            visualIndex: 4
        )

        #expect(session.itemID == 12)
        #expect(session.itemType == .group)
        #expect(session.sourceKind == .folderChild)
        #expect(session.sourceParentID == 88)
        #expect(session.sourceVisualIndex == 4)
    }

    @Test("左右边缘超时分别请求上一页和下一页")
    func edgeHoverUsesActualDirection() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var directions: [DragPageDirection] = []
        sut.onPageChange = { directions.append($0) }
        sut.beginDrag(makeSession())

        sut.updateDragHover(.edge(.backward))
        scheduler.advance(by: 1.5)
        sut.updateDragHover(.edge(.forward))
        scheduler.advance(by: 1.5)

        #expect(directions == [.backward, .forward])
        #expect(sut.session?.hoverDestination == nil)
    }

    @Test("边缘未满 1.5 秒不翻页")
    func edgeHoverBeforeThresholdDoesNotChangePage() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var directions: [DragPageDirection] = []
        sut.onPageChange = { directions.append($0) }
        sut.beginDrag(makeSession())

        sut.updateDragHover(.edge(.forward))
        scheduler.advance(by: 1.4)

        #expect(directions.isEmpty)
        #expect(sut.session?.hoverDestination == .edge(.forward))
    }

    @Test("相同 hover 早返回且不重启定时器")
    func sameHoverReturnsWithoutRestartingTimer() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        sut.beginDrag(makeSession())
        sut.updateDragHover(.edge(.forward))
        let cancelCount = scheduler.cancelCallCount

        sut.updateDragHover(.edge(.forward))

        #expect(scheduler.cancelCallCount == cancelCount)
        #expect(scheduler.scheduledActions.count == 1)
    }

    @Test("过期边缘回调不能翻页")
    func staleEdgeActionCannotChangePage() throws {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var directions: [DragPageDirection] = []
        sut.onPageChange = { directions.append($0) }
        sut.beginDrag(makeSession())
        sut.updateDragHover(.edge(.forward))
        let staleAction = try #require(scheduler.scheduledActions.first?.action)

        sut.updateDragHover(.empty)
        staleAction()

        #expect(directions.isEmpty)
        #expect(sut.session?.hoverDestination == .empty)
    }

    @Test("过期边缘回调不能命中新会话的相同目标")
    func staleEdgeActionCannotMatchReplacementSessionDestination() throws {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var directions: [DragPageDirection] = []
        sut.onPageChange = { directions.append($0) }
        sut.beginDrag(makeSession(itemID: 11))
        sut.updateDragHover(.edge(.forward))
        let staleAction = try #require(scheduler.scheduledActions.first?.action)
        let replacement = makeSession(itemID: 33).updating(
            hoverDestination: .edge(.forward),
            folderCreationPreviewTargetID: nil
        )

        sut.beginDrag(replacement)
        staleAction()

        #expect(directions.isEmpty)
        #expect(sut.session == replacement)
    }

    @Test("翻页回调重入开始新拖拽时不覆写新会话")
    func pageChangeReentryDoesNotOverwriteReplacementSession() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        let replacement = makeSession(itemID: 33).updating(
            hoverDestination: .item(itemID: 44, itemType: .group),
            folderCreationPreviewTargetID: nil
        )
        sut.onPageChange = { _ in sut.beginDrag(replacement) }
        sut.beginDrag(makeSession())

        sut.updateDragHover(.edge(.forward))
        scheduler.advance(by: 1.5)

        #expect(sut.state == .dragging)
        #expect(sut.session == replacement)
    }

    @Test("app-on-app 超时只显示预览，切换和移开会清除")
    func appOnAppTimeoutOnlyShowsPreview() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var previews: [Int64?] = []
        sut.onFolderCreationPreviewChanged = { previews.append($0) }
        sut.beginDrag(makeSession(itemID: 11, type: .app))

        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        scheduler.advance(by: 0.8)
        #expect(sut.session?.folderCreationPreviewTargetID == 22)
        #expect(previews.last == 22)

        sut.updateDragHover(.item(itemID: 33, itemType: .app))
        #expect(previews.last! == nil)
        scheduler.advance(by: 0.8)
        #expect(previews.last == 33)

        sut.updateDragHover(.empty)
        #expect(sut.session?.folderCreationPreviewTargetID == nil)
        #expect(previews.last! == nil)
    }

    @Test("app-on-app 未满 0.8 秒不显示预览")
    func appOnAppBeforeThresholdDoesNotPreview() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        sut.beginDrag(makeSession())

        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        scheduler.advance(by: 0.7)

        #expect(sut.session?.folderCreationPreviewTargetID == nil)
    }

    @Test("过期预览回调不能命中新会话的相同目标")
    func stalePreviewActionCannotMatchReplacementSessionDestination() throws {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var previews: [Int64?] = []
        sut.onFolderCreationPreviewChanged = { previews.append($0) }
        sut.beginDrag(makeSession(itemID: 11))
        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        let staleAction = try #require(scheduler.scheduledActions.first?.action)
        let replacement = makeSession(itemID: 33).updating(
            hoverDestination: .item(itemID: 22, itemType: .app),
            folderCreationPreviewTargetID: nil
        )

        sut.beginDrag(replacement)
        staleAction()

        #expect(previews.isEmpty)
        #expect(sut.session == replacement)
    }

    @Test("拖到自身不创建文件夹预览")
    func selfTargetNeverPreviews() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var previews: [Int64?] = []
        sut.onFolderCreationPreviewChanged = { previews.append($0) }
        sut.beginDrag(makeSession(itemID: 11))

        sut.updateDragHover(.item(itemID: 11, itemType: .app))
        scheduler.advance(by: 0.8)

        #expect(previews.isEmpty)
        #expect(sut.session?.folderCreationPreviewTargetID == nil)
    }

    @Test(arguments: [ItemType.group, ItemType.page])
    func nonAppTargetsNeverPreview(_ targetType: ItemType) {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var preview: Int64?
        sut.onFolderCreationPreviewChanged = { preview = $0 }
        sut.beginDrag(makeSession(type: .app))

        sut.updateDragHover(.item(itemID: 22, itemType: targetType))
        scheduler.advance(by: 0.8)

        #expect(preview == nil)
        #expect(sut.session?.folderCreationPreviewTargetID == nil)
    }

    @Test(arguments: [ItemType.group, ItemType.page])
    func nonAppSourcesNeverPreview(_ sourceType: ItemType) {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var preview: Int64?
        sut.onFolderCreationPreviewChanged = { preview = $0 }
        sut.beginDrag(makeSession(type: sourceType))

        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        scheduler.advance(by: 0.8)

        #expect(preview == nil)
        #expect(sut.session?.folderCreationPreviewTargetID == nil)
    }

    @Test("无会话时 hover 安全无副作用")
    func hoverWithoutSessionIsNoOp() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        sut.handleDragStart()
        #expect(sut.state == .dragging)
        #expect(sut.session == nil)

        sut.updateDragHover(.edge(.forward))

        #expect(sut.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("idle 和 jiggling 状态 hover 安全无副作用")
    func hoverOutsideDraggingIsNoOp() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        sut.updateDragHover(.edge(.forward))
        #expect(scheduler.scheduledActions.isEmpty)

        sut.handleLongPress(movementDistance: 0)
        sut.updateDragHover(.edge(.forward))

        #expect(sut.state == .jiggling)
        #expect(sut.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test(arguments: [true, false])
    func finishAndCancelClearTimerPreviewAndSession(useFinish: Bool) {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var previews: [Int64?] = []
        sut.onFolderCreationPreviewChanged = { previews.append($0) }
        sut.beginDrag(makeSession())
        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        scheduler.advance(by: 0.8)

        if useFinish { sut.finishDrag() } else { sut.cancelDrag() }
        scheduler.advance(by: 2.0)

        #expect(sut.state == .idle)
        #expect(sut.session == nil)
        #expect(previews.last! == nil)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("重复开始会清理旧预览和旧定时器")
    func repeatedBeginClearsPreviousPreviewAndTimer() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var previews: [Int64?] = []
        sut.onFolderCreationPreviewChanged = { previews.append($0) }
        sut.beginDrag(makeSession(itemID: 11))
        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        scheduler.advance(by: 0.8)

        sut.beginDrag(makeSession(itemID: 33))

        #expect(previews.last! == nil)
        #expect(sut.session?.itemID == 33)
        #expect(sut.session?.hoverDestination == nil)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("清除预览回调重入 finish 时不复活旧会话")
    func previewClearReentryDoesNotResurrectSession() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var didReenter = false
        sut.onFolderCreationPreviewChanged = { targetID in
            guard targetID == nil, !didReenter else { return }
            didReenter = true
            sut.finishDrag()
        }
        sut.beginDrag(makeSession())
        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        scheduler.advance(by: 0.8)

        sut.updateDragHover(.item(itemID: 33, itemType: .app))

        #expect(didReenter)
        #expect(sut.state == .idle)
        #expect(sut.session == nil)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("gesture-only legacy hover 只投影兼容子状态")
    func gestureOnlyLegacyHoverOnlyUpdatesCompatibilitySubstate() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var directions: [DragPageDirection] = []
        var previews: [Int64?] = []
        sut.onPageChange = { directions.append($0) }
        sut.onFolderCreationPreviewChanged = { previews.append($0) }
        sut.handleDragStart()

        sut.updateDragHover(location: .overIcon(targetId: 22))
        #expect(sut.draggingSubstate == .overIcon(targetId: 22))
        sut.updateDragHover(location: .screenEdge)
        #expect(sut.draggingSubstate == .none)
        sut.updateDragHover(location: .empty)
        #expect(sut.draggingSubstate == .none)
        scheduler.advance(by: 2.0)

        sut.updateDragHover(location: .overIcon(targetId: 33))
        #expect(sut.draggingSubstate == .overIcon(targetId: 33))
        sut.beginDrag(makeSession())
        #expect(sut.draggingSubstate == .none)
        sut.finishDrag()

        #expect(sut.state == .idle)
        #expect(sut.session == nil)
        #expect(sut.draggingSubstate == .none)
        #expect(directions.isEmpty)
        #expect(previews.isEmpty)
        #expect(scheduler.scheduledActions.isEmpty)
    }

    @Test("native session 的 legacy hover 三分支完全无副作用")
    func nativeSessionLegacyHoverIsNoOp() throws {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        var directions: [DragPageDirection] = []
        var previews: [Int64?] = []
        sut.onPageChange = { directions.append($0) }
        sut.onFolderCreationPreviewChanged = { previews.append($0) }
        sut.beginDrag(makeSession())
        sut.updateDragHover(.item(itemID: 22, itemType: .app))
        scheduler.advance(by: 0.8)

        let expectedSession = try #require(sut.session)
        let expectedState = sut.state
        let expectedSubstate = sut.draggingSubstate
        let expectedPendingIntervals = scheduler.scheduledActions.map(\.interval)
        let expectedCancelCount = scheduler.cancelCallCount
        let expectedDirectionCount = directions.count
        let expectedPreviewCount = previews.count
        #expect(expectedSession.folderCreationPreviewTargetID == 22)
        #expect(previews == [22])

        for location in [
            DragController.HoverLocation.screenEdge,
            .overIcon(targetId: 33),
            .empty,
        ] {
            sut.updateDragHover(location: location)

            #expect(sut.session == expectedSession)
            #expect(sut.state == expectedState)
            #expect(sut.draggingSubstate == expectedSubstate)
            #expect(scheduler.scheduledActions.map(\.interval) == expectedPendingIntervals)
            #expect(scheduler.cancelCallCount == expectedCancelCount)
            #expect(directions.count == expectedDirectionCount)
            #expect(previews.count == expectedPreviewCount)
        }
    }

    @Test("handleCancel 是幂等无写入兼容入口")
    func handleCancelIsIdempotentCompatibilityAlias() {
        let scheduler = MockScheduler()
        let sut = DragController(scheduler: scheduler)
        sut.beginDrag(makeSession())
        sut.updateDragHover(.edge(.forward))

        sut.handleCancel()
        let cancelCount = scheduler.cancelCallCount
        sut.handleCancel()

        #expect(sut.state == .idle)
        #expect(sut.session == nil)
        #expect(scheduler.cancelCallCount == cancelCount)
    }

    @Test("jiggling cancel 和 gesture-only dragging finish 均回到 idle")
    func nonSessionLifecycleCleanupIsSafe() {
        let sut = DragController(scheduler: MockScheduler())
        sut.handleLongPress(movementDistance: 0)
        sut.handleCancel()
        #expect(sut.state == .idle)

        sut.handleDragStart()
        sut.finishDrag()
        #expect(sut.state == .idle)
        #expect(sut.session == nil)
    }
}
