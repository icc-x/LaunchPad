import Testing
import Foundation
#if canImport(AppKit)
import AppKit

@testable import LaunchPad
import LaunchPadProtocols

@MainActor
@Suite("LaunchPadWindowController 全屏毛玻璃覆盖窗口管理器")
struct LaunchPadWindowControllerTests {

    // MARK: - Test Doubles

    /// 组合存储 mock — 实现 DataStoring（ItemReading + ItemWriting + ImageStoring）
    private final class MockDataStore: DataStoring, @unchecked Sendable {
        var pages: [PageItem] = []
        func fetchAllItems(parentId: Int64?) throws -> [PageItem] { pages }
        func insertItem(_ item: PageItem) throws -> Int64 { item.id }
        func updateItem(_ item: PageItem) throws {}
        func deleteItem(id: Int64) throws {}
        func reorderItems(parentId: Int64, orderedIds: [Int64]) throws {}
        func saveImage(itemId: Int64, icon1x: Data, icon2x: Data) throws {}
        func fetchImage(itemId: Int64) throws -> (Data, Data)? { nil }
    }

    private final class AccessibilitySettingsProviderSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var reads = 0
        private let settings: LaunchPad.AccessibilitySettings

        init(settings: LaunchPad.AccessibilitySettings) {
            self.settings = settings
        }

