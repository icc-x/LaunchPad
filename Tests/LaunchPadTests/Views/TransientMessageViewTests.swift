import AppKit
import Testing
@testable import LaunchPad

@MainActor
@Suite("TransientMessageView")
struct TransientMessageViewTests {
    @Test("frame 初始化配置初始隐藏状态和无障碍角色")
    func frameInitializerConfiguresInitialState() {
        let sut = TransientMessageView(frame: .zero)

        #expect(sut.isHidden)
        #expect(sut.message == nil)
        #expect(sut.accessibilityRole() == .staticText)
        #expect(sut.accessibilityLabel() == "")
        #expect(sut.subviews.count == 1)
    }

    @Test("coder 初始化配置初始隐藏状态")
    func coderInitializerConfiguresInitialState() throws {
        let original = TransientMessageView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(original, forKey: "root")
        archiver.finishEncoding()

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
        unarchiver.requiresSecureCoding = false
        let sut = try #require(unarchiver.decodeObject(forKey: "root") as? TransientMessageView)

        #expect(sut.isHidden)
        #expect(sut.message == nil)
        #expect(sut.accessibilityRole() == .staticText)
        #expect(sut.accessibilityLabel() == "")
        #expect(sut.subviews.count == 1)
    }

    @Test("首次 show 转发任意文本、默认时长并发布 high priority announcement")
    func firstShowDisplaysMessageAndPostsAnnouncement() {
        let sut = TransientMessageView(frame: .zero)
        var announcement: (String, Int)?
        var scheduled: (TimeInterval, DispatchWorkItem)?
        sut.postAnnouncement = { announcement = ($0, $1.rawValue) }
        sut.scheduleHide = { delay, item in scheduled = (delay, item) }

        sut.show(message: "调用方提供的任意错误文本")

        #expect(sut.message == "调用方提供的任意错误文本")
        #expect(!sut.isHidden)
        #expect(sut.accessibilityLabel() == "调用方提供的任意错误文本")
        #expect(announcement?.0 == "调用方提供的任意错误文本")
        #expect(announcement?.1 == NSAccessibilityPriorityLevel.high.rawValue)
        #expect(scheduled?.0 == 2.5)
        #expect(scheduled?.1.isCancelled == false)
    }

    @Test("show 精确转发自定义时长")
    func showForwardsCustomDuration() {
        let sut = TransientMessageView(frame: .zero)
        var scheduledDuration: TimeInterval?
        sut.postAnnouncement = { _, _ in }
        sut.scheduleHide = { delay, _ in scheduledDuration = delay }

        sut.show(message: "error", duration: 1.25)

        #expect(scheduledDuration == 1.25)
    }

    @Test("重复 show 取消旧任务并保留新消息")
    func repeatedShowCancelsOldWorkAndReplacesMessage() throws {
        let sut = TransientMessageView(frame: .zero)
        var workItems: [DispatchWorkItem] = []
        sut.postAnnouncement = { _, _ in }
        sut.scheduleHide = { _, item in workItems.append(item) }

        sut.show(message: "first")
        sut.show(message: "second")

        let first = try #require(workItems.first)
        let second = try #require(workItems.last)
        #expect(first.isCancelled)
        #expect(!second.isCancelled)
        #expect(sut.message == "second")
        #expect(!sut.isHidden)
        #expect(sut.accessibilityLabel() == "second")
    }

    @Test("已取消的陈旧任务不能隐藏新消息，当前任务才会隐藏")
    func staleScheduledWorkCannotHideCurrentMessage() throws {
        let sut = TransientMessageView(frame: .zero)
        var workItems: [DispatchWorkItem] = []
        sut.postAnnouncement = { _, _ in }
        sut.scheduleHide = { _, item in workItems.append(item) }

        sut.show(message: "first")
        sut.show(message: "second")

        try #require(workItems.first).perform()

        #expect(sut.message == "second")
        #expect(!sut.isHidden)
        #expect(sut.accessibilityLabel() == "second")

        try #require(workItems.last).perform()

        #expect(sut.message == nil)
        #expect(sut.isHidden)
        #expect(sut.accessibilityLabel() == "")
    }

    @Test("手动 hide 取消 pending work，且重复调用保持幂等")
    func manualHideCancelsPendingWorkAndIsIdempotent() throws {
        let sut = TransientMessageView(frame: .zero)
        var scheduled: DispatchWorkItem?
        sut.postAnnouncement = { _, _ in }
        sut.scheduleHide = { _, item in scheduled = item }
        sut.show(message: "error")

        sut.hide()
        sut.hide()
        try #require(scheduled).perform()

        #expect(try #require(scheduled).isCancelled)
        #expect(sut.message == nil)
        #expect(sut.isHidden)
        #expect(sut.accessibilityLabel() == "")
    }

    @Test("释放视图会取消 pending work，调度闭包不保留视图")
    func deinitializationCancelsPendingWorkWithoutRetainingView() throws {
        var scheduled: DispatchWorkItem?
        weak var releasedView: TransientMessageView?

        autoreleasepool {
            let sut = TransientMessageView(frame: .zero)
            releasedView = sut
            sut.postAnnouncement = { _, _ in }
            sut.scheduleHide = { _, item in scheduled = item }
            sut.show(message: "error")
        }

        #expect(releasedView == nil)
        #expect(try #require(scheduled).isCancelled)
    }

    @Test("无窗口根视图中的 Task 18 约束可解且 fitting size 非零")
    func layoutIsUnambiguousWithTask18Constraints() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        let pageControl = NSView()
        let sut = TransientMessageView(frame: .zero)
        sut.postAnnouncement = { _, _ in }
        sut.scheduleHide = { _, _ in }
        root.addSubview(pageControl)
        root.addSubview(sut)
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        sut.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageControl.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            pageControl.widthAnchor.constraint(equalToConstant: 100),
            pageControl.heightAnchor.constraint(equalToConstant: 16),
            sut.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            sut.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -12),
            sut.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])

        sut.show(message: "布局错误提示")
        root.layoutSubtreeIfNeeded()

        #expect(sut.fittingSize.width > 0)
        #expect(sut.fittingSize.height > 0)
        #expect(!sut.hasAmbiguousLayout)
    }
}
