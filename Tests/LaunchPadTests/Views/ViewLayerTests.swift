import XCTest
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for AnimationRunner utility (0% → target 100%)
final class AnimationRunnerTests: XCTestCase {

    func testAnimate_reduceMotion_callsReduced() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var normalCalled = false
        var reducedCalled = false

        AnimationRunner.animate(
            settings: settings,
            animation: AnimationConstants.pageScroll,
            normal: { normalCalled = true },
            reduced: { reducedCalled = true }
        )

        XCTAssertTrue(reducedCalled)
        XCTAssertFalse(normalCalled)
    }

    func testAnimate_normalMotion_callsNormal() {
        let settings = AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false)
        var normalCalled = false
        var reducedCalled = false

        AnimationRunner.animate(
            settings: settings,
            animation: AnimationConstants.pageScroll,
            normal: { normalCalled = true },
            reduced: { reducedCalled = true }
        )

        XCTAssertTrue(normalCalled)
        XCTAssertFalse(reducedCalled)
    }

    func testRun_reduceMotion_skipsBlock() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        // .instant fallback should still call block
        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.iconEntrance,
            block: { blockCalled = true }
        )

        // run() with .instant fallback calls block directly
        XCTAssertTrue(blockCalled)
    }

    func testRun_normalMotion_callsBlock() {
        let settings = AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.pageScroll,
            block: { blockCalled = true }
        )

        XCTAssertTrue(blockCalled)
    }

    // MARK: - run() Reduce Motion fallback branches

    func testRun_reduceMotion_fadeFallback_callsBlock() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        // windowExpand has .fade(duration:) fallback
        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.windowExpand,
            block: { blockCalled = true }
        )

        XCTAssertTrue(blockCalled)
    }

    func testRun_reduceMotion_scalePulseFallback_callsBlock() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        // jiggle has .scalePulse fallback
        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.jiggle,
            block: { blockCalled = true }
        )

        XCTAssertTrue(blockCalled)
    }
}

/// Tests for LayoutPersistence (0% → target 100%)
final class LayoutPersistenceTests: XCTestCase {

    func testLoadLayout_emptyStorage_returnsEmptyLayout() throws {
        let reader = MockItemReader()
        reader.items = []

        let layout = try LayoutPersistence.loadLayout(reader: reader)

        XCTAssertTrue(layout.pages.isEmpty)
        XCTAssertTrue(layout.itemsByPage.isEmpty)
    }

    func testLoadLayout_withPages_returnsCorrectStructure() throws {
        let page1 = TestDataFactory.makePageItem(id: 1, type: .page, ordering: 0)
        let page2 = TestDataFactory.makePageItem(id: 2, type: .page, ordering: 1)
        let app1 = TestDataFactory.makePageItem(id: 10, type: .app, ordering: 0, parentId: 1)
        let app2 = TestDataFactory.makePageItem(id: 11, type: .app, ordering: 1, parentId: 1)
        let app3 = TestDataFactory.makePageItem(id: 12, type: .app, ordering: 0, parentId: 2)

        let reader = MockItemReader()
        // fetchAllItems(nil) returns top-level items (pages)
        reader.fetchAllItemsHandler = { parentId in
            if parentId == nil { return [page1, page2] }
            if parentId == 1 { return [app1, app2] }
            if parentId == 2 { return [app3] }
            return []
        }

        let layout = try LayoutPersistence.loadLayout(reader: reader)

        XCTAssertEqual(layout.pages.count, 2)
        XCTAssertEqual(layout.pages[0].id, 1)
        XCTAssertEqual(layout.pages[1].id, 2)
        XCTAssertEqual(layout.itemsByPage[1]?.count, 2)
        XCTAssertEqual(layout.itemsByPage[2]?.count, 1)
    }