        func read() -> LaunchPad.AccessibilitySettings {
            lock.lock()
            defer { lock.unlock() }
            reads += 1
            return settings
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return reads
        }
    }

    // MARK: - Helpers

    private struct SUT {
        let controller: LaunchPadWindowController
        let lifecycle: WindowLifecycle
        let viewController: LaunchPadViewController
        let scheduler: MockScheduler
        let accessibilityNotificationCenter: NotificationCenter
    }

    private func makeSUT(
        accessibilitySettingsProvider: @escaping @Sendable ()
            -> LaunchPad.AccessibilitySettings = {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increaseContrast: false
            )
        }
    ) -> SUT {
        let storage = MockDataStore()
        let iconCache = IconCache(iconProvider: MockIconProvider(), imageStore: storage)
        let scheduler = MockScheduler()
        let dragController = DragController(scheduler: scheduler)
        let folderController = FolderController(itemWriter: storage)
        let viewController = LaunchPadViewController(
            storage: storage,
            layoutMutator: MockLayoutMutator(),
            iconCache: iconCache,
            dragController: dragController,
            folderController: folderController,
            applicationOpener: { _ in }
        )
        let lifecycle = WindowLifecycle()
        let notificationCenter = NotificationCenter()
        let controller = LaunchPadWindowController(
            lifecycle: lifecycle,
            viewController: viewController,
            accessibilityNotificationCenter: notificationCenter,
            accessibilitySettingsProvider: accessibilitySettingsProvider
        )
        return SUT(
            controller: controller,
            lifecycle: lifecycle,
            viewController: viewController,
            scheduler: scheduler,
            accessibilityNotificationCenter: notificationCenter
        )
    }

    private func makeSynchronousWindowSUT(
        accessibilitySettingsProvider: @escaping @Sendable ()
            -> LaunchPad.AccessibilitySettings = {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increaseContrast: false
            )
        }
    ) -> SUT {
        let sut = makeSUT(
            accessibilitySettingsProvider: accessibilitySettingsProvider
        )
        sut.controller.mainActorDispatcher = { operation in
            MainActor.assumeIsolated { operation() }
        }
        sut.controller.runAnimated = { _, animations, completion in
            animations()
            completion()
        }
        sut.controller.mainAsyncRunner = { $0() }
        sut.controller.applicationURLProvider = { _ in
            URL(fileURLWithPath: "/Applications/LaunchPad-Test.app")
        }
        sut.controller.applicationOpener = { _ in }
        sut.controller.targetScreenFrameProvider = { _ in
            NSRect(x: 0, y: 0, width: 1440, height: 900)
        }
        return sut
    }

    private func makeSession() -> DragSession {
        DragSession(
            itemID: 10,
            itemUUID: "00000000-0000-0000-0000-000000000010",
            itemType: .app,
            sourceKind: .topLevel,
            sourceParentID: 1,
            sourceVisualIndex: 0
        )
    }

    // MARK: - Init

    @Test("init 后 window 不为 nil")
    func init_windowIsNotNil() {
        let sut = makeSUT()
        #expect(sut.controller.window != nil)
    }

    @Test("init 后 contentView 是 NSVisualEffectView")
    func init_contentViewIsVisualEffect() {
        let sut = makeSUT()
        #expect(sut.controller.window?.contentView is NSVisualEffectView)
    }

    @Test("init 后默认使用 hudWindow 材质")
    func init_defaultMaterialIsHudWindow() {
        let sut = makeSUT()
        let visualEffect = sut.controller.window?.contentView as? NSVisualEffectView
        #expect(visualEffect?.material == .hudWindow)
    }

    @Test("init 后 collectionBehavior 支持全屏与所有空间")
    func init_collectionBehaviorSupportsAllSpaces() {
        let sut = makeSUT()
        let behavior = sut.controller.window?.collectionBehavior ?? []
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.fullScreenAuxiliary))
    }

    @Test("init 后为非激活浮动面板且不随失活隐藏")
    func init_panelIsNonActivatingFloating() {
        let sut = makeSUT()
        let panel = sut.controller.window as? NSPanel
        #expect(panel != nil)
        #expect(panel?.isFloatingPanel == true)
        #expect(panel?.hidesOnDeactivate == false)
    }

    // MARK: - toggle / escape 状态转换

    @Test("hidden 状态 toggle -> 转为 opening")
    func toggle_fromHidden_transitionsToOpening() {
        let sut = makeSUT()
        #expect(sut.lifecycle.state == .hidden)
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .opening)
    }

    @Test("opening 状态再次 toggle -> 被忽略（防抖）")
    func toggle_fromOpening_isDebounced() {
        let sut = makeSUT()
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .opening)
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .opening)
    }

    @Test("hidden 状态 escape -> 无操作")
    func escape_fromHidden_isNoOp() {
        let sut = makeSUT()
        sut.controller.escape()
        #expect(sut.lifecycle.state == .hidden)
    }

    @Test("visible 状态 escape -> 转为 closing")
    func escape_fromVisible_transitionsToClosing() {
        let sut = makeSUT()
        sut.controller.toggle()                   // hidden -> opening
        sut.lifecycle.openAnimationDidFinish()    // opening -> visible
        sut.controller.escape()
        #expect(sut.lifecycle.state == .closing)
    }

    // MARK: - WindowLifecycleDelegate -> 窗口动画

    @Test("opening 委托触发 showWindowAnimated（normal 分支）— 动画完成后进入 visible 且窗口可见")
    func openingTransition_triggersShowWindowAnimated() {
        let sut = makeSynchronousWindowSUT()
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .visible)
        #expect(sut.controller.window?.isVisible == true)
    }

    @Test("closing 委托触发 hideWindowAnimated — 最终进入 hidden")
    func closingTransition_triggersHideWindowAnimated() {
        let sut = makeSynchronousWindowSUT()
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .visible)
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .hidden)
    }

    @Test("hidden 委托触发 orderOut — 窗口不可见")
    func hiddenTransition_ordersWindowOut() {
        let sut = makeSynchronousWindowSUT()
        sut.controller.toggle()
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .hidden)
        #expect(sut.controller.window?.isVisible == false)
    }

    // MARK: - windowDidResignKey

    @Test("visible 状态窗口失焦 -> 触发关闭")
    func windowDidResignKey_whenVisible_triggersClosing() {
        let sut = makeSUT()
        sut.controller.toggle()
        sut.lifecycle.openAnimationDidFinish()    // -> visible
        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: sut.controller.window
        )
        #expect(sut.lifecycle.state == .closing)
    }

    @Test("非 visible 状态窗口失焦 -> 无操作")
    func windowDidResignKey_whenNotVisible_isNoOp() {
        let sut = makeSUT()
        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: sut.controller.window
        )
        #expect(sut.lifecycle.state == .hidden)
    }

    // MARK: - lifecycleRequestsLaunchAnimation

    @Test("启动动画将窗口淡出至 alphaValue=0 并最终回到 hidden")
    func launchAnimation_fadesWindowOut() {
        let sut = makeSynchronousWindowSUT()
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .visible)
        sut.lifecycle.handleAppClick(bundleId: "com.launchpad.nonexistent.fake")
        #expect(sut.controller.window?.alphaValue == 0)
        #expect(sut.lifecycle.state == .hidden)
    }

    // MARK: - applyAccessibilitySettings

    @Test("无障碍设置变化通知触发材质更新")
    func applyAccessibilitySettings_onNotification_updatesMaterial() {
        let sut = makeSUT {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: true,
                increaseContrast: true
            )
        }
        let visualEffect = sut.controller.window?.contentView as? NSVisualEffectView
        #expect(visualEffect != nil)
        sut.accessibilityNotificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        #expect(visualEffect?.material == .menu)
        #expect(visualEffect?.state == .inactive)
    }

    @Test("init(coder:) 返回 nil（不支持 NSCoding）")
    func initCoder_returnsNil() {
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.finishEncoding()
        let data = archiver.encodedData
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return }
        let result = LaunchPadWindowController(coder: coder)
        #expect(result == nil)
    }

    @Test("reduceTransparency=true -> applyAccessibilitySettings 用 solidColor 材质")
    func applyAccessibilitySettings_reduceTransparency_usesSolidColor() {
        let sut = makeSUT()
        let settings = AccessibilitySettings(reduceMotion: false, reduceTransparency: true, increaseContrast: false)
        sut.controller.applyAccessibilitySettings(settings)
        let visualEffect = sut.controller.window?.contentView as? NSVisualEffectView
        #expect(visualEffect?.material == .menu)
        #expect(visualEffect?.state == .inactive)
    }

    @Test("launch request 使用注入 URL 并只调用一次 opener")
    func launchRequestUsesInjectedApplicationBoundary() {
        let sut = makeSynchronousWindowSUT()
        let expected = URL(fileURLWithPath: "/Applications/Target.app")
        var requestedBundleID: String?
        var openedURLs: [URL] = []
        sut.controller.applicationURLProvider = {
            requestedBundleID = $0
            return expected
        }
        sut.controller.applicationOpener = { openedURLs.append($0) }

        sut.controller.lifecycle(
            sut.lifecycle,
            shouldLaunchApp: "com.test.target"
        )

        #expect(requestedBundleID == "com.test.target")
        #expect(openedURLs == [expected])
    }

    @Test("launch request URL 缺失时不调用 opener")
    func launchRequestWithMissingURLDoesNotOpen() {
        let sut = makeSynchronousWindowSUT()
        var requestedBundleIDs: [String] = []
        var openedURLs: [URL] = []
        sut.controller.applicationURLProvider = {
            requestedBundleIDs.append($0)
            return nil
        }
        sut.controller.applicationOpener = { openedURLs.append($0) }

        sut.controller.lifecycle(
            sut.lifecycle,
            shouldLaunchApp: "com.test.missing"
        )

        #expect(requestedBundleIDs == ["com.test.missing"])
        #expect(openedURLs.isEmpty)
    }

    @Test("reduceMotion=true -> showWindowAnimated 用 reduced 分支")
    func showWindowAnimated_reduceMotion_usesReducedBranch() {
        let sut = makeSynchronousWindowSUT {
            AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        }
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .visible)
    }

    @Test("initializer settings provider 同时驱动 opening 和 closing 动画")
    func initializerSettingsProviderDrivesBothAnimations() {
        var durations: [TimeInterval] = []
        let provider = AccessibilitySettingsProviderSpy(
            settings: AccessibilitySettings(
                reduceMotion: true,
                reduceTransparency: false,
                increaseContrast: false
            )
        )
        let sut = makeSynchronousWindowSUT(
            accessibilitySettingsProvider: provider.read
        )
        sut.controller.runAnimated = { duration, animations, completion in
            durations.append(duration)
            animations()
            completion()
        }

        sut.controller.toggle()
        #expect(sut.lifecycle.state == .visible)
        sut.controller.toggle()

        #expect(sut.lifecycle.state == .hidden)
        #expect(provider.callCount == 2)
        #expect(durations == [0.1, 0.1])
    }

    // MARK: - 额外分支覆盖

    @Test("hideWindowAnimated reduceMotion=true -> 持续时间用 0.1（覆盖 L181 ternary 真分支）")
    func hideWindowAnimated_reduceMotion_usesShortDuration() {
        let sut = makeSynchronousWindowSUT {
            AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        }
        sut.controller.runAnimated = { duration, animations, completion in
            #expect(duration == 0.1)
            animations()
            completion()
        }
        sut.controller.toggle()
        sut.controller.toggle()
        #expect(sut.lifecycle.state == .hidden)
    }

    @Test("applyAccessibilitySettings: contentView 非 NSVisualEffectView 时安全返回（覆盖 L196 guard else）")
    func applyAccessibilitySettings_nonVisualEffectView_returnsSafely() {
        let sut = makeSUT()
        // 替换 window 的 contentView 为普通 NSView（不是 NSVisualEffectView）
        let plainView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        plainView.alphaValue = 0.42
        sut.controller.window?.contentView = plainView

        sut.controller.applyAccessibilitySettings(
            AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false)
        )

        #expect(sut.controller.window?.contentView === plainView)
        #expect(plainView.alphaValue == 0.42)
    }

    @Test("showWindowAnimated: target frame 缺失时跳过动画")
    func showWindowAnimated_targetScreenNil_returnsEarly() {
        let sut = makeSUT()
        sut.controller.targetScreenFrameProvider = { _ in nil }
        sut.controller.runAnimated = { _, _, _ in Issue.record("动画不应触发") }
        sut.controller.mainActorDispatcher = { operation in
            MainActor.assumeIsolated { operation() }
        }

        sut.controller.toggle()

        #expect(sut.lifecycle.state == .opening)
        #expect(sut.controller.window?.isVisible == false)
    }

    @Test("窗口进入 closing 会清理活动拖拽")
    func closingWindowClearsDragSession() {
        let sut = makeSynchronousWindowSUT()
        var previewChanges: [Int64?] = []
        sut.viewController.dragController.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        sut.viewController.dragController.beginDrag(makeSession())
        sut.viewController.dragController.updateDragHover(
            .item(itemID: 11, itemType: .app)
        )
        sut.scheduler.advance(by: 0.8)
        #expect(
            sut.viewController.dragController.session?
                .folderCreationPreviewTargetID == 11
        )
        sut.viewController.dragController.handlePressBegan(at: .zero)
        #expect(!sut.scheduler.scheduledActions.isEmpty)

        sut.controller.lifecycle(sut.lifecycle, didTransitionTo: .closing)

        #expect(sut.viewController.dragController.session == nil)
        #expect(sut.viewController.dragController.state == .idle)
        #expect(sut.scheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))
    }

    @Test("窗口进入 hidden 会清理活动拖拽并重载")
    func hiddenWindowClearsDragSession() {
        let sut = makeSynchronousWindowSUT()
        var previewChanges: [Int64?] = []
        sut.viewController.dragController.onFolderCreationPreviewChanged = {
            previewChanges.append($0)
        }
        sut.viewController.dragController.beginDrag(makeSession())
        sut.viewController.dragController.updateDragHover(
            .item(itemID: 11, itemType: .app)
        )
        sut.scheduler.advance(by: 0.8)
        #expect(
            sut.viewController.dragController.session?
                .folderCreationPreviewTargetID == 11
        )
        sut.viewController.dragController.handlePressBegan(at: .zero)
        #expect(!sut.scheduler.scheduledActions.isEmpty)

        sut.controller.lifecycle(sut.lifecycle, didTransitionTo: .hidden)

        #expect(sut.viewController.dragController.session == nil)
        #expect(sut.viewController.dragController.state == .idle)
        #expect(sut.scheduler.scheduledActions.isEmpty)
        #expect(previewChanges.last == .some(nil))
        #expect(sut.controller.window?.isVisible == false)
    }
}
#endif
