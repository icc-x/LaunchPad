import Testing
import os
@testable import LaunchPad
@testable import LaunchPadProtocols

#if canImport(AppKit)
import AppKit

/// Tests for AnimationRunner utility (0% → target 100%)
@MainActor @Suite("AnimationRunner") struct AnimationRunnerTests {

    @Test func animate_reduceMotion_callsReduced() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var normalCalled = false
        var reducedCalled = false

        AnimationRunner.animate(
            settings: settings,
            animation: AnimationConstants.pageScroll,
            normal: { normalCalled = true },
            reduced: { reducedCalled = true }
        )

        #expect(reducedCalled)
        #expect(!normalCalled)
    }

    @Test func animate_normalMotion_callsNormal() {
        let settings = AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false)
        var normalCalled = false
        var reducedCalled = false

        AnimationRunner.animate(
            settings: settings,
            animation: AnimationConstants.pageScroll,
            normal: { normalCalled = true },
            reduced: { reducedCalled = true }
        )

        #expect(normalCalled)
        #expect(!reducedCalled)
    }

    @Test func run_reduceMotion_skipsBlock() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        // .instant fallback should still call block
        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.iconEntrance,
            block: { blockCalled = true }
        )

        // run() with .instant fallback calls block directly
        #expect(blockCalled)
    }

    @Test func run_normalMotion_callsBlock() {
        let settings = AccessibilitySettings(reduceMotion: false, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.pageScroll,
            block: { blockCalled = true }
        )

        #expect(blockCalled)
    }

    // MARK: - run() Reduce Motion fallback branches

    @Test func run_reduceMotion_fadeFallback_callsBlock() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        // windowExpand has .fade(duration:) fallback
        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.windowExpand,
            block: { blockCalled = true }
        )

        #expect(blockCalled)
    }

    @Test func run_reduceMotion_scalePulseFallback_callsBlock() {
        let settings = AccessibilitySettings(reduceMotion: true, reduceTransparency: false, increaseContrast: false)
        var blockCalled = false

        // jiggle has .scalePulse fallback
        AnimationRunner.run(
            settings: settings,
            animation: AnimationConstants.jiggle,
            block: { blockCalled = true }
        )

        #expect(blockCalled)
    }
}

/// Tests for EmptyStateView (0% → basic instantiation)
@MainActor @Suite("EmptyStateView") struct EmptyStateViewTests {

    @Test func emptyStateView_init_doesNotCrash() {
        let view = EmptyStateView()
        #expect(view.isHidden)
        #expect(view.alphaValue == 0)
    }

    @Test func emptyStateView_show_unhides() {
        let view = EmptyStateView()
        view.show(animated: false)
        #expect(!view.isHidden)
    }

    @Test func emptyStateView_hide_hides() {
        let view = EmptyStateView()
        view.show(animated: false)
        view.hide(animated: false)
        #expect(view.isHidden)
    }

    @Test func emptyStateView_show_animated_doesNotCrash() {
        let view = EmptyStateView()
        view.show(animated: true)
        #expect(!view.isHidden)
    }

    @Test func emptyStateView_hide_animated_doesNotCrash() {
        let view = EmptyStateView()
        view.show(animated: false)
        view.hideCompletionRunner = { $0() }
        view.hide(animated: true)
        #expect(view.isHidden)
    }

    @Test func emptyStateView_hide_animated_completionHidesView() {
        let view = EmptyStateView()
        view.show(animated: false)
        var completionRan = false
        view.hideCompletionRunner = { completion in
            completionRan = true
            completion()
        }

        view.hide(animated: true)

        #expect(completionRan)
        #expect(view.isHidden)
    }

    @Test func emptyStateView_show_hide_multipleTimes() {
        let view = EmptyStateView()
        view.show(animated: false)
        view.hide(animated: false)
        view.show(animated: false)
        view.hide(animated: false)
        #expect(view.isHidden)
    }

    // MARK: - init?(coder:)

