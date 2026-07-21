import Foundation
import LaunchPadProtocols

public enum LayoutProjection {
    public static func paginate(
        items: [PageItem],
        metrics: GridMetrics
    ) -> [[PageItem]] {
        guard !items.isEmpty else { return [[]] }
        let capacity = max(metrics.itemsPerPage, 1)
        return stride(from: 0, to: items.count, by: capacity).map { start in
            Array(items[start..<min(start + capacity, items.count)])
        }
    }

    public static func project(
        pages: [PageItem],
        itemsByPage: [Int64: [PageItem]],
        metrics: GridMetrics
    ) -> [[PageItem]] {
        let orderedItems = pages
            .sorted { $0.ordering < $1.ordering }
            .flatMap { page in
                (itemsByPage[page.id] ?? []).sorted { $0.ordering < $1.ordering }
            }
        return paginate(items: orderedItems, metrics: metrics)
    }
}
