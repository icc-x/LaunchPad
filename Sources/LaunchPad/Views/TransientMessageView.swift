import AppKit

/// 短暂显示调用方提供文本的无障碍提示视图。
@MainActor
public final class TransientMessageView: NSView {
    /// 锁同时保护 generation 与 pending item；二者不得在锁外读取或修改。
    private final class HideState: @unchecked Sendable {
        private let lock = NSLock()
        private var generation = 0
        private var pendingItem: DispatchWorkItem?

        func begin() -> Int {
            lock.lock()
            defer { lock.unlock() }
            generation += 1
            pendingItem?.cancel()
            pendingItem = nil
            return generation
        }

        func replace(with item: DispatchWorkItem, for candidateGeneration: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard candidateGeneration == generation else {
                item.cancel()
                return false
            }
            pendingItem?.cancel()
            pendingItem = item
            return true
        }

        func consume(ifCurrent candidateGeneration: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard candidateGeneration == generation else { return false }
            generation += 1
            pendingItem?.cancel()
            pendingItem = nil
            return true
        }

        func invalidate() {
            lock.lock()
            defer { lock.unlock() }
            generation += 1
            pendingItem?.cancel()
            pendingItem = nil
        }
    }

    private var label = NSTextField(labelWithString: "")
    private let hideState = HideState()

    var scheduleHide: (TimeInterval, DispatchWorkItem) -> Void = { delay, item in
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: item
        )
    }

    var postAnnouncement: (String, NSAccessibilityPriorityLevel) -> Void = { message, priority in
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue,
            ]
        )
    }

    public private(set) var message: String?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        if let decodedLabel = subviews.first(where: { $0 is NSTextField }) as? NSTextField {
            label = decodedLabel
        }
        setup()
    }

    deinit {
        hideState.invalidate()
    }

    public func show(message: String, duration: TimeInterval = 2.5) {
        let currentGeneration = hideState.begin()
        self.message = message
        label.stringValue = message
        setAccessibilityLabel(message)
        isHidden = false
        postAnnouncement(message, .high)

        let item = DispatchWorkItem { [weak self] in
            self?.hide(ifCurrentGeneration: currentGeneration)
        }
        if hideState.replace(with: item, for: currentGeneration) {
            scheduleHide(duration, item)
        }
    }

    public func hide() {
        hideState.invalidate()
        message = nil
        label.stringValue = ""
        setAccessibilityLabel("")
        isHidden = true
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.92).cgColor
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        if label.superview == nil {
            addSubview(label)
        }
        constraints
            .filter {
                ($0.firstItem as AnyObject?) === label ||
                    ($0.secondItem as AnyObject?) === label
            }
            .forEach(removeConstraint)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("")
        isHidden = true
    }

    private func hide(ifCurrentGeneration candidateGeneration: Int) {
        guard hideState.consume(ifCurrent: candidateGeneration) else { return }
        message = nil
        label.stringValue = ""
        setAccessibilityLabel("")
        isHidden = true
    }
}