    @Test func emptyStateView_initCoder_producesValidInstance() throws {
        let original = EmptyStateView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(original, forKey: "root")
        archiver.finishEncoding()
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let view = try #require(unarchiver.decodeObject(forKey: "root") as? EmptyStateView)
        #expect(view.isHidden)
    }
}

/// Tests for SearchBar (0% → basic instantiation)
@MainActor @Suite("SearchBar") struct SearchBarTests {

    @Test func searchBar_init_doesNotCrash() {
        let bar = SearchBar()
        #expect(bar.isHidden)
        #expect(bar.alphaValue == 0)
    }

    @Test func searchBar_show_unhides() {
        let bar = SearchBar()
        bar.show(animated: false)
        #expect(!bar.isHidden)
    }

    @Test func searchBar_hide_hides() {
        let bar = SearchBar()
        bar.show(animated: false)
        bar.hide(animated: false)
        #expect(bar.isHidden)
    }

    @Test func searchBar_clearAndFocus_resetsStringValue() {
        let bar = SearchBar()
        bar.show(animated: false)
        bar.stringValue = "test"
        bar.clearAndFocus()
        #expect(bar.stringValue == "")
    }

    @Test func searchBar_onQueryChanged_callback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.clearAndFocus()
        #expect(receivedQuery == "")
    }

    // MARK: - Delegate methods

    @Test func searchBar_controlTextDidChange_callsCallback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.stringValue = "test"
        bar.controlTextDidChange(Notification(name: NSTextField.textDidChangeNotification))
        #expect(receivedQuery == "test")
    }

    @Test func searchBar_searchFieldDidStartSearching_callsCallback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.stringValue = "hello"
        bar.searchFieldDidStartSearching(bar)
        #expect(receivedQuery == "hello")
    }

    @Test func searchBar_searchFieldDidEndSearching_callsCallback() {
        let bar = SearchBar()
        var receivedQuery: String?
        bar.onQueryChanged = { query in receivedQuery = query }
        bar.searchFieldDidEndSearching(bar)
        #expect(receivedQuery == "")
    }

    @Test func searchBar_show_animated_doesNotCrash() {
        let bar = SearchBar()
        bar.show(animated: true)
        #expect(!bar.isHidden)
    }

    @Test func searchBar_hide_animated_doesNotCrash() {
        let bar = SearchBar()
        bar.show(animated: false)
        bar.hideCompletionRunner = { $0() }
        bar.hide(animated: true)
        #expect(bar.isHidden)
    }

    // MARK: - init?(coder:)

    @Test func searchBar_initCoder_producesValidInstance() throws {
        let original = SearchBar(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(original, forKey: "root")
        archiver.finishEncoding()
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        _ = try #require(unarchiver.decodeObject(forKey: "root") as? SearchBar)
    }

    // MARK: - Guard branches

    @Test func searchBar_show_calledTwice_secondCallIsNoOp() {
        let bar = SearchBar()
        bar.show(animated: false)
        #expect(bar.alphaValue == 1)
        // Second call should be no-op (guard !isShown)
        bar.show(animated: false)
        #expect(bar.alphaValue == 1)
    }

    @Test func searchBar_hide_withoutShow_isNoOp() {
        let bar = SearchBar()
        // hide without show should be no-op (guard isShown)
        bar.hide(animated: false)
        #expect(bar.isHidden)
        #expect(bar.alphaValue == 0)
    }

    @Test func searchBar_hide_animated_completionHidesView() {
        let bar = SearchBar()
        bar.show(animated: false)
        var completionRan = false
        bar.hideCompletionRunner = { completion in
            completionRan = true
            completion()
        }

        bar.hide(animated: true)

        #expect(completionRan)
        #expect(bar.isHidden)
    }
}

@MainActor
private final class GridSectionsDataSource: NSObject, NSCollectionViewDataSource {
    var itemCounts: [Int]
    init(itemCounts: [Int]) { self.itemCounts = itemCounts }

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        itemCounts.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        itemCounts[section]
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: AppIconCell.identifier, for: indexPath)
    }
}

