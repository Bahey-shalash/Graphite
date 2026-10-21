import CoreGraphics
import Foundation

/// Notability's ruled and grid paper as its PDF export draws it (`Docs/Notability-format.md`, Paper): rows every page
/// width / 17 units, the first one spacing below the top, in #A3B7D3. Ruled rows run from the document's x = 0 to the
/// page width less twice the 15.9375-point inset, 0.5 points wide. Grid rows run from x = 0 across the page, and its
/// columns stand every spacing with one at the middle of the document's width, the page's full height, 0.4 points
/// wide. Both were checked only on letter paper made on a Mac.
enum NotabilityPaperRuling {
    private static let rowsPerPageWidth = 17.0
    private static let lineColor = NotebookImportColor(red: 0xA3 / 255.0, green: 0xB7 / 255.0, blue: 0xD3 / 255.0, alpha: 1)
    private static let ruledLineWidthPoints = 0.5
    private static let gridLineWidthPoints = 0.4

    /// Nil for paper without lines, or a line style not described.
    static func ruledPaper(lineStyle: NotabilityPaperLineStyle?, geometry: NotabilityPageGeometry,
                           paperColor: NotebookImportColor) -> ImportedRuledPaper? {
        let isGrid: Bool
        switch lineStyle {
        case .lines?: isGrid = false
        case .grid?: isGrid = true
        case .noLines?, .unknown?, nil: return nil
        }
        guard let pageWidth = geometry.pageWidthInUnits, let pointsPerUnit = geometry.pointsPerUnit,
              let pageSize = geometry.exportPageSizeInPoints else { return nil }
        let inset = NotabilityPageGeometry.leftInsetPoints
        let spacing = pageWidth / rowsPerPageWidth * pointsPerUnit
        return ImportedRuledPaper(paperColor: paperColor, lineColor: lineColor, lineWidth: isGrid ? gridLineWidthPoints : ruledLineWidthPoints,
                                  spacing: spacing, firstRowFromTop: spacing, leftEdge: inset,
                                  rightEdge: isGrid ? Double(pageSize.width) : Double(pageSize.width) - inset,
                                  gridColumnAnchor: isGrid ? inset + pageWidth / 2 * pointsPerUnit : nil)
    }
}
