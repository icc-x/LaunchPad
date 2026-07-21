import Foundation
#if canImport(AppKit)
import AppKit

/// 使用显式行优先几何的横向分页网格布局，每个 section 对应一页。
public final class AppGridFlowLayout: NSCollectionViewLayout {
    private var metrics: GridMetrics?
    private var compatibilityParameters: GridLayoutCalculator.GridParameters?
    private var attributesByIndexPath: [IndexPath: NSCollectionViewLayoutAttributes] = [:]
    private var contentSize: NSSize = .zero

    public func applyGridMetrics(_ metrics: GridMetrics) {
        self.metrics = metrics
        compatibilityParameters = nil
        invalidateLayout()
    }

    @available(*, deprecated, message: "Use applyGridMetrics(_:)")
    public func applyGridParameters(
        _ parameters: GridLayoutCalculator.GridParameters
    ) {
        metrics = nil
        compatibilityParameters = parameters
        invalidateLayout()
    }

    public override func prepare() {
        super.prepare()
        attributesByIndexPath.removeAll(keepingCapacity: true)
        guard let collectionView,
              let metrics = resolvedMetrics(for: collectionView) else {
            contentSize = .zero
            return
        }

        let sectionCount = max(collectionView.numberOfSections, 1)
        for section in 0..<collectionView.numberOfSections {
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                let row = item / max(metrics.columns, 1)
                let column = item % max(metrics.columns, 1)
                let origin = NSPoint(
                    x: CGFloat(section) * metrics.pageWidth
                        + metrics.sectionInsets.left
                        + CGFloat(column) * (metrics.itemSize.width + metrics.horizontalSpacing),
                    y: metrics.sectionInsets.top
                        + CGFloat(row) * (metrics.itemSize.height + metrics.verticalSpacing)
                )
                let indexPath = IndexPath(item: item, section: section)
                let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
                attributes.frame = NSRect(origin: origin, size: metrics.itemSize)
                attributesByIndexPath[indexPath] = attributes
            }
        }
        contentSize = NSSize(
            width: CGFloat(sectionCount) * metrics.pageWidth,
            height: metrics.sectionInsets.top
                + CGFloat(metrics.rows) * metrics.itemSize.height
                + CGFloat(max(metrics.rows - 1, 0)) * metrics.verticalSpacing
                + metrics.sectionInsets.bottom
        )
    }

    private func resolvedMetrics(
        for collectionView: NSCollectionView
    ) -> GridMetrics? {
        if let metrics { return metrics }
        guard let parameters = compatibilityParameters else { return nil }
        let fallbackWidth = 2 * parameters.horizontalMargin
            + CGFloat(parameters.columns) * parameters.iconSize
            + CGFloat(max(parameters.columns - 1, 0)) * parameters.spacing
        let fallbackHeight = parameters.topMargin + parameters.bottomMargin
            + CGFloat(parameters.rows) * (parameters.iconSize + 40)
            + CGFloat(max(parameters.rows - 1, 0)) * parameters.spacing
        let clipSize = collectionView.enclosingScrollView?.contentView.bounds.size
        let clipWidth = clipSize?.width ?? 0
        let clipHeight = clipSize?.height ?? 0
        let viewport = CGSize(
            width: clipWidth.isFinite && clipWidth > 0
                ? clipWidth : fallbackWidth,
            height: clipHeight.isFinite && clipHeight > 0
                ? clipHeight : fallbackHeight
        )
        return GridLayoutCalculator.calculate(viewportSize: viewport)
    }

    public override var collectionViewContentSize: NSSize { contentSize }

    public override func layoutAttributesForElements(
        in rect: NSRect
    ) -> [NSCollectionViewLayoutAttributes] {
        attributesByIndexPath.values
            .filter { $0.frame.intersects(rect) }
            .map { $0.copy() as! NSCollectionViewLayoutAttributes }
    }

    public override func layoutAttributesForItem(
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        attributesByIndexPath[indexPath]?.copy() as? NSCollectionViewLayoutAttributes
    }

    public override func layoutAttributesForSupplementaryView(
        ofKind elementKind: NSCollectionView.SupplementaryElementKind,
        at indexPath: IndexPath
    ) -> NSCollectionViewLayoutAttributes? {
        nil
    }

    public override func shouldInvalidateLayout(
        forBoundsChange newBounds: NSRect
    ) -> Bool {
        collectionView?.bounds.size != newBounds.size
    }

    public override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: NSPoint,
        withScrollingVelocity velocity: NSPoint
    ) -> NSPoint {
        guard let collectionView,
              let metrics = resolvedMetrics(for: collectionView) else {
            return proposedContentOffset
        }
        let totalPages = max(collectionView.numberOfSections, 1)
        let currentPage = Int(round(collectionView.enclosingScrollView?
            .contentView.bounds.origin.x ?? 0) / max(metrics.pageWidth, 1))
        let target = PageScrollView.targetPage(
            for: proposedContentOffset.x - CGFloat(currentPage) * metrics.pageWidth,
            velocity: velocity.x,
            currentPage: currentPage,
            totalPages: totalPages,
            pageWidth: metrics.pageWidth
        )
        return NSPoint(x: CGFloat(target) * metrics.pageWidth, y: 0)
    }
}
#endif
