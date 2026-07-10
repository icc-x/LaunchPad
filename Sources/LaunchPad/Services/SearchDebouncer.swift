import Foundation
import LaunchPadProtocols

/// 搜索防抖器 — 100ms debounce，空查询和 Backspace 立即触发
///
/// - 空查询 → 立即触发（清空搜索）
/// - 查询变短（Backspace）→ 立即触发
/// - 其他输入 → 防抖 100ms 后触发（取消之前的 pending）
@MainActor
public final class SearchDebouncer {

    private let debounceInterval: TimeInterval
    private let scheduler: Scheduler
    @preconcurrency private let searchHandler: (String) -> Void
    private var lastQuery: String = ""

    /// - Parameters:
    ///   - debounceInterval: 防抖间隔，默认 0.1s
    ///   - scheduler: 调度器（可注入 MockScheduler 测试）
    ///   - searchHandler: 搜索回调（保证在 MainActor 上调用）
    @preconcurrency
    public init(
        debounceInterval: TimeInterval = 0.1,
        scheduler: Scheduler,
        searchHandler: @escaping (String) -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.scheduler = scheduler
        self.searchHandler = searchHandler
    }

    /// 提交搜索查询
    /// - Parameter query: 用户输入的搜索文本
    public func search(query: String) {
        // 空查询立即触发（清空搜索）
        if query.isEmpty {
            scheduler.cancelPending()
            lastQuery = query
            searchHandler(query)
            return
        }

        // Backspace: 查询变短 → 立即触发
        if query.count < lastQuery.count {
            scheduler.cancelPending()
            lastQuery = query
            searchHandler(query)
            return
        }

        // 正常输入: 取消上次 pending，延迟触发
        lastQuery = query
        scheduler.cancelPending()
        let handler = searchHandler
        nonisolated(unsafe) let unsafeHandler = handler
        let unsafeQuery = query
        scheduler.schedule(after: debounceInterval) {
            // DispatchQueueScheduler 在主线程调用此闭包
            // MockScheduler.fireLatest() 也在测试主线程调用
            MainActor.assumeIsolated {
                unsafeHandler(unsafeQuery)
            }
        }
    }

    /// 取消所有待执行搜索
    public func cancelPending() {
        scheduler.cancelPending()
        lastQuery = ""
    }
}
