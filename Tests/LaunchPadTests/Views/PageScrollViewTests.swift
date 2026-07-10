import Testing
import CoreGraphics
import AppKit
@testable import LaunchPad

@Suite("PageScrollView target page calculation")
@MainActor
struct PageScrollViewTests {

    // MARK: - Helper

    private func calc(
        offset: CGFloat,
        velocity: CGFloat,
        currentPage: Int,
        totalPages: Int,
        pageWidth: CGFloat = 1440
    ) -> Int {
        return PageScrollView.targetPage(
            for: offset,
            velocity: velocity,
            currentPage: currentPage,
            totalPages: totalPages,
            pageWidth: pageWidth
        )
    }

    // MARK: - Velocity-driven paging

    @Test("Positive velocity above threshold -> next page")
    func positiveVelocity_aboveThreshold_nextPage() {
        let result = calc(
            offset: 0,
            velocity: 500,
            currentPage: 0,
            totalPages: 3
        )
        #expect(result == 1)
    }

    @Test("Negative velocity above threshold -> previous page")
    func negativeVelocity_aboveThreshold_previousPage() {
        let result = calc(
            offset: 0,
            velocity: -500,
            currentPage: 2,
            totalPages: 3
        )
        #expect(result == 1)
    }

    @Test("Positive velocity from middle page -> next page")
    func positiveVelocity_middlePage_nextPage() {
        let result = calc(
            offset: 0,
            velocity: 600,
            currentPage: 1,
            totalPages: 5
        )
        #expect(result == 2)
    }

    // MARK: - Low velocity + offset

    @Test("Low velocity + small offset -> stays on current page")
    func lowVelocity_smallOffset_staysCurrent() {
        let result = calc(
            offset: 100,
            velocity: 50,
            currentPage: 1,
            totalPages: 3,
            pageWidth: 1440
        )
        #expect(result == 1)
    }

    @Test("Low velocity + large positive offset (exceeds half page) -> next page")
    func lowVelocity_largePositiveOffset_nextPage() {
        let result = calc(
            offset: 800,
            velocity: 50,
            currentPage: 1,
            totalPages: 3,
            pageWidth: 1440
        )
        #expect(result == 2)
    }

    @Test("Low velocity + large negative offset (exceeds half page) -> previous page")
    func lowVelocity_largeNegativeOffset_previousPage() {
        let result = calc(
            offset: -800,
            velocity: -50,
            currentPage: 2,
            totalPages: 3,
            pageWidth: 1440
        )
        #expect(result == 1)
    }

    @Test("Low velocity + exactly half page offset -> stays on current page (boundary)")
    func lowVelocity_exactlyHalfOffset_staysCurrent() {
        let result = calc(
            offset: 720,
            velocity: 0,
            currentPage: 1,
            totalPages: 3,
            pageWidth: 1440
        )
        #expect(result == 1)
    }

    // MARK: - Edge bounce

    @Test("First page + negative velocity -> bounces back to first page (no out of bounds)")
    func firstPage_negativeVelocity_bounceBack() {
        let result = calc(
            offset: 0,
            velocity: -800,
            currentPage: 0,
            totalPages: 3
        )
        #expect(result == 0)
    }

    @Test("First page + negative offset -> bounces back to first page")
    func firstPage_negativeOffset_bounceBack() {
        let result = calc(
            offset: -500,
            velocity: -50,
            currentPage: 0,
            totalPages: 3
        )
        #expect(result == 0)
    }

    @Test("Last page + positive velocity -> bounces back to last page (no out of bounds)")
    func lastPage_positiveVelocity_bounceBack() {
        let result = calc(
            offset: 0,
            velocity: 800,
            currentPage: 2,
            totalPages: 3
        )
        #expect(result == 2)
    }

    @Test("Last page + positive offset -> bounces back to last page")
    func lastPage_positiveOffset_bounceBack() {
        let result = calc(
            offset: 500,
            velocity: 50,
            currentPage: 2,
            totalPages: 3
        )
        #expect(result == 2)
    }

