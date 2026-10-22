import CoreGraphics

/// Where a preview card goes beside its link: below it when the card fits there, otherwise on
/// the side with more room, always within the window's margins.
enum LinkPreviewPlacement {
    static let maximumWidthPoints: CGFloat = 420
    static let maximumHeightPoints: CGFloat = 400
    /// The least room kept between the card and the edges of the window.
    static let marginPoints: CGFloat = 12
    /// The room between the link and the card.
    static let gapPoints: CGFloat = 6

    /// The card's frame in a container of `containerSize`, beside `anchor`, for a card that
    /// is `naturalHeight` tall with nothing cut; the card is cut to the room there is.
    static func frame(beside anchor: CGRect, naturalHeight: CGFloat, in containerSize: CGSize) -> CGRect {
        let width = max(0, min(maximumWidthPoints, containerSize.width - 2 * marginPoints))
        let wantedHeight = min(naturalHeight, maximumHeightPoints)
        let roomBelow = max(0, containerSize.height - marginPoints - anchor.maxY - gapPoints)
        let roomAbove = max(0, anchor.minY - gapPoints - marginPoints)
        let goesBelow = roomBelow >= wantedHeight || roomBelow >= roomAbove
        let height = min(wantedHeight, goesBelow ? roomBelow : roomAbove)
        let originY = goesBelow ? anchor.maxY + gapPoints : anchor.minY - gapPoints - height
        let originX = min(max(anchor.minX, marginPoints), max(marginPoints, containerSize.width - marginPoints - width))
        return CGRect(x: originX, y: originY, width: width, height: height)
    }
}
