import Foundation
#if canImport(AppKit)
import AppKit

/// 自定义横向 FlowLayout — 每页一个 section，支持分页滚动
public class AppGridFlowLayout: NSCollectionViewFlowLayout {

    private var gridParams: GridLayoutCalculator.GridParameters?

    // MARK: - Configuration

    public func applyGridParameters(_ params: GridLayoutCalculator.GridParameters) {
        self.gridParams = params

        let itemWidth = params.iconSize + params.spacing
        let itemHeight = params.iconSize + 40 // icon + label + padding

        itemSize = NSSize(width: itemWidth, height: itemHeight)
        minimumInteritemSpacing = params.spacing
        minimumLineSpacing = params.spacing
        sectionInset = NSEdgeInsets(
            top: params.topMargin,
            left: params.horizontalMargin,
            bottom: params.bottomMargin,
            right: params.horizontalMargin
        )

        scrollDirection = .horizontal
        headerReferenceSize = .zero

        invalidateLayout()
    }

    // MARK: - Snap to Page

    override public func targetContentOffset(forProposedContentOffset proposedContentOffset: NSPoint, withScrollingVelocity velocity: NSPoint) -> NSPoint {
        guard let collectionView = collectionView,
              let params = gridParams else {
            return super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        }

        let pageWidth = collectionView.bounds.width
        let currentPage = PageScrollView.targetPage(
            for: proposedContentOffset.x,
            velocity: velocity.x,
            currentPage: Int(proposedContentOffset.x / max(pageWidth, 1)),
            totalPages: max(1, Int(collectionView.bounds.width > 0 ? collectionView.bounds.width / pageWidth : 1)),
            pageWidth: pageWidth
        )

        return NSPoint(x: CGFloat(currentPage) * pageWidth, y: 0)
    }

    // MARK: - Vertical centering

    override public func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        let attributes = super.layoutAttributesForElements(in: rect)

        guard let collectionView = collectionView else { return attributes }

        // Vertically center the items
        for attr in attributes {
            let verticalOffset = (collectionView.bounds.height - attr.frame.height) / 2
            attr.frame.origin.y = verticalOffset
        }

        return attributes
    }
}
#endif
