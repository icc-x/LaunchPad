import Foundation
#if canImport(AppKit)
import AppKit

/// 搜索输入框
public class SearchBar: NSSearchField {

    /// 搜索查询变化回调
    public var onQueryChanged: ((String) -> Void)?

    private var isShown = false

    /// 测试注入：驱动 hide 动画完成回调（同 EmptyStateView.hideCompletionRunner）。
    internal var hideCompletionRunner: (
        @escaping @MainActor @Sendable () -> Void
    ) -> Void = { $0() }

    // MARK: - Init

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSearchBar()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSearchBar()
    }

    private func setupSearchBar() {
        placeholderString = "Search Applications"
        sendsSearchStringImmediately = true
        delegate = self
        font = NSFont.systemFont(ofSize: 16)
        isBezeled = true
        bezelStyle = .roundedBezel

        // Start hidden
        alphaValue = 0
        isHidden = true

        hideCompletionRunner = { [weak self] completion in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = AnimationConstants.windowExpand.duration
                self?.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { completion() }
            })
        }
    }

    // MARK: - Show / Hide

    public func show(animated: Bool = true) {
        guard !isShown else { return }
        isShown = true
        isHidden = false

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = AnimationConstants.windowExpand.duration
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }

        window?.makeFirstResponder(self)
    }

    public func hide(animated: Bool = true) {
        guard isShown else { return }
        isShown = false
        stringValue = ""

        if animated {
            hideCompletionRunner { [weak self] in
                MainActor.assumeIsolated {
                    self?.isHidden = true
                }
            }
        } else {
            alphaValue = 0
            isHidden = true
        }
    }

    public func clearAndFocus() {
        stringValue = ""
        onQueryChanged?("")
        window?.makeFirstResponder(self)
    }
}

// MARK: - NSSearchFieldDelegate

extension SearchBar: NSSearchFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        onQueryChanged?(stringValue)
    }

    public func searchFieldDidStartSearching(_ sender: NSSearchField) {
        // 用户按回车触发搜索时（与 controlTextDidChange 互补）
        onQueryChanged?(stringValue)
    }

    public func searchFieldDidEndSearching(_ sender: NSSearchField) {
        // User clicked the "x" button
        onQueryChanged?("")
    }
}
#endif