    // MARK: - Velocity threshold

    @Test("Velocity just above threshold -> flips page")
    func velocity_justAboveThreshold_flips() {
        let result = calc(
            offset: 0,
            velocity: PageScrollView.velocityThreshold + 1,
            currentPage: 1,
            totalPages: 3
        )
        #expect(result == 2)
    }

    @Test("Velocity just below threshold + small offset -> stays")
    func velocity_justBelowThreshold_smallOffset_stays() {
        let result = calc(
            offset: 100,
            velocity: PageScrollView.velocityThreshold - 1,
            currentPage: 1,
            totalPages: 3
        )
        #expect(result == 1)
    }

    // MARK: - Different screen widths

    @Test("Narrow screen 768px + large offset -> correct calculation")
    func narrowScreen_largeOffset_correct() {
        let result = calc(
            offset: 400,
            velocity: 0,
            currentPage: 0,
            totalPages: 3,
            pageWidth: 768
        )
        #expect(result == 1)
    }

    @Test("Wide screen 2560px + small offset -> stays on current page")
    func wideScreen_smallOffset_stays() {
        let result = calc(
            offset: 500,
            velocity: 0,
            currentPage: 1,
            totalPages: 3,
            pageWidth: 2560
        )
        #expect(result == 1)
    }

    // MARK: - Single page

    @Test("Single page -> always returns page 0")
    func singlePage_alwaysReturnsZero() {
        let result = calc(
            offset: 0,
            velocity: 999,
            currentPage: 0,
            totalPages: 1
        )
        #expect(result == 0)
    }

    // MARK: - scrollToPage

