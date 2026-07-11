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

    // MARK: - Guard branches: handleAppClick from non-visible state

    @Test("hidden state handleAppClick -> ignored (guard else branch)")
    func hidden_appClick_ignored() {
        let (sut, delegate) = makeSUT()
        #expect(sut.state == .hidden)

        sut.handleAppClick(bundleId: "com.example.Test")
        #expect(sut.state == .hidden)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("opening state handleAppClick -> ignored (guard else branch)")
    func opening_appClick_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        #expect(sut.state == .opening)
        delegate.stateChanges.removeAll()

        sut.handleAppClick(bundleId: "com.example.Test")
        #expect(sut.state == .opening)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("closing state handleAppClick -> ignored (guard else branch)")
    func closing_appClick_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        sut.handleToggle()
        #expect(sut.state == .closing)
        delegate.stateChanges.removeAll()

        sut.handleAppClick(bundleId: "com.example.Test")
        #expect(sut.state == .closing)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("launching state handleAppClick -> ignored (guard else branch)")
    func launching_appClick_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        sut.handleAppClick(bundleId: "com.example.Test")
        #expect(sut.state == .launching)
        delegate.stateChanges.removeAll()

        sut.handleAppClick(bundleId: "com.example.Other")
        #expect(sut.state == .launching)
        #expect(delegate.stateChanges.isEmpty)
    }

    // MARK: - Guard branches: openAnimationDidFinish from non-opening state

    @Test("hidden state openAnimationDidFinish -> ignored (guard else branch)")
    func hidden_openAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.openAnimationDidFinish()
        #expect(sut.state == .hidden)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("visible state openAnimationDidFinish -> ignored (guard else branch)")
    func visible_openAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        delegate.stateChanges.removeAll()

        sut.openAnimationDidFinish()
        #expect(sut.state == .visible)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("closing state openAnimationDidFinish -> ignored (guard else branch)")
    func closing_openAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        sut.handleToggle()
        delegate.stateChanges.removeAll()

        sut.openAnimationDidFinish()
        #expect(sut.state == .closing)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("launching state openAnimationDidFinish -> ignored (guard else branch)")
    func launching_openAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        sut.handleAppClick(bundleId: "test")
        delegate.stateChanges.removeAll()

        sut.openAnimationDidFinish()
        #expect(sut.state == .launching)
        #expect(delegate.stateChanges.isEmpty)
    }

    // MARK: - Guard branches: closeAnimationDidFinish from non-closing state

    @Test("hidden state closeAnimationDidFinish -> ignored (guard else branch)")
    func hidden_closeAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.closeAnimationDidFinish()
        #expect(sut.state == .hidden)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("opening state closeAnimationDidFinish -> ignored (guard else branch)")
    func opening_closeAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.stateChanges.removeAll()

        sut.closeAnimationDidFinish()
        #expect(sut.state == .opening)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("visible state closeAnimationDidFinish -> ignored (guard else branch)")
    func visible_closeAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        delegate.stateChanges.removeAll()

        sut.closeAnimationDidFinish()
        #expect(sut.state == .visible)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("launching state closeAnimationDidFinish -> ignored (guard else branch)")
    func launching_closeAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        sut.handleAppClick(bundleId: "test")
        delegate.stateChanges.removeAll()

        sut.closeAnimationDidFinish()
        #expect(sut.state == .launching)
        #expect(delegate.stateChanges.isEmpty)
    }

    // MARK: - Guard branches: launchAnimationDidFinish from non-launching state

    @Test("hidden state launchAnimationDidFinish -> ignored (guard else branch)")
    func hidden_launchAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.launchAnimationDidFinish()
        #expect(sut.state == .hidden)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("opening state launchAnimationDidFinish -> ignored (guard else branch)")
    func opening_launchAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.stateChanges.removeAll()

        sut.launchAnimationDidFinish()
        #expect(sut.state == .opening)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("visible state launchAnimationDidFinish -> ignored (guard else branch)")
    func visible_launchAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        delegate.stateChanges.removeAll()

        sut.launchAnimationDidFinish()
        #expect(sut.state == .visible)
        #expect(delegate.stateChanges.isEmpty)
    }

    @Test("closing state launchAnimationDidFinish -> ignored (guard else branch)")
    func closing_launchAnimationFinish_ignored() {
        let (sut, delegate) = makeSUT()
        sut.handleToggle()
        delegate.completeOpenAnimation()
        sut.handleToggle()
        delegate.stateChanges.removeAll()

        sut.launchAnimationDidFinish()
        #expect(sut.state == .closing)
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
