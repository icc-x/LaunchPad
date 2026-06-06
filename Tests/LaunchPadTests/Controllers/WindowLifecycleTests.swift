import Testing
@testable import LaunchPad

@Suite("WindowLifecycle state machine")
struct WindowLifecycleTests {

    // MARK: - Helper

    private func makeSUT() -> (WindowLifecycle, MockWindowLifecycleDelegate) {
        let delegate = MockWindowLifecycleDelegate()
        let lifecycle = WindowLifecycle(delegate: delegate)
        return (lifecycle, delegate)
    }

    // MARK: - hidden -> toggle -> opening -> visible

    @Test("hidden state toggle -> transitions through opening -> visible")
    func hidden_toggle_opensToVisible() {
        let (sut, delegate) = makeSUT()

        #expect(sut.state == .hidden)

        sut.handleToggle()

        #expect(delegate.stateChanges.count >= 1)
        #expect(delegate.stateChanges.first == .opening)
        #expect(sut.state == .opening)

        delegate.completeOpenAnimation()

        #expect(sut.state == .visible)
    }

    // MARK: - visible -> toggle -> closing -> hidden

    @Test("visible state toggle -> transitions through closing -> hidden")
    func visible_toggle_closesToHidden() {
        let (sut, delegate) = makeSUT()

        sut.handleToggle()
        delegate.completeOpenAnimation()
        #expect(sut.state == .visible)
        delegate.stateChanges.removeAll()

        sut.handleToggle()
        #expect(delegate.stateChanges.contains(.closing))

        delegate.completeCloseAnimation()
        #expect(sut.state == .hidden)
    }

    // MARK: - visible -> ESC -> closing -> hidden

    @Test("visible state ESC -> transitions through closing -> hidden")
    func visible_esc_closesToHidden() {
        let (sut, delegate) = makeSUT()

        sut.handleToggle()
        delegate.completeOpenAnimation()
        delegate.stateChanges.removeAll()

        sut.handleEscape()
        #expect(delegate.stateChanges.contains(.closing))

        delegate.completeCloseAnimation()
        #expect(sut.state == .hidden)
    }

    // MARK: - visible -> click app -> launching -> closing -> hidden

    @Test("visible state click app -> launching -> closing -> hidden")
    func visible_clickApp_launchesAndCloses() {
        let (sut, delegate) = makeSUT()

        sut.handleToggle()
        delegate.completeOpenAnimation()
        delegate.stateChanges.removeAll()

        sut.handleAppClick(bundleId: "com.apple.Safari")
        #expect(delegate.stateChanges.contains(.launching))
        #expect(delegate.launchedBundleId == "com.apple.Safari")

        delegate.completeLaunchAnimation()
        #expect(delegate.stateChanges.contains(.closing))

        delegate.completeCloseAnimation()
        #expect(sut.state == .hidden)
    }

    // MARK: - opening -> toggle -> ignored

    @Test("opening state toggle again -> ignored (debounce)")
    func opening_toggle_ignored() {
        let (sut, delegate) = makeSUT()

        sut.handleToggle()
        #expect(sut.state == .opening)
        delegate.stateChanges.removeAll()

        sut.handleToggle()
        #expect(sut.state == .opening)
        #expect(delegate.stateChanges.isEmpty)
    }

    // MARK: - visible -> focus lost -> closing -> hidden

    @Test("visible state focus lost -> auto closing -> hidden")
    func visible_focusLost_autoClose() {
        let (sut, delegate) = makeSUT()

        sut.handleToggle()
        delegate.completeOpenAnimation()
        #expect(sut.state == .visible)
        delegate.stateChanges.removeAll()

        sut.handleFocusLost()
        #expect(delegate.stateChanges.contains(.closing))

        delegate.completeCloseAnimation()
        #expect(sut.state == .hidden)
    }

    // MARK: - hidden -> ESC -> no-op

    @Test("hidden state ESC -> no operation")
    func hidden_esc_noOp() {
        let (sut, delegate) = makeSUT()

        #expect(sut.state == .hidden)

        sut.handleEscape()
        #expect(sut.state == .hidden)
        #expect(delegate.stateChanges.isEmpty)
    }

    // MARK: - Boundary: closing state toggle ignored

    @Test("closing state toggle -> ignored")
    func closing_toggle_ignored() {
        let (sut, delegate) = makeSUT()

        sut.handleToggle()
        delegate.completeOpenAnimation()
        sut.handleToggle()
        #expect(sut.state == .closing)
        delegate.stateChanges.removeAll()

        sut.handleToggle()
        #expect(sut.state == .closing)
    }

    // MARK: - Boundary: hidden state focus lost no-op

    @Test("hidden state focus lost -> no operation")
    func hidden_focusLost_noOp() {
        let (sut, delegate) = makeSUT()

        sut.handleFocusLost()
        #expect(sut.state == .hidden)
        #expect(delegate.stateChanges.isEmpty)
    }
}

// MARK: - Mock Delegate

/// Two-phase Mock — records animation requests but doesn't auto-complete.
/// Tests must explicitly call completeXxxAnimation() to advance the state machine.
final class MockWindowLifecycleDelegate: WindowLifecycleDelegate {
    var stateChanges: [WindowLifecycle.State] = []
    var launchedBundleId: String?

    private var pendingLifecycle: WindowLifecycle?

    func lifecycle(_ lifecycle: WindowLifecycle, didTransitionTo state: WindowLifecycle.State) {
        stateChanges.append(state)
    }

    func lifecycle(_ lifecycle: WindowLifecycle, shouldLaunchApp bundleId: String) {
        launchedBundleId = bundleId
    }

    func lifecycleRequestsOpenAnimation(_ lifecycle: WindowLifecycle) {
        pendingLifecycle = lifecycle
    }

    func lifecycleRequestsCloseAnimation(_ lifecycle: WindowLifecycle) {
        pendingLifecycle = lifecycle
    }

    func lifecycleRequestsLaunchAnimation(_ lifecycle: WindowLifecycle, bundleId: String) {
        pendingLifecycle = lifecycle
    }

    // MARK: - Phase 2: explicitly complete animations

    func completeOpenAnimation() {
        pendingLifecycle?.openAnimationDidFinish()
    }

    func completeCloseAnimation() {
        pendingLifecycle?.closeAnimationDidFinish()
    }

    func completeLaunchAnimation() {
        pendingLifecycle?.launchAnimationDidFinish()
    }
}
