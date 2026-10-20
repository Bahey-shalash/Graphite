import CoreGraphics
import Foundation

/// Why a paper's ruling cannot be drawn.
public enum PaperRulingError: Error, Hashable, Sendable {
    case lineColorNotReadable(String)
    case lineWidthNotUsable(Double)
    case rowsNotOnThePage(firstRowFromTop: Double, leftEdge: Double, rightEdge: Double)
    case gridColumnAnchorNotUsable(Double)
}

/// The ruling of ruled or grid paper that is not one of Graphite's own, such as an imported notebook's: its line colour
/// and width, where its rows run and where its columns stand. All positions are in points from the page's top-left
/// corner. Rows start `firstRowFromTop` below the top edge and repeat every `PaperSpecification.spacing` down to the
/// bottom edge, each from `leftEdge` to `rightEdge`. Grid columns stand at `gridColumnAnchor` and every spacing to
/// both sides of it, each the page's full height. A paper without a ruling draws Graphite's own lines, unchanged.
public struct PaperRuling: Sendable, Codable, Equatable {
    /// At most this wide: a line wider than a third of an inch is not a ruling.
    private static let maximumLineWidth = 24.0

    /// `#rrggbb`, in place of the paper's line colour and strength.
    public var lineColorHex: String
    public var lineWidth: Double
    public var firstRowFromTop: Double
    public var leftEdge: Double
    public var rightEdge: Double
    /// One grid column's distance from the left edge; nil on ruled paper.
    public var gridColumnAnchor: Double?

    public init(lineColorHex: String, lineWidth: Double, firstRowFromTop: Double, leftEdge: Double, rightEdge: Double, gridColumnAnchor: Double?) {
        self.lineColorHex = lineColorHex
        self.lineWidth = lineWidth
        self.firstRowFromTop = firstRowFromTop
        self.leftEdge = leftEdge
        self.rightEdge = rightEdge
        self.gridColumnAnchor = gridColumnAnchor
    }

    func validate(forPageWidth width: Double, height: Double) throws(PaperRulingError) {
        guard PDFTemplateGenerator.TemplateColors.color(hex: lineColorHex) != nil else { throw .lineColorNotReadable(lineColorHex) }
        guard lineWidth.isFinite, lineWidth > 0, lineWidth <= Self.maximumLineWidth else { throw .lineWidthNotUsable(lineWidth) }
        guard firstRowFromTop.isFinite, leftEdge.isFinite, rightEdge.isFinite, firstRowFromTop >= 0, firstRowFromTop <= height,
              leftEdge >= 0, leftEdge < rightEdge, rightEdge <= width else {
            throw .rowsNotOnThePage(firstRowFromTop: firstRowFromTop, leftEdge: leftEdge, rightEdge: rightEdge)
        }
        if let gridColumnAnchor, !gridColumnAnchor.isFinite { throw .gridColumnAnchorNotUsable(gridColumnAnchor) }
    }

    /// Strokes the rows, and on grid paper the columns, in the context's current colour and width. The context's y
    /// runs upwards from the bottom edge, as in every PDF page.
    func strokeLines(of paper: PaperSpecification, in context: CGContext) {
        for rowFromTop in stride(from: firstRowFromTop, through: paper.height, by: paper.spacing) {
            context.move(to: CGPoint(x: leftEdge, y: paper.height - rowFromTop))
            context.addLine(to: CGPoint(x: rightEdge, y: paper.height - rowFromTop))
        }
        if paper.template == .grid, let gridColumnAnchor {
            let firstColumn = gridColumnAnchor - (gridColumnAnchor / paper.spacing).rounded(.down) * paper.spacing
            for column in stride(from: firstColumn, through: paper.width, by: paper.spacing) {
                context.move(to: CGPoint(x: column, y: 0))
                context.addLine(to: CGPoint(x: column, y: paper.height))
            }
        }
        context.strokePath()
    }
}
