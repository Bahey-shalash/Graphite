import CoreGraphics
import Foundation

/// Plans a page of a Notability note for Graphite (`Docs/Goodnotes-Notability-import-phase-3-design.md`, steps 1
/// and 2). The note is one continuous document; each page is a PDF page of Notability's export size, showing the
/// document from `topInUnits` down, with x = 0 at 15.9375 points from the page's left edge and `pointsPerUnit` points
/// per unit (`Docs/Notability-format.md`, Coordinates and pages). The page is an imported PDF page when the note has
/// one for it, and plain paper of the note's colour otherwise; a curve becomes PencilKit points along its cubic
/// chain, its width the curve's width times the knot's factor, and is cut where it leaves the page.
public enum NotabilityPagePlanner {
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)

    private struct PageTransform {
        let topInUnits: Double
        let pointsPerUnit: Double

        func point(_ unitPoint: CGPoint) -> CGPoint {
            CGPoint(x: NotabilityPageGeometry.leftInsetPoints + unitPoint.x * pointsPerUnit, y: (unitPoint.y - topInUnits) * pointsPerUnit)
        }
    }

    public static func plan(_ page: NotabilityPage, note: NotabilityNote) -> ImportedPageOutcome {
        var tally = ImportReportTally()
        guard let pageSize = note.pageGeometry.exportPageSizeInPoints, let pointsPerUnit = note.pageGeometry.pointsPerUnit else {
            tally.add(.pageGeometryUnknown)
            return .leftOut(sourcePageNumber: page.pageNumber, report: tally.report)
        }
        let transform = PageTransform(topInUnits: page.topInUnits, pointsPerUnit: pointsPerUnit)
        let background = background(of: page.pageNumber, note: note, tally: &tally)
        var strokes: [ImportedStroke] = []
        for curve in page.curves {
            if case .unknown(let rawStyle) = curve.style { tally.add(.notabilityReadingIssue(.curveStyleUnknown(rawStyle: rawStyle))) }
            if curve.style == .highlighter { tally.count(.highlighter) }
            strokes += NotabilityCurveSampling.strokes(for: curve, transform: transform.point, pointsPerUnit: pointsPerUnit,
                                                       pageHeightInPoints: pageSize.height)
        }
        for _ in page.shapes { tally.count(.element(.shape)) }
        for _ in page.pictures { tally.count(.element(.picture)) }
        if page.pageNumber == 1 && !note.typedText.text.isEmpty { tally.count(.element(.typedText)) }
        return .planned(ImportedPagePlan(sourcePageNumber: page.pageNumber, sizeInPoints: pageSize, background: background, strokes: strokes,
                                         report: tally.report))
    }

    private static func background(of pageNumber: Int, note: NotabilityNote, tally: inout ImportReportTally) -> ImportedPageBackground {
        if let importedPage = note.importedPDFPages.first(where: { importedPage in importedPage.documentPageNumber == pageNumber }) {
            if let pdfFile = importedPage.pdfFile { return .pdfPage(ImportedSourceFile(path: pdfFile), pageNumber: importedPage.pdfPageNumber ?? 1) }
            tally.add(.backgroundFileMissing)
        }
        switch note.paper.lineStyle {
        case .lines?, .grid?, .unknown?: tally.add(.paperRulingNotDrawn)
        case .noLines?, nil: break
        }
        return .plainColor(note.paper.identifier == .legacyBlack ? black : white)
    }
}