@MainActor
private func makeGridFixture(
    itemCounts: [Int],
    viewportSize: CGSize
) -> (
    window: NSWindow,
    scrollView: NSScrollView,
    collectionView: AppGridCollectionView,
    layout: AppGridFlowLayout,
    dataSource: GridSectionsDataSource,
    metrics: GridMetrics
) {
    let metrics = GridLayoutCalculator.calculate(viewportSize: viewportSize)
    let layout = AppGridFlowLayout()
    layout.applyGridMetrics(metrics)
    let collectionView = AppGridCollectionView(frame: NSRect(
        origin: .zero,
        size: NSSize(width: metrics.pageWidth * CGFloat(max(itemCounts.count, 1)),
                     height: viewportSize.height)
    ))
    collectionView.collectionViewLayout = layout
    collectionView.register(AppIconCell.self, forItemWithIdentifier: AppIconCell.identifier)
    let dataSource = GridSectionsDataSource(itemCounts: itemCounts)
    collectionView.dataSource = dataSource
    // This fixture owns its external data source; isolate unrelated production selection callbacks.
    collectionView.delegate = nil
    let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: viewportSize))
    scrollView.documentView = collectionView
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: viewportSize),
        styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = scrollView
    collectionView.reloadData()
    layout.prepare()
    return (window, scrollView, collectionView, layout, dataSource, metrics)
}

@MainActor
private func expectRowMajor(
    attributes: [NSCollectionViewLayoutAttributes],
    columns: Int,
    expectedRows: Int
) throws {
    let indexed = try attributes.map { attribute in
        (
            item: try #require(attribute.indexPath).item,
            attributes: attribute
        )
    }
    let sorted = indexed.sorted { $0.item < $1.item }
    #expect(Set(sorted.map { $0.attributes.frame.minY.rounded() }).count == expectedRows)
    for (index, entry) in sorted.enumerated() {
        let row = index / columns
        let column = index % columns
        #expect(entry.item == index)
        if column > 0 {
            #expect(abs(
                entry.attributes.frame.minY
                    - sorted[row * columns].attributes.frame.minY
            ) <= 0.5)
        }
    }
}

@MainActor @Suite("显式 row-major 分页网格") struct AppGridFlowLayoutTests {

