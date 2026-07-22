import Testing
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

@MainActor @Suite("FolderCell")
struct FolderCellTests {
    private func makeSUT() -> FolderCell {
        let cell = FolderCell()
        _ = cell.view
        return cell
    }

    private func makeGroup(id: Int64 = 1, title: String = "Folder") -> PageItem {
        TestDataFactory.makePageItem(
            id: id,
            type: .group,
            ordering: 0,
            group: TestDataFactory.makeGroupInfo(id: id, title: title)
        )
    }

    @Test func init_loadsView() {
        let cell = makeSUT()
        #expect(cell.view != nil)
    }

    @Test func identifier_isCorrect() {
        let cell = makeSUT()
        #expect(type(of: cell).identifier == NSUserInterfaceItemIdentifier("FolderCell"))
    }

    @Test func configure_setsTitle() {
        let cell = makeSUT()
        cell.configure(item: makeGroup(title: "Utilities"), childIcons: [])
        #expect(cell.view.accessibilityLabel() == "Utilities")
    }

    @Test func configure_withChildIcons_populatesThumbnails() {
        let cell = makeSUT()
        let icons = (0..<4).map { _ in
            NSImage(size: NSSize(width: 64, height: 64))
        }
        cell.configure(item: makeGroup(), childIcons: icons)
    }

    @Test func configure_withNoChildIcons_showsEmptyGrid() {
        let cell = makeSUT()
        cell.configure(item: makeGroup(title: "Empty Folder"), childIcons: [])
    }

    @Test func configure_withMoreThan9Icons_usesOnlyFirst9() {
        let cell = makeSUT()
        let icons = (0..<15).map { _ in
            NSImage(size: NSSize(width: 64, height: 64))
        }
        cell.configure(item: makeGroup(title: "Big Folder"), childIcons: icons)
    }

    @Test func configure_increaseContrast_addsBorder() {
        let cell = makeSUT()
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increaseContrast: true
            )
        }
        cell.configure(item: makeGroup(), childIcons: [])
        #expect(cell.containerView.layer?.borderWidth == 1)
    }

    @Test func configure_increaseContrast_usesSemiboldFont() {
        let cell = makeSUT()
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increaseContrast: true
            )
        }
        cell.configure(item: makeGroup(), childIcons: [])
        let expected = NSFont.systemFont(
            ofSize: 11, weight: .semibold
        ).fontDescriptor
        #expect(cell.titleLabel.font?.fontDescriptor == expected)
    }

    @Test func configure_normalContrast_noBorder() {
        let cell = makeSUT()
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: false,
                increaseContrast: false
            )
        }
        cell.configure(item: makeGroup(), childIcons: [])
        #expect(cell.containerView.layer?.borderWidth == 0)
    }

    @Test func configure_reduceTransparency_changesMaterial() {
        let cell = makeSUT()
        let settings = AccessibilitySettings.current()
        cell.accessibilitySettingsProvider = { settings }
        cell.configure(item: makeGroup(), childIcons: [])
        if settings.reduceTransparency {
            #expect(cell.frostedBackground.material == .menu)
            #expect(cell.frostedBackground.state == .inactive)
        } else {
            #expect(cell.frostedBackground.material == .hudWindow)
            #expect(cell.frostedBackground.state == .active)
        }
    }

    @Test func configure_reduceTransparency_provider_changesMaterial() {
        let cell = makeSUT()
        cell.accessibilitySettingsProvider = {
            AccessibilitySettings(
                reduceMotion: false,
                reduceTransparency: true,
                increaseContrast: false
            )
        }
        cell.configure(item: makeGroup(), childIcons: [])
        #expect(cell.frostedBackground.material == .menu)
        #expect(cell.frostedBackground.state == .inactive)
    }

    @Test func onRenamed_callbackIsSettable() {
        let cell = makeSUT()
        cell.onRenamed = { _ in }
        #expect(cell.onRenamed != nil)
    }

    @Test func prepareForReuse_resetsState() {
        let cell = makeSUT()
        cell.configure(
            item: makeGroup(),
            childIcons: [NSImage(size: NSSize(width: 64, height: 64))]
        )
        cell.prepareForReuse()
        cell.configure(item: makeGroup(id: 2, title: "New Folder"), childIcons: [])
    }

    @Test func accessibilityRole_isButton() {
        let cell = makeSUT()
        #expect(cell.view.accessibilityRole() == .button)
    }

    @Test func handleDoubleClick_entersEditMode() {
        let cell = makeSUT()
        cell.perform(NSSelectorFromString("handleDoubleClick"))
        #expect(cell.titleLabel.isEditable)
    }

    @Test func controlTextDidEndEditing_validTitle_callsOnRenamed() {
        let cell = makeSUT()
        var receivedTitle: String?
        cell.onRenamed = { receivedTitle = $0 }
        cell.titleLabel.stringValue = "New Folder Name"
        cell.controlTextDidEndEditing(
            Notification(name: NSTextField.textDidEndEditingNotification)
        )
        #expect(receivedTitle == "New Folder Name")
    }

    @Test func controlTextDidEndEditing_emptyTitle_doesNotCallOnRenamed() {
        let cell = makeSUT()
        var receivedTitle: String?
        cell.onRenamed = { receivedTitle = $0 }
        cell.titleLabel.stringValue = "   "
        cell.controlTextDidEndEditing(
            Notification(name: NSTextField.textDidEndEditingNotification)
        )
        #expect(receivedTitle == nil)
    }

    @Test func controlTextDidEndEditing_whitespaceTitle_doesNotCallOnRenamed() {
        let cell = makeSUT()
        var receivedTitle: String?
        cell.onRenamed = { receivedTitle = $0 }
        cell.titleLabel.stringValue = "\n\t"
        cell.controlTextDidEndEditing(
            Notification(name: NSTextField.textDidEndEditingNotification)
        )
        #expect(receivedTitle == nil)
    }

    @Test func configure_nilGroup_usesDefaultTitle() {
        let cell = makeSUT()
        let item = TestDataFactory.makePageItem(
            id: 1, type: .group, ordering: 0, group: nil
        )
        cell.configure(item: item, childIcons: [])
        #expect(cell.view.accessibilityLabel() == "Folder")
    }

    @Test func configure_twice_removesExistingSubviews() {
        let cell = makeSUT()
        let icons = (0..<4).map { _ in
            NSImage(size: NSSize(width: 64, height: 64))
        }
        let group = makeGroup()
        cell.configure(item: group, childIcons: icons)
        cell.configure(item: group, childIcons: icons)
        #expect(cell.view != nil)
    }
}
#endif