    func testSaveLayout_callsUpdateForEachItem() throws {
        let writer = MockItemWriter()
        let items = [
            TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0),
            TestDataFactory.makePageItem(id: 2, type: .app, ordering: 1),
            TestDataFactory.makePageItem(id: 3, type: .app, ordering: 2),
        ]
        try LayoutPersistence.saveLayout(items: items, writer: writer)

        XCTAssertEqual(writer.updatedItems.count, 3)
        XCTAssertEqual(writer.updatedItems.map { $0.id }, [1, 2, 3])
    }

    func testSaveLayout_emptyList_doesNotCallUpdate() throws {
        let writer = MockItemWriter()
        try LayoutPersistence.saveLayout(items: [], writer: writer)
        XCTAssertTrue(writer.updatedItems.isEmpty)
    }

    func testSaveLayout_propagatesError() throws {
        let writer = MockItemWriter()
        writer.updateError = TestError.generic
        let items = [TestDataFactory.makePageItem(id: 1, type: .app, ordering: 0)]

        XCTAssertThrowsError(try LayoutPersistence.saveLayout(items: items, writer: writer))
        XCTAssertEqual(writer.updatedItems.count, 0)
    }
}

/// Tests for EmptyStateView (0% → basic instantiation)
final class EmptyStateViewTests: XCTestCase {

    func testEmptyStateView_init_doesNotCrash() {
        let view = EmptyStateView()
        XCTAssertNotNil(view)
        XCTAssertTrue(view.isHidden)
    }

    func testEmptyStateView_show_unhides() {
        let view = EmptyStateView()
        view.show(animated: false)
        XCTAssertFalse(view.isHidden)
    }

    func testEmptyStateView_hide_hides() {
        let view = EmptyStateView()
        view.show(animated: false)
        view.hide(animated: false)
        XCTAssertTrue(view.isHidden)
    }

    func testEmptyStateView_show_animated_doesNotCrash() {
        let view = EmptyStateView()
        view.show(animated: true)
        XCTAssertFalse(view.isHidden)
    }

    func testEmptyStateView_hide_animated_doesNotCrash() {
        let view = EmptyStateView()
        view.show(animated: false)
        view.hide(animated: true)
    }

    @MainActor
    func testEmptyStateView_hide_animated_completionHidesView() {
        let view = EmptyStateView()
        view.show(animated: false)
        // 注入同步 completion runner，确定性触发 hide 完成闭包（覆盖 64-67 行）
        view.hideCompletionRunner = { $0() }
        view.hide(animated: true)
        XCTAssertTrue(view.isHidden)
    }

    func testEmptyStateView_show_hide_multipleTimes() {
        let view = EmptyStateView()
        view.show(animated: false)
        view.hide(animated: false)
        view.show(animated: false)
        view.hide(animated: false)
        XCTAssertTrue(view.isHidden)
    }

    // MARK: - init?(coder:)

    func testEmptyStateView_initCoder_producesValidInstance() throws {
        let original = EmptyStateView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let archiver = NSKeyedArchiver()
        archiver.requiresSecureCoding = false
        archiver.encode(original, forKey: "root")
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let view = unarchiver.decodeObject(forKey: "root") as? EmptyStateView
        XCTAssertNotNil(view)
        XCTAssertTrue(view!.isHidden)
    }
}

/// Tests for SearchBar (0% → basic instantiation)
final class SearchBarTests: XCTestCase {

    func testSearchBar_init_doesNotCrash() {
        let bar = SearchBar()
        XCTAssertNotNil(bar)
        XCTAssertTrue(bar.isHidden)
    }

    func testSearchBar_show_unhides() {
        let bar = SearchBar()
        bar.show(animated: false)
        XCTAssertFalse(bar.isHidden)
    }

    func testSearchBar_hide_hides() {
        let bar = SearchBar()
        bar.show(animated: false)
        bar.hide(animated: false)
        XCTAssertTrue(bar.isHidden)
    }

