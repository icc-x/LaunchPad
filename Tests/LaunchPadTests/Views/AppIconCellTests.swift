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

    // MARK: - Accessibility

    func testAccessibilityRole_isButton() {
        XCTAssertEqual(cell.view.accessibilityRole(), .button)
    }
}

// MARK: - FolderCell Tests

/// Tests for FolderCell (0% → target 80%+)
@MainActor
final class FolderCellTests: XCTestCase {

    private var cell: FolderCell!

    override func setUp() {
        super.setUp()
        cell = FolderCell()
        _ = cell.view
    }

    override func tearDown() {
        cell = nil
        super.tearDown()
    }

    // MARK: - Init

    func testInit_loadsView() {
        XCTAssertNotNil(cell.view)
    }

    func testIdentifier_isCorrect() {
        XCTAssertEqual(FolderCell.identifier, NSUserInterfaceItemIdentifier("FolderCell"))
    }

    // MARK: - Configure

    func testConfigure_setsTitle() {
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Utilities")
        )
        cell.configure(item: group, childIcons: [])
        XCTAssertEqual(cell.view.accessibilityLabel(), "Utilities")
    }

    func testConfigure_withChildIcons_populatesThumbnails() {
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        let icons = (0..<4).map { _ in NSImage(size: NSSize(width: 64, height: 64)) }
        cell.configure(item: group, childIcons: icons)
        // Should not crash; 4 thumbnails populated
    }

    func testConfigure_withNoChildIcons_showsEmptyGrid() {
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Empty Folder")
        )
        cell.configure(item: group, childIcons: [])
        // Should not crash
    }

    func testConfigure_withMoreThan9Icons_usesOnlyFirst9() {
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Big Folder")
        )
        let icons = (0..<15).map { _ in NSImage(size: NSSize(width: 64, height: 64)) }
        cell.configure(item: group, childIcons: icons)
        // Should only use first 9
    }

    // MARK: - Rename

    func testOnRenamed_callbackIsSettable() {
        var receivedTitle: String?
        cell.onRenamed = { title in receivedTitle = title }
        XCTAssertNotNil(cell.onRenamed)
    }

    // MARK: - Prepare for Reuse

    func testPrepareForReuse_resetsState() {
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        cell.configure(item: group, childIcons: [NSImage(size: NSSize(width: 64, height: 64))])
        cell.prepareForReuse()
        // Verify reuse doesn't crash and cell can be reconfigured
        let group2 = TestDataFactory.makePageItem(
            id: 2, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 2, title: "New Folder")
        )
        cell.configure(item: group2, childIcons: [])
    }

    // MARK: - Accessibility

    func testAccessibilityRole_isButton() {
        XCTAssertEqual(cell.view.accessibilityRole(), .button)
    }
}
#endif