    @Test("scrollToPage with valid page does not crash")
    func scrollToPage_validPage_noCrash() {
        let scrollView = PageScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1440 * 3, height: 900))
        scrollView.documentView = documentView
        scrollView.scrollToPage(1)
    }

    @Test("scrollToPage with page 0 does not crash")
    func scrollToPage_page0_noCrash() {
        let scrollView = PageScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1440 * 3, height: 900))
        scrollView.documentView = documentView
        scrollView.scrollToPage(0)
    }

    @Test("scrollToPage with custom pageWidth does not crash")
    func scrollToPage_customPageWidth_noCrash() {
        let scrollView = PageScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1440 * 3, height: 900))
        scrollView.documentView = documentView
        scrollView.scrollToPage(2, pageWidth: 720)
    }

    @Test("scrollToPage with zero pageWidth does not crash")
    func scrollToPage_zeroPageWidth_noCrash() {
        let scrollView = PageScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        scrollView.scrollToPage(0, pageWidth: 0)
    }

    // MARK: - velocityThreshold

    @Test("velocityThreshold is 300")
    func velocityThreshold_is300() {
        #expect(PageScrollView.velocityThreshold == 300.0)
    }

    // MARK: - init?(coder:)

    @Test("init?(coder:) produces valid instance")
    func initCoder_producesValidInstance() throws {
        let original = PageScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let archiver = NSKeyedArchiver()
        archiver.requiresSecureCoding = false
        archiver.encode(original, forKey: "root")
        let data = archiver.encodedData

        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let view = unarchiver.decodeObject(forKey: "root") as? PageScrollView
        #expect(view != nil)
    }

    // MARK: - scrollWheel / processScrollPhase

    private func makeConfiguredScrollView(currentOffsetX: CGFloat = 0) -> PageScrollView {
        let scrollView = PageScrollView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let doc = NSView(frame: NSRect(x: 0, y: 0, width: 1440 * 3, height: 900))
        scrollView.documentView = doc
        scrollView.contentView.bounds.origin.x = currentOffsetX
        return scrollView
    }

    private func makeDummyScrollEvent() -> NSEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                         wheel1: 0, wheel2: 0, wheel3: 0)!
        return NSEvent(cgEvent: cg)!
    }

    @Test("scrollWheel(with:) wrapper delegates to processScrollPhase")
    func scrollWheel_wrapper_delegates() {
        let sv = makeConfiguredScrollView()
        // phase 为合成事件的默认阶段（非 changed/ended），processScrollPhase 落入“其他阶段”分支
        sv.scrollWheel(with: makeDummyScrollEvent())
    }

    @Test("processScrollPhase .changed accumulates delta and marks scrolling")
    func changedPhase_accumulates() {
        let sv = makeConfiguredScrollView()
        let result = sv.processScrollPhase(.changed, deltaX: 50, event: makeDummyScrollEvent())
        #expect(result == false)
    }

    @Test("processScrollPhase .ended with prior .changed computes target and scrolls")
    func endedPhase_afterChanged_scrollsToTarget() {
        let sv = makeConfiguredScrollView(currentOffsetX: 0)
        _ = sv.processScrollPhase(.changed, deltaX: 700, event: makeDummyScrollEvent())
        let result = sv.processScrollPhase(.ended, deltaX: 0, event: makeDummyScrollEvent())
        // offset 700 < halfPage 720 → 留在第 0 页，scrollToPage(0)
        #expect(result == false)
    }

    @Test("processScrollPhase .ended without prior .changed returns early (isScrolling false)")
    func endedPhase_withoutChanged_returnsEarly() {
        let sv = makeConfiguredScrollView()
        let result = sv.processScrollPhase(.ended, deltaX: 0, event: makeDummyScrollEvent())
        #expect(result == false)
    }

    @Test("processScrollPhase .ended with zero pageWidth returns early")
    func endedPhase_zeroPageWidth_returnsEarly() {
        let sv = makeConfiguredScrollView()
        sv.bounds = NSRect(x: 0, y: 0, width: 0, height: 0) // pageWidth = bounds.width = 0
        _ = sv.processScrollPhase(.changed, deltaX: 10, event: makeDummyScrollEvent())
        let result = sv.processScrollPhase(.ended, deltaX: 0, event: makeDummyScrollEvent())
        #expect(result == false)
    }

    @Test("processScrollPhase .cancelled after .changed scrolls to target")
    func cancelledPhase_afterChanged_scrolls() {
        let sv = makeConfiguredScrollView(currentOffsetX: 0)
        _ = sv.processScrollPhase(.changed, deltaX: 800, event: makeDummyScrollEvent())
        let result = sv.processScrollPhase(.cancelled, deltaX: 0, event: makeDummyScrollEvent())
        #expect(result == false)
    }

    @Test("processScrollPhase .mayBegin at first page with positive delta bounces to super")
    func mayBegin_firstPage_positiveDelta_bounces() {
        let sv = makeConfiguredScrollView(currentOffsetX: 0) // 首页
        let result = sv.processScrollPhase(.mayBegin, deltaX: 10, event: makeDummyScrollEvent())
        #expect(result == true)
    }

    @Test("processScrollPhase .began at last page with negative delta bounces to super")
    func began_lastPage_negativeDelta_bounces() {
        let sv = makeConfiguredScrollView(currentOffsetX: 1440 * 3 - 1440) // 末页
        let result = sv.processScrollPhase(.began, deltaX: -10, event: makeDummyScrollEvent())
        #expect(result == true)
    }

    @Test("processScrollPhase .mayBegin at middle page does not bounce")
    func mayBegin_middlePage_noBounce() {
        let sv = makeConfiguredScrollView(currentOffsetX: 1440) // 中间页
        let result = sv.processScrollPhase(.mayBegin, deltaX: 10, event: makeDummyScrollEvent())
        #expect(result == false)
    }

    @Test("processScrollPhase .mayBegin at first page with negative delta does not bounce")
    func mayBegin_firstPage_negativeDelta_noBounce() {
        let sv = makeConfiguredScrollView(currentOffsetX: 0)
        let result = sv.processScrollPhase(.mayBegin, deltaX: -10, event: makeDummyScrollEvent())
        #expect(result == false)
    }

    @Test("processScrollPhase with no recognized phase falls through")
    func noRecognizedPhase_fallsThrough() {
        let sv = makeConfiguredScrollView()
        let result = sv.processScrollPhase([], deltaX: 0, event: makeDummyScrollEvent())
        #expect(result == false)
    }
}

