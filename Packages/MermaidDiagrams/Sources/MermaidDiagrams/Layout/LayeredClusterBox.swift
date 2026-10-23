import CoreGraphics

/// One level of a cluster layout as a box on the page: its size around its content and padding, at least its minimum
/// width with the content centered across it, and where a point of the content's flow space is, from the box's top
/// left corner. The top level has no padding.
struct LayeredClusterBox {
    let direction: LayeredDirection
    let size: CGSize
    /// The content's size on the page, and its top left corner in the box.
    private let contentSize: CGSize
    private let contentOrigin: CGPoint

    /// - Parameter extent: The content's extent in flow space (`LayeredPlacement.extent`: across as x, along as y).
    init(direction: LayeredDirection, content extent: CGSize, padding: LayeredClusterPadding, minimumWidth: CGFloat) {
        self.direction = direction
        contentSize = direction.runsVertically ? extent : CGSize(width: extent.height, height: extent.width)
        size = CGSize(width: max(contentSize.width + 2 * padding.side, minimumWidth), height: contentSize.height + padding.top + padding.bottom)
        contentOrigin = CGPoint(x: (size.width - contentSize.width) / 2, y: padding.top)
    }

    /// A point of the content's flow space in the box.
    func pagePoint(_ flowPoint: CGPoint) -> CGPoint {
        let inContent: CGPoint
        switch direction {
        case .topToBottom: inContent = flowPoint
        case .bottomToTop: inContent = CGPoint(x: flowPoint.x, y: contentSize.height - flowPoint.y)
        case .leftToRight: inContent = CGPoint(x: flowPoint.y, y: flowPoint.x)
        case .rightToLeft: inContent = CGPoint(x: contentSize.width - flowPoint.y, y: flowPoint.x)
        }
        return CGPoint(x: contentOrigin.x + inContent.x, y: contentOrigin.y + inContent.y)
    }

    /// The point of the border on `side` straight across from `point`.
    func borderPoint(on side: DiagramSide, from point: CGPoint) -> CGPoint {
        switch side {
        case .top: CGPoint(x: point.x, y: 0)
        case .bottom: CGPoint(x: point.x, y: size.height)
        case .left: CGPoint(x: 0, y: point.y)
        case .right: CGPoint(x: size.width, y: point.y)
        }
    }
}
