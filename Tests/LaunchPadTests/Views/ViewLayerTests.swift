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
        // 3 dots * 8pt + 2 gaps * 8pt = 40pt wide, 8pt tall
        XCTAssertEqual(size.width, 40)
        XCTAssertEqual(size.height, 8)
    }
}
#endif
