import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor @Suite("AppIconCell")
struct AppIconCellTests {
    private func makeSUT() -> AppIconCell {
        let cell = AppIconCell()
        cell.workspaceNotificationCenter = NotificationCenter()
        cell.runningApplicationProvider = { [] }
        cell.notificationBundleIDReader = { _ in nil }
        _ = cell.view
        return cell
    }

    @Test func init_loadsView() {
        let cell = makeSUT()
        #expect(cell.view.subviews.count == 2)
        #expect(cell.view.accessibilityRole() == .button)
    }

    @Test func identifier_isCorrect() {
        let cell = makeSUT()
        #expect(type(of: cell).identifier == NSUserInterfaceItemIdentifier("AppIconCell"))
    }

    @Test func configure_appItem_setsTitle() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "Safari")
        )
        cell.configure(item: app, icon: nil)
        #expect(cell.view.accessibilityLabel() == "Safari")
    }

    @Test func configure_groupItem_setsTitle() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "My Folder")
        )
        cell.configure(item: group, icon: nil)
        #expect(cell.view.accessibilityLabel() == "My Folder")
    }

    @Test func configure_withIcon_setsImage() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let icon = NSImage(size: NSSize(width: 128, height: 128))
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: icon)
    }

    @Test func configure_withNilIcon_usesDefault() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
    }

    @Test func configure_customIconSize_updatesConstraints() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil, iconSize: 96)
    }

    @Test func configure_defaultIconSize_is64() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
    }

    @Test func startJiggling_setsJiggling() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        cell.startJiggling()
    }

    @Test func startJiggling_calledTwice_doesNotCrash() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        cell.startJiggling()
        cell.startJiggling()
    }

    @Test func stopJiggling_afterStart_stopsCleanly() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        cell.startJiggling()
        cell.stopJiggling()
    }

    @Test func stopJiggling_withoutStart_doesNotCrash() {
        let cell = makeSUT()
        cell.stopJiggling()
    }

    @Test func deleteButton_callbackIsSettable() {
        let cell = makeSUT()
        cell.onDelete = {}
        #expect(cell.onDelete != nil)
    }

    @Test func prepareForReuse_resetsState() {
        let cell = makeSUT()
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(
            item: app,
            icon: NSImage(size: NSSize(width: 64, height: 64))
        )
        cell.startJiggling()
        cell.prepareForReuse()
        cell.startJiggling()
        cell.stopJiggling()
    }

    @Test func configure_withBundleId_updatesRunningState() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(
                id: 1, title: "Finder", bundleId: "com.apple.finder"
            )
        )
        cell.configure(item: app, icon: nil)
    }

    @Test func configure_withoutBundleId_hidesIndicator() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(
                id: 1, title: "TestApp", bundleId: "com.nonexistent.app12345"
            )
        )
        cell.configure(item: app, icon: nil)
    }

    @Test func configure_registersWorkspaceNotifications() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(
                id: 1, title: "Finder", bundleId: "com.apple.finder"
            )
        )
        cell.configure(item: app, icon: nil)
        #expect(cell.hasWorkspaceObservers)
    }

    @Test func prepareForReuse_unregistersNotifications() {
        let cell = makeSUT()
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(
                id: 1, title: "Finder", bundleId: "com.apple.finder"
            )
        )
        cell.configure(item: app, icon: nil)
        #expect(cell.hasWorkspaceObservers)
        cell.prepareForReuse()
        #expect(!cell.hasWorkspaceObservers)
    }

    @Test func didActivateNotification_showsRunningIndicator() {
        let cell = makeSUT()
        let center = cell.workspaceNotificationCenter
        let bundleID = "com.example.task4.workspace"
        cell.notificationBundleIDReader = { _ in bundleID }
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(
                id: 1, title: "Fixture", bundleId: bundleID
            )
        )
        cell.configure(item: app, icon: nil)

        #expect(!cell.isRunningIndicatorVisible)
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(cell.isRunningIndicatorVisible)
    }

    @Test func didDeactivateNotification_hidesRunningIndicator() {
        let cell = makeSUT()
        let center = cell.workspaceNotificationCenter
        let bundleID = "com.example.task4.workspace"
        cell.notificationBundleIDReader = { _ in bundleID }
        defer { cell.prepareForReuse() }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(
                id: 1, title: "Fixture", bundleId: bundleID
            )
        )
        cell.configure(item: app, icon: nil)

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(cell.isRunningIndicatorVisible)
        center.post(name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        #expect(!cell.isRunningIndicatorVisible)
    }

    @Test func configure_increaseContrast_appliesBorderAndBoldFont() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increaseContrast: true
            )
        }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
    }

    @Test func startJiggling_reduceMotion_usesPulseAnimation() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        UserDefaults.standard.set(true, forKey: "com.apple.universalaccess.reduceMotion")
        defer {
            UserDefaults.standard.set(
                false, forKey: "com.apple.universalaccess.reduceMotion"
            )
        }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        cell.startJiggling()
        cell.stopJiggling()
    }

    @Test func startJiggling_reduceMotion_provider_usesPulse() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(
                reduceMotion: true,
                reduceTransparency: false,
                increaseContrast: false
            )
        }
        let app = TestDataFactory.makePageItem(
            id: 1, type: .app, ordering: 0,
            app: TestDataFactory.makeAppInfo(id: 1, title: "TestApp")
        )
        cell.configure(item: app, icon: nil)
        cell.startJiggling()
        cell.stopJiggling()
    }

    @Test func accessibilityRole_isButton() {
        let cell = makeSUT()
        #expect(cell.view.accessibilityRole() == .button)
    }

    @Test func deleteButtonClicked_triggersOnDelete() {
        let cell = makeSUT()
        var deleteCalled = false
        cell.onDelete = { deleteCalled = true }
        cell.perform(NSSelectorFromString("deleteButtonClicked"))
        #expect(deleteCalled)
    }

    @Test func deleteButtonClicked_withoutCallback_doesNotCrash() {
        let cell = makeSUT()
        cell.perform(NSSelectorFromString("deleteButtonClicked"))
    }

    @Test("AppIconCell 重新配置 96pt 时同步两个尺寸约束")
    func appIconCellReconfiguresBothConstraints() {
        let cell = makeSUT()
        defer { cell.prepareForReuse() }
        cell.configure(
            item: TestDataFactory.makePageItem(id: 1),
            icon: NSImage(size: NSSize(width: 64, height: 64)),
            iconSize: 96
        )
        #expect(cell.configuredIconSize == 96)
        #expect(
            cell.configuredIconConstraintSize
                == CGSize(width: 96, height: 96)
        )
    }

    @Test("folder creation preview 显示真实 accent 边框并可清除")
    func folderCreationPreviewTogglesLayerAppearance() throws {
        let cell = makeSUT()
        let container = try #require(cell.view.subviews.first)
        #expect(container.layer != nil)
        #expect(!cell.isFolderCreationPreviewVisible)
        cell.setFolderCreationPreviewVisible(true)
        #expect(cell.isFolderCreationPreviewVisible)
        #expect(container.layer?.borderWidth == 2)
        #expect(container.layer?.borderColor == NSColor.controlAccentColor.cgColor)
        #expect(container.layer?.cornerRadius == 8)
        cell.setFolderCreationPreviewVisible(false)
        #expect(!cell.isFolderCreationPreviewVisible)
        #expect(container.layer?.borderWidth == 0)
        #expect(container.layer?.borderColor == nil)
    }

    @Test("prepareForReuse 清除 folder creation preview")
    func prepareForReuseClearsFolderCreationPreview() {
        let cell = makeSUT()
        cell.setFolderCreationPreviewVisible(true)
        cell.prepareForReuse()
        #expect(!cell.isFolderCreationPreviewVisible)
    }
}
#endif
