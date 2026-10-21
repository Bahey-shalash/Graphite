import CoreGraphics
import Foundation

/// Plans a Goodnotes page for Graphite (`Docs/Goodnotes-Notability-import-phase-3-design.md`, steps 1 to 4 and 8): the
/// page is its paper's size in points, its background the paper's PDF page (template paper and imported PDFs alike),
/// its ink the strokes' center lines sampled into PencilKit points, its pictures their files placed and turned
/// (`GoodnotesPicturePlanner`), and its typed text, sticky notes included, text boxes (`GoodnotesTextPlanner`). Goodnotes units are 6/11 of a point with the same origin and direction as the page
/// canvas, so a unit position times 6/11 is the point position. Highlighter strokes come after all other ink, where
/// Goodnotes draws them.
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
        let content = plannedContent(of: page.elements, tally: &tally)
        return .planned(ImportedPagePlan(sourcePageNumber: pageNumber, sizeInPoints: paper.sizeInPoints, background: background,
                                         strokes: content.strokes, pictures: content.pictures, textBoxes: content.textBoxes,
                                         isBookmarked: page.descriptor.isBookmarked,
                                         report: tally.report))
    }

    /// The page's ink, highlighters last, its pictures and its text boxes, each in drawing order. Goodnotes stacks
    /// pictures, text and ink in one drawing order, and Graphite draws a page's pictures under all its ink and its text
    /// boxes over it: a picture drawn after some ink other than highlighter (which Goodnotes draws over everything) now
    /// has that ink over it, and is counted.
    private static func plannedContent(of elements: [GoodnotesElement], tally: inout ImportReportTally)
        -> (strokes: [ImportedStroke], pictures: [ImportedPicture], textBoxes: [ImportedTextBox]) {
        var strokes: [ImportedStroke] = [], highlighterStrokes: [ImportedStroke] = [], pictures: [ImportedPicture] = []
        var textBoxes: [ImportedTextBox] = []
        for element in elements {
            switch element.content {
            case .stroke(let stroke):
                let planned = GoodnotesStrokePlanner.strokes(for: stroke, tally: &tally).compactMap { planned in planned.keepingFiniteSamples() }
                if stroke.isHighlighter { highlighterStrokes += planned } else { strokes += planned }
            case .picture(let picture):
                guard let plannedPicture = GoodnotesPicturePlanner.picture(for: picture, tally: &tally) else { break }
                if !strokes.isEmpty { tally.count(.pictureMovedUnderInk) }
                pictures.append(plannedPicture)
            case .shapeFill: tally.count(.element(.shapeFill))
            case .textBox(let textBox):
                guard let plannedBox = GoodnotesTextPlanner.textBox(for: textBox, tally: &tally) else {
                    tally.count(.textBoxNotPlaced)
                    break
                }
                textBoxes.append(plannedBox)
            case .rtfTextBox(let textBox): textBoxes.append(GoodnotesTextPlanner.textBox(for: textBox))
            case .stickyNote(let stickyNote): textBoxes.append(GoodnotesTextPlanner.textBox(for: stickyNote, tally: &tally))
            case .rtfTextElement: tally.count(.element(.textWithoutFrame))
            case .unknown: tally.count(.element(.unknownKind))
            }
        }
        return (strokes + highlighterStrokes, pictures, textBoxes)
    }
}
