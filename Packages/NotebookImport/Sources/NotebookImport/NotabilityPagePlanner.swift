import CoreGraphics
import Foundation

/// Plans a page of a Notability note for Graphite (`Docs/Goodnotes-Notability-import-phase-3-design.md`, steps 1
/// to 3). The note is one continuous document; each page is a PDF page of Notability's export size, showing the
/// document from `topInUnits` down, with x = 0 at 15.9375 points from the page's left edge and `pointsPerUnit` points
/// per unit (`Docs/Notability-format.md`, Coordinates and pages). The page is an imported PDF page when the note has
/// one for it, and the note's paper otherwise, ruled as Notability rules it; a curve becomes PencilKit points along
/// its cubic chain, its width the curve's width times the knot's factor, and is cut where it leaves the page; a line
/// shape becomes ink drawn in its place among the curves. The typed text starts on the first page and flows onto the
/// next ones (`NotabilityTextPlanner`).
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
        let strokes = strokes(of: page, transform: transform, pageHeightInPoints: pageSize.height, tally: &tally)
        var flowingText: ImportedFlowingText?
        if page.pageNumber == 1 {
            if note.reflowState == .reflowable { tally.add(.pageWidthAssumed) }
            var continuationTally = ImportReportTally()
            let continuationBackground = Self.background(of: Int.max, note: note, tally: &continuationTally)
            flowingText = NotabilityTextPlanner.flowingText(of: note.typedText, pageSize: pageSize, pointsPerUnit: pointsPerUnit,
                                                            continuationBackground: continuationBackground, tally: &tally)
        }
        return .planned(ImportedPagePlan(sourcePageNumber: page.pageNumber, sizeInPoints: pageSize, background: background, strokes: strokes,
                                         pictures: pictures(of: page, transform: transform), flowingText: flowingText,
                                         isBookmarked: isBookmarked(page.pageNumber, note: note), report: tally.report))
    }

    /// The page's curves in drawing order, each shape drawn just before the first curve its `drawnBeforeCurveIndex`
    /// does not pass (a shape drawn after the page's last curve comes last). A shape that is not a line, or has no
    /// width, is counted as left out.
    private static func strokes(of page: NotabilityPage, transform: PageTransform, pageHeightInPoints: Double,
                                tally: inout ImportReportTally) -> [ImportedStroke] {
        var pendingShapes = page.shapes.enumerated().sorted { first, second in
            (first.element.drawnBeforeCurveIndex, first.offset) < (second.element.drawnBeforeCurveIndex, second.offset)
        }.map(\.element)[...]
        var strokes: [ImportedStroke] = []
        func drawShapes(before curveIndex: Int?) {
            while let shape = pendingShapes.first, curveIndex.map({ index in shape.drawnBeforeCurveIndex <= index }) ?? true {
                pendingShapes.removeFirst()
                strokes += shapeStrokes(shape, transform: transform, pageHeightInPoints: pageHeightInPoints, tally: &tally)
            }
        }
        for curve in page.curves {
            drawShapes(before: curve.index)
            if case .unknown(let rawStyle) = curve.style { tally.add(.notabilityReadingIssue(.curveStyleUnknown(rawStyle: rawStyle))) }
            if curve.style == .highlighter { tally.count(.highlighter) }
            strokes += NotabilityCurveSampling.strokes(for: curve, transform: transform.point, pointsPerUnit: transform.pointsPerUnit,
                                                       pageHeightInPoints: pageHeightInPoints)
        }
        drawShapes(before: nil)
        return strokes
    }

    private static func shapeStrokes(_ shape: NotabilityShape, transform: PageTransform, pageHeightInPoints: Double,
                                     tally: inout ImportReportTally) -> [ImportedStroke] {
        guard let strokes = NotabilityShapeSampling.strokes(for: shape, transform: transform.point, pointsPerUnit: transform.pointsPerUnit,
                                                            pageHeightInPoints: pageHeightInPoints) else {
            tally.count(.element(.shape))
            return []
        }
        tally.count(.shapeAsInk)
        if !(shape.dashPattern ?? []).isEmpty { tally.count(.dashes) }
        return strokes
    }

    /// The page's pictures by `zIndex`, the lowest first (pictures of one index keep the note's order). Notability
    /// draws every picture under all ink, as Graphite does, so their order needs no report. The frame is the shown
    /// (cropped) part's origin and size; the crop is in the image's pixels, which the export draws stretched to fill it.
    private static func pictures(of page: NotabilityPage, transform: PageTransform) -> [ImportedPicture] {
        let ordered = page.pictures.enumerated().sorted { first, second in
            (first.element.zIndex, first.offset) < (second.element.zIndex, second.offset)
        }
        return ordered.map { _, picture in
            let origin = transform.point(picture.origin)
            let size = CGSize(width: picture.size.width * transform.pointsPerUnit, height: picture.size.height * transform.pointsPerUnit)
            return ImportedPicture(file: ImportedSourceFile(path: picture.file), frame: CGRect(origin: origin, size: size),
                                   rotationRadiansClockwise: picture.rotationRadiansClockwise, cropRectangleInPixels: picture.cropRectangle,
                                   isFlippedHorizontally: picture.isFlippedHorizontally, isFlippedVertically: picture.isFlippedVertically)
        }
    }

    /// Notability keeps a bookmark only on a page made from an imported PDF's page.
    private static func isBookmarked(_ pageNumber: Int, note: NotabilityNote) -> Bool {
        note.importedPDFPages.contains { importedPage in importedPage.documentPageNumber == pageNumber && importedPage.isBookmarked }
    }

    private static func background(of pageNumber: Int, note: NotabilityNote, tally: inout ImportReportTally) -> ImportedPageBackground {
        if let importedPage = note.importedPDFPages.first(where: { importedPage in importedPage.documentPageNumber == pageNumber }) {
            if let pdfFile = importedPage.pdfFile { return .pdfPage(ImportedSourceFile(path: pdfFile), pageNumber: importedPage.pdfPageNumber ?? 1) }
            tally.add(.backgroundFileMissing)
        }
        let paperColor = note.paper.identifier == .legacyBlack ? black : white
        if let ruledPaper = NotabilityPaperRuling.ruledPaper(lineStyle: note.paper.lineStyle, geometry: note.pageGeometry, paperColor: paperColor) {
            return .ruledPaper(ruledPaper)
        }
        if case .unknown? = note.paper.lineStyle { tally.add(.paperRulingNotDrawn) }
        return .plainColor(paperColor)
    }
}