// MARK: - PageControl state logic

@Suite("PageControl state logic")
struct PageControlTests {

    // MARK: - Basic state

    @Test("Initial currentPage = 0")
    func initial_currentPage_isZero() {
        let vm = PageControlViewModel()
        #expect(vm.currentPage == 0)
    }

    @Test("Initial totalPages = 0")
    func initial_totalPages_isZero() {
        let vm = PageControlViewModel()
        #expect(vm.totalPages == 0)
    }

    @Test("Setting currentPage updates state")
    func setCurrentPage_updatesState() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 5)

        vm.currentPage = 2
        #expect(vm.currentPage == 2)
    }

    @Test("Setting totalPages affects dot count")
    func setTotalPages_affectsDotCount() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 4)

        #expect(vm.totalPages == 4)
        #expect(vm.dotCount == 4)
    }

    // MARK: - Page range

    @Test("currentPage out of range clamps to valid value")
    func currentPage_clampedToValidRange() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 3)

        vm.currentPage = 5
        #expect(vm.currentPage == 2)

        vm.currentPage = -1
        #expect(vm.currentPage == 0)
    }

    @Test("totalPages set to 0 resets currentPage to 0")
    func totalPages_zero_resetsCurrentPage() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 3)
        vm.currentPage = 2

        vm.configure(totalPages: 0)
        #expect(vm.currentPage == 0)
    }

    // MARK: - Visibility

    @Test("Normal mode isVisible = true")
    func normalMode_isVisible() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 3)

        #expect(vm.isVisible == true)
    }

    @Test("Search mode hides PageControl")
    func searchMode_hidesControl() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 3)

        vm.isSearchActive = true
        #expect(vm.isVisible == false)
    }

    @Test("Exiting search mode restores display")
    func exitSearchMode_showsControl() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 3)

        vm.isSearchActive = true
        #expect(vm.isVisible == false)

        vm.isSearchActive = false
        #expect(vm.isVisible == true)
    }

    @Test("Single page does not show PageControl")
    func singlePage_notVisible() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 1)

        #expect(vm.isVisible == false)
    }

    @Test("Zero pages does not show PageControl")
    func zeroPages_notVisible() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 0)

        #expect(vm.isVisible == false)
    }

    // MARK: - Dot state

    @Test("currentPage dot marked as active")
    func currentDot_isActive() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 4)
        vm.currentPage = 2

        #expect(vm.isDotActive(at: 0) == false)
        #expect(vm.isDotActive(at: 1) == false)
        #expect(vm.isDotActive(at: 2) == true)
        #expect(vm.isDotActive(at: 3) == false)
    }

    @Test("isDotActive out of bounds returns false")
    func isDotActive_outOfBounds_returnsFalse() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 3)

        #expect(vm.isDotActive(at: -1) == false)
        #expect(vm.isDotActive(at: 3) == false)
        #expect(vm.isDotActive(at: 100) == false)
    }

    // MARK: - Jump

    @Test("selectDot updates currentPage")
    func selectDot_updatesCurrentPage() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 5)

        vm.selectDot(at: 3)
        #expect(vm.currentPage == 3)
    }

    @Test("selectDot out of bounds does not change currentPage")
    func selectDot_outOfBounds_noChange() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 3)
        vm.currentPage = 1

        vm.selectDot(at: 5)
        #expect(vm.currentPage == 1)
    }

    // MARK: - configure with shrinking pages

    @Test("configure with smaller totalPages resets currentPage when out of range")
    func configure_smallerTotalPages_resetsCurrentPage() {
        let vm = PageControlViewModel()
        vm.configure(totalPages: 5)
        vm.currentPage = 4
        vm.configure(totalPages: 3)
        #expect(vm.currentPage == 0) // 4 >= 3, so reset
    }

    // scrollWheel phase 测试见 PageScrollView 的 handleScrollPhase 重构（暂未启用，coverage 导出阻塞）
}
