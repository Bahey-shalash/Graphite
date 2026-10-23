import CoreGraphics
import Foundation

/// The page around a Sankey chart and its labels, as Pele sizes it: the room the chart and its labels take, as wide as
/// the title when it is wider, centered, the bold title above with a gap, and padding around. Places the chart's nodes,
/// bands and labels on it.
struct SankeyPage {
    let size: CGSize
    let placedTitle: DiagramTextBlock?
    /// Where the chart's origin is on the page.
    private let offset: CGVector
    private let nodeWidth: Double

    init(labels: SankeyLabelPlacement, title: DiagramTextBlock?, nodeWidth: Double) {
        self.nodeWidth = nodeWidth
        let padding = SankeyLayoutEngine.padding
        let titleHeight = title.map { title in title.size.height + SankeyLayoutEngine.titleGap } ?? 0
        let chartExtent = CGFloat(labels.maximumX - labels.minimumX)
        let inner = max(chartExtent, title?.size.width ?? 0)
        offset = CGVector(dx: padding - CGFloat(labels.minimumX) + (inner - chartExtent) / 2, dy: padding + titleHeight - CGFloat(labels.minimumY))
        let pageSize = CGSize(width: (inner + 2 * padding).rounded(.up),
                              height: (CGFloat(labels.maximumY - labels.minimumY) + titleHeight + 2 * padding).rounded(.up))
        size = pageSize
        placedTitle = title.map { title in
            var placed = title
            placed.center = CGPoint(x: pageSize.width / 2, y: padding + title.size.height / 2)
            return placed
        }
    }

    /// A node's bar, at least a point tall.
    func node(_ node: SankeyPlacement.Node, seriesIndex: Int) -> SankeyLayoutNode {
        SankeyLayoutNode(seriesIndex: seriesIndex, frame: CGRect(x: CGFloat(node.x) + offset.dx, y: CGFloat(node.y) + offset.dy,
                                                                 width: CGFloat(nodeWidth), height: max(CGFloat(node.height), 1)))
    }

    /// A band from its source bar's right side to its target bar's left side, at least a point thick.
    func link(_ link: SankeyPlacement.Link, nodes: [SankeyPlacement.Node]) -> SankeyLayoutLink {
        SankeyLayoutLink(sourceSeriesIndex: link.source, targetSeriesIndex: link.target,
                         startX: CGFloat(nodes[link.source].x + nodeWidth) + offset.dx, endX: CGFloat(nodes[link.target].x) + offset.dx,
                         sourceY: CGFloat(link.sourceY) + offset.dy, targetY: CGFloat(link.targetY) + offset.dy,
                         halfThickness: max(CGFloat(link.thickness), 1) / 2)
    }

    /// A label's name and value on one line from its left side, measured in `measurer`.
    func label(name: String, value: String?, label: SankeyLabelPlacement.Label, measurer: some DiagramTextMeasuring) -> SankeyLayoutLabel {
        let left = CGFloat(label.left) + offset.dx
        let middle = CGFloat(label.middle) + offset.dy
        var nameBlock = DiagramTextBlock(label: DiagramLabel(name), measurer: measurer, maximumWidth: .greatestFiniteMagnitude)
        nameBlock.center = CGPoint(x: left + nameBlock.size.width / 2, y: middle)
        let valueBlock = value.map { value in
            var block = DiagramTextBlock(label: DiagramLabel(value), measurer: measurer, maximumWidth: .greatestFiniteMagnitude)
            block.center = CGPoint(x: left + CGFloat(label.width) - block.size.width / 2, y: middle)
            return block
        }
        return SankeyLayoutLabel(name: nameBlock, value: valueBlock)
    }
}
