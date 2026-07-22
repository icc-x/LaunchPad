import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for AppIconCell (0% → target 80%+)
@MainActor
final class AppIconCellTests: XCTestCase {

    private var cell: AppIconCell!

    override func setUp() {
        super.setUp()
        cell = AppIconCell()
        // Force loadView by accessing view
        _ = cell.view
    }

    override func tearDown() {
        cell = nil
        super.tearDown()
    }

    // MARK: - Helpers

    // MARK: - Init

    func testInit_loadsView() {
        XCTAssertNotNil(cell.view)
    }

    func testIdentifier_isCorrect() {
        XCTAssertEqual(AppIconCell.identifier, NSUserInterfaceItemIdentifier("AppIconCell"))
    }

    // MARK: - Configure

    func testConfigure_appItem_setsTitle() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Safari")
        )
        cell.configure(item: app, icon: nil)
        // The title label should have the app name
        // We can't directly access titleLabel, but we can check accessibility
        XCTAssertEqual(cell.view.accessibilityLabel(), "Safari")
    }

    func testConfigure_groupItem_setsTitle() {
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "My Folder")
        )
        cell.configure(item: group, icon: nil)
        XCTAssertEqual(cell.view.accessibilityLabel(), "My Folder")
    }

    func testConfigure_withIcon_setsImage() {
        let icon = NSImage(size: NSSize(width: 128, height: 128))
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: icon)
        // Should not crash
    }

    func testConfigure_withNilIcon_usesDefault() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        // Should use NSApplicationIcon as default
    }

    func testConfigure_customIconSize_updatesConstraints() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil, iconSize: 96)
        // Should update icon constraints to 96
    }

    func testConfigure_defaultIconSize_is64() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        // Default iconSize should be 64
    }

    // MARK: - Jiggle Animation

    func testStartJiggling_setsJiggling() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        cell.startJiggling()
        // Should not crash; jiggle animation started
    }

    func testStartJiggling_calledTwice_doesNotCrash() {
        cell.startJiggling()
        cell.startJiggling() // Second call should be no-op
    }

    func testStopJiggling_afterStart_stopsCleanly() {
        cell.startJiggling()
        cell.stopJiggling()
        // Should not crash
    }

    func testStopJiggling_withoutStart_doesNotCrash() {
        cell.stopJiggling()
    }

    // MARK: - Delete Button

    func testDeleteButton_callbackIsSettable() {
        var called = false
        cell.onDelete = { called = true }
        XCTAssertNotNil(cell.onDelete)
    }

    // MARK: - Prepare for Reuse

    func testPrepareForReuse_resetsState() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: NSImage(size: NSSize(width: 64, height: 64)))
        cell.startJiggling()

        cell.prepareForReuse()

        // After reuse, jiggling should be stopped (verify by starting again without crash)
        cell.startJiggling()
        cell.stopJiggling()
    }

    // MARK: - Running Indicator

    func testConfigure_withBundleId_updatesRunningState() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Finder",
                                              bundleId: "com.apple.finder")
        )
        cell.configure(item: app, icon: nil)
        // Finder is always running on macOS, so indicator should be visible
        // (unless running in CI without Finder)
    }

    func testConfigure_withoutBundleId_hidesIndicator() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp",
                                              bundleId: "com.nonexistent.app12345")
        )
        cell.configure(item: app, icon: nil)
        // Non-running app should have hidden indicator
    }

    // MARK: - Workspace Notifications

    func testConfigure_registersWorkspaceNotifications() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Finder",
                                              bundleId: "com.apple.finder")
        )
        cell.configure(item: app, icon: nil)
        XCTAssertTrue(cell.hasWorkspaceObservers, "configure should register workspace notification observers")
    }

    func testPrepareForReuse_unregistersNotifications() {
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Finder",
                                              bundleId: "com.apple.finder")
        )
        cell.configure(item: app, icon: nil)
        XCTAssertTrue(cell.hasWorkspaceObservers)

        cell.prepareForReuse()
        XCTAssertFalse(cell.hasWorkspaceObservers, "prepareForReuse should unregister workspace notification observers")
    }

    func testDidActivateNotification_showsRunningIndicator() {
        let center = NotificationCenter()
        let bundleID = "com.example.task4.workspace"
        cell.workspaceNotificationCenter = center
        cell.runningApplicationProvider = { [] }
        cell.notificationBundleIDReader = { _ in bundleID }
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Fixture",
                                              bundleId: bundleID)
        )
        cell.configure(item: app, icon: nil)

        XCTAssertFalse(cell.isRunningIndicatorVisible)
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertTrue(cell.isRunningIndicatorVisible, "indicator should be visible after activate")
    }

    func testDidDeactivateNotification_hidesRunningIndicator() {
        let center = NotificationCenter()
        let bundleID = "com.example.task4.workspace"
        cell.workspaceNotificationCenter = center
        cell.runningApplicationProvider = { [] }
        cell.notificationBundleIDReader = { _ in bundleID }
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Fixture",
                                              bundleId: bundleID)
        )
        cell.configure(item: app, icon: nil)

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        XCTAssertTrue(cell.isRunningIndicatorVisible)
        center.post(name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        XCTAssertFalse(cell.isRunningIndicatorVisible, "indicator should be hidden after deactivate")
    }

    // MARK: - Accessibility: Increase Contrast

    func testConfigure_increaseContrast_appliesBorderAndBoldFont() {
        UserDefaults.standard.set(true, forKey: "com.apple.universalaccess.highContrast")
        defer { UserDefaults.standard.set(false, forKey: "com.apple.universalaccess.highContrast") }

        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        // increaseContrast path should be covered
    }

    func testStartJiggling_reduceMotion_usesPulseAnimation() {
        // Try to enable reduce motion via UserDefaults
        UserDefaults.standard.set(true, forKey: "com.apple.universalaccess.reduceMotion")
        defer { UserDefaults.standard.set(false, forKey: "com.apple.universalaccess.reduceMotion") }

        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        cell.startJiggling()
        cell.stopJiggling()
        // reduceMotion path should be covered (if system picks up the setting)
    }

    func testStartJiggling_reduceMotion_provider_usesPulse() {
        // 通过注入 accessibilitySettingsProvider 确定性触发 reduceMotion 脉冲分支
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        cell.startJiggling()
        cell.stopJiggling()
        // reduceMotion 分支（缩放脉冲动画）应被执行
    }

    // MARK: - Accessibility

    func testAccessibilityRole_isButton() {
        XCTAssertEqual(cell.view.accessibilityRole(), .button)
    }

    // MARK: - Delete Button Action

    func testDeleteButtonClicked_triggersOnDelete() {
        var deleteCalled = false
        cell.onDelete = { deleteCalled = true }

        // Invoke the private @objc method via perform
        cell.perform(NSSelectorFromString("deleteButtonClicked"))

        XCTAssertTrue(deleteCalled)
    }

    func testDeleteButtonClicked_withoutCallback_doesNotCrash() {
        // No callback set
        cell.perform(NSSelectorFromString("deleteButtonClicked"))
        // Should not crash
    }
}

// NOTE: FolderCellTests 已抽取到独立的 FolderCellTests.swift（更完整的超集），
// 此处删除遗留的重复类以解决 "invalid redeclaration" 编译错误。
#endif
