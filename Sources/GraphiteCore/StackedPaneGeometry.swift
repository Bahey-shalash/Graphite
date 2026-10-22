import Foundation

/// Where the panes of a stacked tab group go, as Obsidian lays out stacked tabs after Andy
/// Matuschak's sliding notes: panes of one width side by side in a row that scrolls
/// sideways, each with its title on a spine at its leading edge. A pane scrolled past the
/// leading edge stops with its spine showing and the next pane slides over it; a pane
/// beyond the trailing edge waits there with its spine showing. Later panes are drawn over
/// earlier ones.
public struct StackedPaneGeometry: Equatable, Sendable {
    public let paneCount: Int
    public let containerWidth: Double
    public let spineWidth: Double
    /// A pane's whole width: its spine and its content.
    public let paneWidth: Double

    /// A pane's content is `preferredContentWidth` wide (Obsidian's stacked panes are 700
    /// pixels), narrower when the container cannot show it with every other pane's spine,
    /// and never narrower than `minimumContentWidth`, where panes overlap instead.
    public init(paneCount: Int, containerWidth: Double, spineWidth: Double, preferredContentWidth: Double, minimumContentWidth: Double) {
        self.paneCount = max(paneCount, 1)
        self.containerWidth = max(containerWidth, 0)
        self.spineWidth = spineWidth
        let widthBesideEverySpine = self.containerWidth - spineWidth * Double(self.paneCount)
        paneWidth = spineWidth + max(minimumContentWidth, min(preferredContentWidth, widthBesideEverySpine))
    }

    public var contentWidth: Double { paneWidth - spineWidth }
    /// The width the row scrolls over.
    public var rowWidth: Double { paneWidth * Double(paneCount) }
    public var maximumScrollOffset: Double { max(0, rowWidth - containerWidth) }

    /// The pane's leading edge, from the container's leading edge, at a scroll offset.
    public func displayedLeadingEdge(ofPane index: Int, scrollOffset: Double) -> Double {
        let unstuck = Double(index) * paneWidth - scrollOffset
        let leadingStop = Double(index) * spineWidth
        let trailingStop = max(leadingStop, containerWidth - Double(paneCount - index) * spineWidth)
        return min(max(unstuck, leadingStop), trailingStop)
    }

    /// How much of the pane's content shows: not covered by the next pane, nor past the
    /// container's trailing edge.
    public func visibleContentWidth(ofPane index: Int, scrollOffset: Double) -> Double {
        let leadingEdge = displayedLeadingEdge(ofPane: index, scrollOffset: scrollOffset)
        var trailingEdge = min(leadingEdge + paneWidth, containerWidth)
        if index + 1 < paneCount { trailingEdge = min(trailingEdge, displayedLeadingEdge(ofPane: index + 1, scrollOffset: scrollOffset)) }
        return max(0, trailingEdge - (leadingEdge + spineWidth))
    }

    /// The scroll offset closest to `currentOffset` that shows the pane whole, with the
    /// spines of the panes before it at the leading edge and those after it at the trailing
    /// edge. When the pane cannot show whole, its leading part shows.
    public func scrollOffset(showingPane index: Int, from currentOffset: Double) -> Double {
        let largestOffset = Double(index) * (paneWidth - spineWidth)
        let smallestOffset = Double(index + 1) * paneWidth - containerWidth + Double(paneCount - 1 - index) * spineWidth
        let offset = min(max(currentOffset, smallestOffset), largestOffset)
        return min(max(offset, 0), maximumScrollOffset)
    }

    /// The pane drawn at a point, measured from the container's leading edge: the last of
    /// the panes there, since later panes are drawn over earlier ones.
    public func pane(at position: Double, scrollOffset: Double) -> Int? {
        guard position >= 0, position < containerWidth else { return nil }
        return (0..<paneCount).last { index in
            let leadingEdge = displayedLeadingEdge(ofPane: index, scrollOffset: scrollOffset)
            return position >= leadingEdge && position < leadingEdge + paneWidth
        }
    }
}