    @Test func rowMajorAttributesUseTwoThreeAndFiveRowsWithoutOverlap() throws {
        for (height, itemCount, expectedRows) in [(248.0, 14, 2), (372.0, 21, 3), (620.0, 35, 5)] {
            let fixture = makeGridFixture(
                itemCounts: [itemCount],
                viewportSize: CGSize(width: 1440, height: height)
            )
            let attributes = (0..<itemCount).compactMap {
                fixture.layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))
            }
            try expectRowMajor(
                attributes: attributes,
                columns: fixture.metrics.columns,
                expectedRows: expectedRows
            )
            for left in attributes.indices {
                for right in attributes.indices where right > left {
                    #expect(!attributes[left].frame.intersects(attributes[right].frame))
                }
            }
        }
    }

    @Test func twoAndThreeSectionOriginsDifferByPageWidth() {
        for count in [2, 3] {
            let fixture = makeGridFixture(
                itemCounts: Array(repeating: 1, count: count),
                viewportSize: CGSize(width: 1440, height: 620)
            )
            let origins = (0..<count).compactMap {
                fixture.layout.layoutAttributesForItem(
                    at: IndexPath(item: 0, section: $0)
                )?.frame.minX
            }
            #expect(origins.count == count)
            for section in 1..<count {
                #expect(
                    abs(
                        origins[section] - origins[section - 1]
                            - fixture.metrics.pageWidth
                    ) <= 0.5
                )
            }
            #expect(
                abs(
                    fixture.layout.collectionViewContentSize.width
                        - CGFloat(count) * fixture.metrics.pageWidth
                ) <= 0.5
            )
        }
    }

    @Test func partialLastPageStartsAtTopLeftSlot() throws {
        let fixture = makeGridFixture(
            itemCounts: [35, 3],
            viewportSize: CGSize(width: 1440, height: 620)
        )
        let first = try #require(fixture.layout.layoutAttributesForItem(
            at: IndexPath(item: 0, section: 1)
        ))
        #expect(
            first.frame.origin == NSPoint(
                x: fixture.metrics.pageWidth + fixture.metrics.sectionInsets.left,
                y: fixture.metrics.sectionInsets.top
            )
        )
    }

    @Test func supplementaryRequestIsNotRepositionedAsAnItem() {
        let fixture = makeGridFixture(
            itemCounts: [1], viewportSize: CGSize(width: 1440, height: 620)
        )
        #expect(fixture.layout.layoutAttributesForSupplementaryView(
            ofKind: NSCollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        ) == nil)
    }

    @Test func snapUsesRealSectionCountAndConfiguredPageWidth() {
        let fixture = makeGridFixture(
            itemCounts: [1, 1, 1], viewportSize: CGSize(width: 300, height: 248)
        )
        fixture.scrollView.contentView.setBoundsOrigin(NSPoint(x: 300, y: 0))
        let target = fixture.layout.targetContentOffset(
            forProposedContentOffset: NSPoint(x: 610, y: 17),
            withScrollingVelocity: .zero
        )
        #expect(target == NSPoint(x: 600, y: 0))
    }

    @Test func documentFrameTracksPagedContentWidthAndCanShrink() {
        let fixture = makeGridFixture(
            itemCounts: [1, 1, 1], viewportSize: CGSize(width: 300, height: 248)
        )
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        #expect(abs(fixture.collectionView.frame.width - 900) <= 0.5)
        #expect(abs(fixture.scrollView.contentView.documentRect.width - 900) <= 0.5)

        fixture.dataSource.itemCounts = [1, 1]
        fixture.collectionView.reloadData()
        fixture.layout.invalidateLayout()
        fixture.window.contentView?.layoutSubtreeIfNeeded()

        #expect(abs(fixture.collectionView.frame.width - 600) <= 0.5)
        #expect(abs(fixture.scrollView.contentView.documentRect.width - 600) <= 0.5)
    }

    @Test
    @available(*, deprecated, message: "Covers the deprecated compatibility API")
    func compatibilityMetricsStayBoundToClipViewportAcrossPrepares() {
        let viewportSize = CGSize(width: 300, height: 248)
        let fixture = makeGridFixture(
            itemCounts: [1, 1, 1], viewportSize: viewportSize
        )
        fixture.scrollView.scrollerStyle = .legacy
        fixture.scrollView.hasVerticalScroller = true
        fixture.collectionView.setFrameSize(NSSize(width: 900, height: 620))
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        let clipSize = fixture.scrollView.contentView.bounds.size
        let parameters = GridLayoutCalculator.calculate(screenWidth: viewportSize.width)
        let expectedMetrics = GridLayoutCalculator.calculate(viewportSize: clipSize)
        let expectedContentHeight = expectedMetrics.sectionInsets.top
            + CGFloat(expectedMetrics.rows) * expectedMetrics.itemSize.height
            + CGFloat(max(expectedMetrics.rows - 1, 0)) * expectedMetrics.verticalSpacing
            + expectedMetrics.sectionInsets.bottom

        #expect(fixture.scrollView.scrollerStyle == .legacy)
        #expect(clipSize.width < viewportSize.width)

        for _ in 0..<2 {
            fixture.layout.applyGridParameters(parameters)
            fixture.layout.prepare()

            #expect(
                abs(
                    fixture.layout.collectionViewContentSize.width
                        - 3 * clipSize.width
                ) <= 0.5
            )
            #expect(
                abs(
                    fixture.layout.collectionViewContentSize.height - expectedContentHeight
                ) <= 0.5
            )
            fixture.window.contentView?.layoutSubtreeIfNeeded()
        }
    }
}

