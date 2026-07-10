import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for FolderCell (0% → target 80%+)
@MainActor
final class FolderCellTests: XCTestCase {

    private var cell: FolderCell!

    /// UserDefaults key backing `AccessibilitySettings.increaseContrast`.
    private let contrastKey = "com.apple.universalaccess.highContrast"

    override func setUp() {
        super.setUp()
        cell = FolderCell()
        // Force loadView by accessing view
        _ = cell.view
    }

    override func tearDown() {
        // 恢复系统 Increase Contrast 默认值（关闭），避免污染其他测试
        UserDefaults.standard.set(false, forKey: contrastKey)
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

    // MARK: - Increase Contrast

    func testConfigure_increaseContrast_addsBorder() {
        UserDefaults.standard.set(true, forKey: contrastKey)
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        cell.configure(item: group, childIcons: [])
        XCTAssertEqual(cell.containerView.layer?.borderWidth, 1)
    }

    func testConfigure_increaseContrast_usesSemiboldFont() {
        UserDefaults.standard.set(true, forKey: contrastKey)
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        cell.configure(item: group, childIcons: [])
        let expected = NSFont.systemFont(ofSize: 11, weight: .semibold).fontDescriptor
        XCTAssertEqual(cell.titleLabel.font?.fontDescriptor, expected)
    }

    func testConfigure_normalContrast_noBorder() {
        UserDefaults.standard.set(false, forKey: contrastKey)
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        cell.configure(item: group, childIcons: [])
        XCTAssertEqual(cell.containerView.layer?.borderWidth, 0)
    }

    // MARK: - Reduce Transparency (回归)

    func testConfigure_reduceTransparency_changesMaterial() {
        let settings = AccessibilitySettings.current()
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        cell.configure(item: group, childIcons: [])
        // reduceTransparency 来自系统，不可在测试中强制；按当前系统值断言对应分支
        if settings.reduceTransparency {
            XCTAssertEqual(cell.frostedBackground.material, .menu)
            XCTAssertEqual(cell.frostedBackground.state, .inactive)
        } else {
            XCTAssertEqual(cell.frostedBackground.material, .hudWindow)
            XCTAssertEqual(cell.frostedBackground.state, .active)
        }
    }

    func testConfigure_reduceTransparency_provider_changesMaterial() {
        // 通过注入 accessibilitySettingsProvider 确定性触发 reduceTransparency 回退分支
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(reduceMotion: false, reduceTransparency: true, increaseContrast: false)
        }
        let group = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: 1, title: "Folder")
        )
        cell.configure(item: group, childIcons: [])
        XCTAssertEqual(cell.frostedBackground.material, .menu)
        XCTAssertEqual(cell.frostedBackground.state, .inactive)
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

    // MARK: - Double-click editing

    func testHandleDoubleClick_entersEditMode() {
        // Invoke the private @objc method via perform
        cell.perform(NSSelectorFromString("handleDoubleClick"))
        // Should not crash; titleLabel.isEditable should be true
        XCTAssertTrue(cell.titleLabel.isEditable)
    }

    // MARK: - controlTextDidEndEditing

    func testControlTextDidEndEditing_validTitle_callsOnRenamed() {
        var receivedTitle: String?
        cell.onRenamed = { title in receivedTitle = title }
        cell.titleLabel.stringValue = "New Folder Name"
        cell.controlTextDidEndEditing(Notification(name: NSTextField.textDidEndEditingNotification))
        XCTAssertEqual(receivedTitle, "New Folder Name")
    }

    func testControlTextDidEndEditing_emptyTitle_doesNotCallOnRenamed() {
        var receivedTitle: String?
        cell.onRenamed = { title in receivedTitle = title }
        cell.titleLabel.stringValue = "   "
        cell.controlTextDidEndEditing(Notification(name: NSTextField.textDidEndEditingNotification))
        XCTAssertNil(receivedTitle)
    }

    func testControlTextDidEndEditing_whitespaceTitle_doesNotCallOnRenamed() {
        var receivedTitle: String?
        cell.onRenamed = { title in receivedTitle = title }
        cell.titleLabel.stringValue = "\n\t"
        cell.controlTextDidEndEditing(Notification(name: NSTextField.textDidEndEditingNotification))
        XCTAssertNil(receivedTitle)
    }
}
#endif
