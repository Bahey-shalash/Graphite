import CoreGraphics
import Foundation

/// Plans a Goodnotes page for Graphite (`Docs/Goodnotes-Notability-import-phase-3-design.md`, steps 1 and 2): the
/// page is its paper's size in points, its background the paper's PDF page (template paper and imported PDFs alike),
/// and its ink the strokes' center lines sampled into PencilKit points. Goodnotes units are 6/11 of a point with the
/// same origin and direction as the page canvas, so a unit position times 6/11 is the point position. Highlighter
/// strokes come after all other ink, where Goodnotes draws them.
public enum GoodnotesPagePlanner {
    static let pointsPerUnit = 6.0 / 11.0
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// `pageNumber` is the page's place in the notebook, from 1.
    public static func plan(_ page: GoodnotesPage, pageNumber: Int) -> ImportedPageOutcome {
        var tally = ImportReportTally()
        for issue in page.issues { tally.add(.goodnotesReadingIssue(issue)) }
        guard let paper = page.descriptor.paper else {
            tally.add(.pageWithoutPaper)
            return .leftOut(sourcePageNumber: pageNumber, report: tally.report)
        }
        let background: ImportedPageBackground
        if let file = paper.attachment?.file {
            background = .pdfPage(ImportedSourceFile(path: file), pageNumber: Int(clamping: paper.pdfPageNumber))
        } else {
            background = .plainColor(white)
            tally.add(.backgroundFileMissing)
        }
        var strokes: [ImportedStroke] = []
        var highlighterStrokes: [ImportedStroke] = []
        for element in page.elements {
            switch element.content {
            case .stroke(let stroke):
                let planned = GoodnotesStrokePlanner.strokes(for: stroke, tally: &tally).compactMap { planned in planned.keepingFiniteSamples() }
                if stroke.isHighlighter { highlighterStrokes += planned } else { strokes += planned }
            case .picture: tally.count(.element(.picture))
            case .shapeFill: tally.count(.element(.shapeFill))
            case .textBox, .rtfTextBox, .rtfTextElement: tally.count(.element(.textBox))
            case .stickyNote: tally.count(.element(.stickyNote))
            case .unknown: tally.count(.element(.unknownKind))
            }
        }
        return .planned(ImportedPagePlan(sourcePageNumber: pageNumber, sizeInPoints: paper.sizeInPoints, background: background,
                                         strokes: strokes + highlighterStrokes, report: tally.report))
    }
}