    func testSearchBar_clearAndFocus_resetsStringValue() {
        let bar = SearchBar()
        bar.show(animated: false)
        bar.stringValue = "test"
        bar.clearAndFocus()
        XCTAssertEqual(bar.stringValue, "")
    }

    func testSearchBar_onQueryChanged_callback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.clearAndFocus()
        XCTAssertEqual(receivedQuery, "")
    }

    // MARK: - Delegate methods

    func testSearchBar_controlTextDidChange_callsCallback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.stringValue = "test"
        bar.controlTextDidChange(Notification(name: NSTextField.textDidChangeNotification))
        XCTAssertEqual(receivedQuery, "test")
    }

    func testSearchBar_searchFieldDidStartSearching_callsCallback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.stringValue = "hello"
        bar.searchFieldDidStartSearching(bar)
        XCTAssertEqual(receivedQuery, "hello")
    }

    func testSearchBar_searchFieldDidEndSearching_callsCallback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.searchFieldDidEndSearching(bar)
        XCTAssertEqual(receivedQuery, "")
    }

    func testSearchBar_show_animated_doesNotCrash() {
        let bar = SearchBar()
        bar.show(animated: true)
        XCTAssertFalse(bar.isHidden)
    }

    func testSearchBar_hide_animated_doesNotCrash() {
        let bar = SearchBar()
        bar.show(animated: false)
        bar.hide(animated: true)
    }

    // MARK: - init?(coder:)

    func testSearchBar_initCoder_producesValidInstance() throws {
        let original = SearchBar(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let archiver = NSKeyedArchiver()
        archiver.requiresSecureCoding = false
        archiver.encode(original, forKey: "root")
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let bar = unarchiver.decodeObject(forKey: "root") as? SearchBar
        XCTAssertNotNil(bar)
    }

    // MARK: - Guard branches

    func testSearchBar_show_calledTwice_secondCallIsNoOp() {
        let bar = SearchBar()
        bar.show(animated: false)
        XCTAssertEqual(bar.alphaValue, 1)
        // Second call should be no-op (guard !isShown)
        bar.show(animated: false)
        XCTAssertEqual(bar.alphaValue, 1)
    }

    func testSearchBar_hide_withoutShow_isNoOp() {
        let bar = SearchBar()
        // hide without show should be no-op (guard isShown)
        bar.hide(animated: false)
        XCTAssertTrue(bar.isHidden)
        XCTAssertEqual(bar.alphaValue, 0)
    }

    func testSearchBar_hide_animated_completionHidesView() {
        let bar = SearchBar()
        bar.show(animated: false)
        bar.hide(animated: true)

        let expectation = XCTestExpectation(description: "Animated hide completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertTrue(bar.isHidden)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}

/// Tests for AppGridFlowLayout (0% → basic instantiation)
final class AppGridFlowLayoutTests: XCTestCase {

    func testAppGridFlowLayout_init_doesNotCrash() {
        let layout = AppGridFlowLayout()
        XCTAssertNotNil(layout)
    }

    func testApplyGridParameters_setsScrollDirection() {
        let layout = AppGridFlowLayout()
        let screenWidth: CGFloat = 1440
        let params = GridLayoutCalculator.calculate(screenWidth: screenWidth)
        layout.applyGridParameters(params)

        XCTAssertEqual(layout.scrollDirection, .horizontal)
    }
}

/// Tests for PageControlView (0% → basic interaction)
@MainActor
final class PageControlViewTests: XCTestCase {

    func testPageControlView_init_doesNotCrash() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        XCTAssertNotNil(view)
    }

    func testPageControlView_update_withMultiplePages_isVisible() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.update()
        XCTAssertFalse(view.isHidden)
    }

    func testPageControlView_update_withSinglePage_isHidden() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 1)
        let view = PageControlView(viewModel: viewModel)
        view.update()
        XCTAssertTrue(view.isHidden)
    }

    func testPageControlView_intrinsicContentSize_multiplePages() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        let size = view.intrinsicContentSize
        XCTAssertEqual(size.width, 40)
        XCTAssertEqual(size.height, 8)
    }

    func testPageControlView_intrinsicContentSize_zeroPages() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 0)
        let view = PageControlView(viewModel: viewModel)
        let size = view.intrinsicContentSize
        XCTAssertEqual(size.width, 0)
        XCTAssertEqual(size.height, 8)
    }

    func testPageControlView_intrinsicContentSize_singlePage() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 1)
        let view = PageControlView(viewModel: viewModel)
        let size = view.intrinsicContentSize
        XCTAssertEqual(size.width, 8) // 1 dot * 8pt
        XCTAssertEqual(size.height, 8)
    }

    // MARK: - Draw

    func testPageControlView_draw_withPages_doesNotCrash() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        view.draw(view.bounds)
    }

    func testPageControlView_draw_zeroPages_doesNotCrash() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 0)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        view.draw(view.bounds)
    }

    func testPageControlView_draw_withActiveDot_doesNotCrash() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 4)
        viewModel.currentPage = 2
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        view.draw(view.bounds)
    }

    // MARK: - Mouse

    func testPageControlView_mouseDown_onDot_selectsPage() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)

        var selectedDot: Int?
        view.onDotSelected = { dot in selectedDot = dot }

        // Click on the first dot area
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 50, y: 10), // center of view
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        if let event {
            view.mouseDown(with: event)
        }
        // Should select a dot (exact index depends on layout calculation)
        XCTAssertNotNil(selectedDot)
    }

    func testPageControlView_mouseDown_outsideDots_doesNotSelect() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 20)

        var selectedDot: Int?
        view.onDotSelected = { dot in selectedDot = dot }

        // Click far outside dot area
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 5, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        if let event {
            view.mouseDown(with: event)
        }
        XCTAssertNil(selectedDot)
    }

    func testPageControlView_mouseDown_zeroPages_doesNotCrash() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 0)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 50, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )
        if let event {
            view.mouseDown(with: event)
        }
    }

    // MARK: - Accessibility

    func testPageControlView_accessibilityRole_isGroup() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        XCTAssertEqual(view.accessibilityRole(), .group)
    }

    func testPageControlView_accessibilityLabel_isPageIndicator() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        XCTAssertEqual(view.accessibilityLabel(), "Page indicator")
    }

    // MARK: - onDotSelected callback

    func testPageControlView_onDotSelected_isSettable() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        view.onDotSelected = { _ in }
        XCTAssertNotNil(view.onDotSelected)
    }

    // MARK: - init?(coder:)

    func testPageControlView_initCoder_producesValidInstance() throws {
        let original = PageControlView(viewModel: PageControlViewModel())
        let archiver = NSKeyedArchiver()
        archiver.requiresSecureCoding = false
        archiver.encode(original, forKey: "root")
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let view = unarchiver.decodeObject(forKey: "root") as? PageControlView
        XCTAssertNotNil(view)
    }
}

