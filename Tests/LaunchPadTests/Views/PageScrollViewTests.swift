import Testing
import CoreGraphics
@testable import LaunchPad

@Suite("PageScrollView target page calculation")
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
}
