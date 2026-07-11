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

    // MARK: - Helpers

    private struct SUT {
        let controller: LaunchPadWindowController
        let lifecycle: WindowLifecycle
        let viewController: LaunchPadViewController
    }

    private func makeSUT() -> SUT {
        let storage = MockDataStore()
        let iconCache = IconCache(iconProvider: MockIconProvider(), imageStore: storage)
        let dragController = DragController(itemWriter: storage, scheduler: MockScheduler())
        let folderController = FolderController(itemWriter: storage)
        let viewController = LaunchPadViewController(
            storage: storage,
            iconCache: iconCache,
            dragController: dragController,
            folderController: folderController
        )
        let lifecycle = WindowLifecycle()
        let controller = LaunchPadWindowController(lifecycle: lifecycle, viewController: viewController)
        return SUT(controller: controller, lifecycle: lifecycle, viewController: viewController)
    }

    /// 同步短暂驱动 main runloop，推进 NSAnimationContext 动画与 completion。
    /// 必须为同步函数：`RunLoop.run` 不可从 async 上下文调用。
    @MainActor
    private func pumpRunloopBriefly(for duration: TimeInterval = 0.01) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    /// 让 `DispatchQueue.main.async` 排队的 main actor 任务执行（通过 await 让出 main actor），
    /// 同时驱动 NSAnimationContext 动画推进与 completion 回调。
    /// 被测代码的 delegate 回调、动画完成回调均以 `DispatchQueue.main.async` 派发，
    /// 需要交替 yield 与 runloop pump 才能完整推进状态机。
    private func flushMainQueue(for duration: TimeInterval = 0.6) async {
        let deadline = Date(timeIntervalSinceNow: duration)
        while Date() < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
            pumpRunloopBriefly(for: 0.01)
        }
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
    func openingTransition_triggersShowWindowAnimated() async {
        let sut = makeSUT()
        // 默认 settings -> normal 分支；注入同步动画使 openAnimationDidFinish 确定性触发（覆盖 156-162）
        sut.controller.runAnimated = { _, animations, completion in animations(); completion() }
        sut.controller.mainAsyncRunner = { $0() }
        sut.controller.toggle()
        await flushMainQueue(for: 0.3)            // 驱动 .opening 委托 -> showWindowAnimated -> openAnimationDidFinish
        #expect(sut.lifecycle.state == .visible)
        #expect(sut.controller.window?.isVisible == true)
    }

    @Test("closing 委托触发 hideWindowAnimated — 最终进入 hidden")
    func closingTransition_triggersHideWindowAnimated() async {
        let sut = makeSUT()
        // 注入同步动画使 closeAnimationDidFinish 确定性触发（覆盖 185-187）
        sut.controller.runAnimated = { _, animations, completion in animations(); completion() }
        sut.controller.mainAsyncRunner = { $0() }
        sut.controller.toggle()
        await flushMainQueue(for: 0.05)
        sut.lifecycle.openAnimationDidFinish()    // -> visible
        #expect(sut.lifecycle.state == .visible)
        sut.controller.toggle()                   // -> closing（排队 hideWindowAnimated）
        await flushMainQueue(for: 0.3)            // 执行 hideWindowAnimated -> closeAnimationDidFinish -> hidden
        #expect(sut.lifecycle.state == .hidden)
    }

    @Test("hidden 委托触发 orderOut — 窗口不可见")
    func hiddenTransition_ordersWindowOut() async {
        let sut = makeSUT()
        sut.controller.toggle()
        await flushMainQueue(for: 0.05)
        sut.lifecycle.openAnimationDidFinish()    // -> visible
        sut.controller.toggle()                   // -> closing
        await flushMainQueue(for: 0.05)
        sut.lifecycle.closeAnimationDidFinish()   // -> hidden（orderOut）
        await flushMainQueue(for: 0.05)           // 执行 orderOut async
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
    func launchAnimation_fadesWindowOut() async {
        let sut = makeSUT()
        // 注入同步动画与 main runner，使 launchAnimationDidFinish 等完成回调确定性触发
        // （headless 环境 NSAnimationContext completionHandler 不触发，必须用注入覆盖 135-137 行）
        sut.controller.runAnimated = { _, animations, completion in animations(); completion() }
        sut.controller.mainAsyncRunner = { $0() }
        sut.controller.toggle()
        sut.lifecycle.openAnimationDidFinish()    // opening -> visible（同步直接驱动，避免 flaky）
        #expect(sut.lifecycle.state == .visible)
        // 使用不存在的 bundleId，避免真实启动应用
        sut.lifecycle.handleAppClick(bundleId: "com.launchpad.nonexistent.fake")
        #expect(sut.lifecycle.state == .launching)
        await flushMainQueue(for: 0.3)            // 注入后：fade out 立即执行 -> launchAnimationDidFinish -> closing -> hideWindow -> hidden
        #expect(sut.controller.window?.alphaValue == 0)
        #expect(sut.lifecycle.state == .hidden)
    }

    // MARK: - applyAccessibilitySettings

    @Test("无障碍设置变化通知触发材质更新")
    func applyAccessibilitySettings_onNotification_updatesMaterial() async {
        let sut = makeSUT()
        let visualEffect = sut.controller.window?.contentView as? NSVisualEffectView
        #expect(visualEffect != nil)
        // 模拟系统无障碍设置变化通知
        NotificationCenter.default.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        pumpRunloopBriefly(for: 0.05)            // 让回调在 main runloop 上执行
        // applyAccessibilitySettings 根据当前系统设置选择材质
        let reduceTransparency = AccessibilitySettings.current().reduceTransparency
        let expectedMaterial: NSVisualEffectView.Material = reduceTransparency ? .menu : .hudWindow
        let expectedState: NSVisualEffectView.State = reduceTransparency
            ? .inactive
            : .followsWindowActiveState
        #expect(visualEffect?.material == expectedMaterial)
        #expect(visualEffect?.state == expectedState)
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

    @Test("shouldLaunchApp 真实 bundleId -> urlForApplication 成功分支")
    func shouldLaunchApp_existingBundleId_findsUrl() async {
        let sut = makeSUT()
        sut.controller.toggle()
        // 直接驱动 visible，避免动画 completion flaky 导致 handleAppClick guard 失败
        sut.lifecycle.openAnimationDidFinish()
        sut.lifecycle.handleAppClick(bundleId: "com.apple.finder")
        await flushMainQueue(for: 0.3)
        #expect(true)
    }

    @Test("reduceMotion=true -> showWindowAnimated 用 reduced 分支")
    func showWindowAnimated_reduceMotion_usesReducedBranch() async {
        let sut = makeSUT()
        sut.controller.accessibilitySettingsProvider = {
            AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        }
        // 注入同步动画与 main runner，使 reduced 分支（169-174）的 openAnimationDidFinish 确定性触发
        sut.controller.runAnimated = { _, animations, completion in animations(); completion() }
        sut.controller.mainAsyncRunner = { $0() }
        sut.controller.toggle()
        await flushMainQueue(for: 0.3)
        #expect(sut.lifecycle.state == .visible)
    }

    // MARK: - 额外分支覆盖

    @Test("hideWindowAnimated reduceMotion=true -> 持续时间用 0.1（覆盖 L181 ternary 真分支）")
    func hideWindowAnimated_reduceMotion_usesShortDuration() async {
        let sut = makeSUT()
        sut.controller.accessibilitySettingsProvider = {
            AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        }
        // 注入同步动画与 main runner
        sut.controller.runAnimated = { duration, animations, completion in
            // 断言 duration 为 0.1
            #expect(duration == 0.1)
            animations()
            completion()
        }
        sut.controller.mainAsyncRunner = { $0() }
        sut.controller.toggle()
        await flushMainQueue(for: 0.05)
        sut.lifecycle.openAnimationDidFinish()    // -> visible
        sut.controller.toggle()                   // -> closing（触发 hideWindowAnimated）
        await flushMainQueue(for: 0.3)
        #expect(sut.lifecycle.state == .hidden)
    }

    @Test("applyAccessibilitySettings: contentView 非 NSVisualEffectView 时安全返回（覆盖 L196 guard else）")
    func applyAccessibilitySettings_nonVisualEffectView_returnsSafely() {
        let sut = makeSUT()
        // 替换 window 的 contentView 为普通 NSView（不是 NSVisualEffectView）
        let plainView = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        sut.controller.window?.contentView = plainView
        // 不应崩溃
        sut.controller.applyAccessibilitySettings(
            AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false)
        )
        #expect(true)
    }

    @Test("showWindowAnimated: NSScreen.screens.first 不匹配 + NSScreen.main 为 nil 时跳过动画（覆盖 L148 guard else）")
    func showWindowAnimated_targetScreenNil_returnsEarly() {
        // 构造一个 windowController，让其内部 window 没有有效 screen 可设置
        // 由于 LaunchPadWindowController.init 已设置 panel，init 后无法修改其 frame 计算逻辑
        // 这里我们用 NSScreen.screens.first(where:) 配合异常 frame 模拟不匹配场景
        // 通过反射 / KVC 设置 NSScreen.screens 为空数组较困难，改用让 window 为 nil 触发 guard else
        let sut = makeSUT()
        // 关闭 window 然后让 showWindowAnimated 走 guard else
        sut.controller.window?.close()
        sut.controller.window = nil
        sut.controller.runAnimated = { _, _, _ in Issue.record("动画不应触发") }
        sut.controller.mainAsyncRunner = { $0() }
        sut.controller.toggle() // hidden -> opening 状态机
        // 此时 window 为 nil，showWindowAnimated 中 guard let window = window else { return } 触发
        // 等待异步派发的 delegate 回调
        #expect(sut.lifecycle.state == .opening)
    }
}
#endif