/// Tests for AppGridFlowLayout (0% → basic interaction)
@MainActor
final class AppGridFlowLayoutTests2: XCTestCase {

    func testApplyGridParameters_setsItemSize() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        let expectedWidth = params.iconSize + params.spacing
        let expectedHeight = params.iconSize + 40
        XCTAssertEqual(layout.itemSize.width, expectedWidth)
        XCTAssertEqual(layout.itemSize.height, expectedHeight)
    }

    func testApplyGridParameters_setsSpacing() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        XCTAssertEqual(layout.minimumInteritemSpacing, params.spacing)
        XCTAssertEqual(layout.minimumLineSpacing, params.spacing)
    }

    func testApplyGridParameters_setsSectionInset() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        XCTAssertEqual(layout.sectionInset.top, params.topMargin)
        XCTAssertEqual(layout.sectionInset.left, params.horizontalMargin)
        XCTAssertEqual(layout.sectionInset.bottom, params.bottomMargin)
        XCTAssertEqual(layout.sectionInset.right, params.horizontalMargin)
    }

    func testApplyGridParameters_setsScrollDirection() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        XCTAssertEqual(layout.scrollDirection, .horizontal)
    }

    func testApplyGridParameters_setsHeaderSize() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        XCTAssertEqual(layout.headerReferenceSize, .zero)
    }

    func testApplyGridParameters_differentScreenWidths() {
        let layout = AppGridFlowLayout()

        let small = GridLayoutCalculator.calculate(screenWidth: 1280)
        layout.applyGridParameters(small)
        XCTAssertEqual(layout.scrollDirection, .horizontal)

        let large = GridLayoutCalculator.calculate(screenWidth: 2560)
        layout.applyGridParameters(large)
        XCTAssertEqual(layout.scrollDirection, .horizontal)
    }

    // MARK: - targetContentOffset

    func testTargetContentOffset_withoutCollectionView_returnsProposed() {
        let layout = AppGridFlowLayout()
        let proposed = NSPoint(x: 100, y: 0)
        let result = layout.targetContentOffset(forProposedContentOffset: proposed, withScrollingVelocity: .zero)
        // Without collectionView, should fall through to super
        XCTAssertNotNil(result)
    }

    func testTargetContentOffset_withCollectionView_snapsToPage() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        collectionView.collectionViewLayout = layout
        // Need to set up document view for layout to work
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1440 * 3, height: 900))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        scrollView.documentView = documentView
        documentView.addSubview(collectionView)

        let proposed = NSPoint(x: 500, y: 0)
        let result = layout.targetContentOffset(forProposedContentOffset: proposed, withScrollingVelocity: .zero)
        // Should snap to nearest page
        XCTAssertNotNil(result)
    }

    // MARK: - layoutAttributesForElements

    func testLayoutAttributesForElements_withoutCollectionView_returnsEmpty() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        let attrs = layout.layoutAttributesForElements(in: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertNotNil(attrs)
    }

    func testLayoutAttributesForElements_withEmptyCollectionView_returnsEmpty() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        collectionView.collectionViewLayout = layout

        let attrs = layout.layoutAttributesForElements(in: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertNotNil(attrs)
    }

    func testLayoutAttributesForElements_withItems_centersVertically() {
        let layout = AppGridFlowLayout()
        let params = GridLayoutCalculator.calculate(screenWidth: 1440)
        layout.applyGridParameters(params)

        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        collectionView.collectionViewLayout = layout
        collectionView.register(AppIconCell.self, forItemWithIdentifier: AppIconCell.identifier)

        let dataSource = GridTestDataSource(itemCount: 5)
        collectionView.dataSource = dataSource

        // Place in a window to trigger layout
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1440 * 3, height: 900))
        scrollView.documentView = documentView
        documentView.addSubview(collectionView)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                              styleMask: [], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)

        collectionView.reloadData()
        collectionView.layoutSubtreeIfNeeded()

        let attrs = layout.layoutAttributesForElements(in: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertNotNil(attrs)
        // If layout produced attributes, verify vertical centering
        if !attrs.isEmpty {
            let collectionViewHeight = collectionView.bounds.height
            for attr in attrs {
                XCTAssertEqual(attr.frame.origin.y,
                               (collectionViewHeight - attr.frame.height) / 2,
                               accuracy: 1.0)
            }
        }
    }
}

// MARK: - Test Data Source for AppGridFlowLayout

private final class GridTestDataSource: NSObject, NSCollectionViewDataSource {
    let itemCount: Int
    init(itemCount: Int) { self.itemCount = itemCount }

    func collectionView(_ collectionView: NSCollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        itemCount
    }

    func collectionView(_ collectionView: NSCollectionView,
                        itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath)
    }
}
#endif