/// Tests for PageControlView (0% → basic interaction)
@MainActor @Suite("PageControlView") struct PageControlViewTests {

    @Test func pageControlView_init_doesNotCrash() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        #expect(view.onDotSelected == nil)
    }

    @Test func pageControlView_update_withMultiplePages_isVisible() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.update()
        #expect(!view.isHidden)
    }

    @Test func pageControlView_update_withSinglePage_isHidden() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 1)
        let view = PageControlView(viewModel: viewModel)
        view.update()
        #expect(view.isHidden)
    }

    @Test func pageControlView_intrinsicContentSize_multiplePages() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        let size = view.intrinsicContentSize
        #expect(size.width == 40)
        #expect(size.height == 8)
    }

    @Test func pageControlView_intrinsicContentSize_zeroPages() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 0)
        let view = PageControlView(viewModel: viewModel)
        let size = view.intrinsicContentSize
        #expect(size.width == 0)
        #expect(size.height == 8)
    }

    @Test func pageControlView_intrinsicContentSize_singlePage() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 1)
        let view = PageControlView(viewModel: viewModel)
        let size = view.intrinsicContentSize
        #expect(size.width == 8) // 1 dot * 8pt
        #expect(size.height == 8)
    }

    // MARK: - Draw

    @Test func pageControlView_draw_withPages_doesNotCrash() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        view.draw(view.bounds)
    }

    @Test func pageControlView_draw_zeroPages_doesNotCrash() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 0)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        view.draw(view.bounds)
    }

    @Test func pageControlView_draw_withActiveDot_doesNotCrash() {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 4)
        viewModel.currentPage = 2
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
        view.draw(view.bounds)
    }

    // MARK: - Mouse

    @Test func pageControlView_mouseDown_onDot_selectsPage() throws {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)

        var selectedDot: Int?
        view.onDotSelected = { dot in selectedDot = dot }

        // Click on the first dot area
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 50, y: 10), // center of view
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        view.mouseDown(with: event)

        #expect(selectedDot == 1)
    }

    @Test func pageControlView_mouseDown_outsideDots_doesNotSelect() throws {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 3)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 20)

        var selectedDot: Int?
        view.onDotSelected = { dot in selectedDot = dot }

        // Click far outside dot area
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 5, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        view.mouseDown(with: event)

        #expect(selectedDot == nil)
    }

    @Test func pageControlView_mouseDown_zeroPages_doesNotCrash() throws {
        let viewModel = PageControlViewModel()
        viewModel.configure(totalPages: 0)
        let view = PageControlView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 20)
        var callbackCount = 0
        view.onDotSelected = { _ in callbackCount += 1 }

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 50, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
        view.mouseDown(with: event)

        #expect(callbackCount == 0)
    }

    // MARK: - Accessibility

    @Test func pageControlView_accessibilityRole_isSlider() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        #expect(view.accessibilityRole() == .slider)
    }

    @Test func pageControlView_accessibilityLabel_isPageIndicator() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        #expect(view.accessibilityLabel() == "Page indicator")
    }

    // MARK: - onDotSelected callback

    @Test func pageControlView_onDotSelected_isSettable() {
        let viewModel = PageControlViewModel()
        let view = PageControlView(viewModel: viewModel)
        view.onDotSelected = { _ in }
        #expect(view.onDotSelected != nil)
    }

    // MARK: - init?(coder:)

    @Test func pageControlView_initCoder_producesValidInstance() throws {
        let original = PageControlView(viewModel: PageControlViewModel())
        let archiver = NSKeyedArchiver(requiringSecureCoding: false)
        archiver.encode(original, forKey: "root")
        archiver.finishEncoding()
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        _ = try #require(unarchiver.decodeObject(forKey: "root") as? PageControlView)
    }
}

#endif
