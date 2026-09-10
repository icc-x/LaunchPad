import Testing
import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif
@testable import LaunchPad

// MARK: - Fake drag controller (implements narrow protocols, no concrete DragController)

@MainActor
private final class FakeDragController: LaunchPadDragControlling, GridDragControlling, FolderDragControlling {
    var state: DragController.DragState = .idle
    var session: DragSession?
    var onPageChange: ((DragPageDirection) -> Void)?
    var onFolderCreationPreviewChanged: ((Int64?) -> Void)?
    private(set) var events: [String] = []

    func handlePressBegan(at point: CGPoint) { events.append("pressBegan") }
    func handleDragMoved(to point: CGPoint) { events.append("dragMoved") }
    func handlePressEnded() { events.append("pressEnded") }
    func finishDrag() { events.append("finish") }
    func cancelDrag() { events.append("cancel") }
    func handleCancel() { events.append("handleCancel") }
    func beginDrag(_ newSession: DragSession) {
        events.append("begin")
        session = newSession
    }
    func updateDragHover(_ destination: DragHoverDestination) {
        events.append("hover")
    }
}

// MARK: - KeyboardKeyCode

@Suite("KeyboardKeyCode 具名键码")
struct KeyboardKeyCodeTests {

    @Test("具名键码值与 Carbon 键码一致")
    func namedValues() {
        #expect(KeyboardKeyCode.returnKey == 36)
        #expect(KeyboardKeyCode.tab == 48)
        #expect(KeyboardKeyCode.space == 49)
        #expect(KeyboardKeyCode.delete == 51)
        #expect(KeyboardKeyCode.escape == 53)
        #expect(KeyboardKeyCode.leftArrow == 123)
        #expect(KeyboardKeyCode.rightArrow == 124)
        #expect(KeyboardKeyCode.downArrow == 125)
        #expect(KeyboardKeyCode.upArrow == 126)
    }

    @Test("navigationKey 映射全部支持按键")
    func navigationKeyMapsAllSupportedKeys() {
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.escape) == .escape)
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.returnKey) == .enter)
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.upArrow) == .upArrow)
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.downArrow) == .downArrow)
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.leftArrow) == .leftArrow)
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.rightArrow) == .rightArrow)
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.tab) == .tab)
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.delete) == .delete)
    }

    @Test("navigationKey 对 space 与未知键码返回 nil")
    func navigationKeyRejectsUnknownKeys() {
        #expect(KeyboardKeyCode.navigationKey(for: KeyboardKeyCode.space) == nil)
        #expect(KeyboardKeyCode.navigationKey(for: 200) == nil)
        #expect(KeyboardKeyCode.navigationKey(for: 0) == nil)
    }
}

// MARK: - Coordinator consumes the narrow grid protocol

@MainActor
@Suite("AppGridInteractionCoordinator 通过窄协议驱动拖拽")
struct CoordinatorNarrowProtocolTests {

    @Test("draggingSession ended 驱动 fake 的 finishDrag")
    func coordinator_endSession_drivesFakeFinish() {
        let fake = FakeDragController()
        let coordinator = AppGridInteractionCoordinator(
            dragController: fake,
            pasteboardUUIDReader: { _ in nil }
        )
        fake.beginDrag(DragSession(
            itemID: 1,
            itemUUID: UUID().uuidString,
            itemType: .app,
            sourceKind: .topLevel,
            sourceParentID: 10,
            sourceVisualIndex: 0
        ))
        coordinator.collectionView(
            NSCollectionView(),
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )
        #expect(fake.events.contains("finish"))
    }

    @Test("draggingSession ended 触发 onDragSessionEnded，供宿主清理抖动态")
    func coordinator_endSession_notifiesHostToClearJiggle() {
        let fake = FakeDragController()
        let coordinator = AppGridInteractionCoordinator(
            dragController: fake,
            pasteboardUUIDReader: { _ in nil }
        )
        var endedCount = 0
        coordinator.onDragSessionEnded = { endedCount += 1 }
        fake.beginDrag(DragSession(
            itemID: 1,
            itemUUID: UUID().uuidString,
            itemType: .app,
            sourceKind: .topLevel,
            sourceParentID: 10,
            sourceVisualIndex: 0
        ))

        coordinator.collectionView(
            NSCollectionView(),
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )

        #expect(endedCount == 1)
    }

    @Test("isDragEnabled 关闭时驱动 fake 的 handleCancel")
    func coordinator_disableDrag_drivesFakeCancel() {
        let fake = FakeDragController()
        let coordinator = AppGridInteractionCoordinator(
            dragController: fake,
            pasteboardUUIDReader: { _ in nil }
        )
        coordinator.isDragEnabled = true
        coordinator.isDragEnabled = false
        #expect(fake.events.contains("handleCancel"))
    }
}

// MARK: - Folder overlay consumes the narrow folder protocol

@MainActor
@Suite("FolderOverlayView 通过窄协议驱动拖拽")
struct FolderNarrowProtocolTests {

    @Test("folder draggingSession ended 驱动 fake 的 finishDrag")
    func folder_endSession_drivesFakeFinish() {
        let fake = FakeDragController()
        let overlay = FolderOverlayView()
        overlay.dragController = fake

        overlay.collectionView(
            NSCollectionView(),
            draggingSession: NSDraggingSession(),
            endedAt: .zero,
            dragOperation: .move
        )
        #expect(fake.events.contains("finish"))
    }
}
