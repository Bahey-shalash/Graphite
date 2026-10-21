import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore
import NotebookImport

/// Puts a page's imported text on its PDF page as Graphite text boxes (`PDFEdit.addTextBox`), over its pictures and
/// ink: Goodnotes' text boxes, sticky notes and older text boxes where the plan places them, and the part of
/// Notability's flowing text this page holds (`ImportedFlowingTextPlacement`). Each linked run gets its `/Link`
/// annotation with the box. A box with no text is not written; one that cannot be placed is counted.
enum ImportedPageText {
    /// What became of a page's text.
    struct Placed: Equatable {
        var boxCount = 0
        var notPlacedCount = 0
        var fontsReplacedRunCount = 0
        var stylesNotKeptRunCount = 0

        mutating func add(_ other: Placed) {
            boxCount += other.boxCount
            notPlacedCount += other.notPlacedCount
            fontsReplacedRunCount += other.fontsReplacedRunCount
            stylesNotKeptRunCount += other.stylesNotKeptRunCount
        }
    }

    static func place(_ textBoxes: [ImportedTextBox], onPageAt pageIndex: Int, of document: PDFDocument, pageSize: CGSize) throws -> Placed {
        var placed = Placed()
        guard !textBoxes.isEmpty, let page = document.page(at: pageIndex) else { return placed }
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: pageSize)
        for importedBox in textBoxes {
            let text = ImportedTextRuns(importedBox.content)
            placed.fontsReplacedRunCount += text.fontsReplacedRunCount
            placed.stylesNotKeptRunCount += text.stylesNotKeptRunCount
            guard !text.isEmpty else { continue }
            let style = PDFTextBoxStyle(alignment: text.alignment, fillColor: importedBox.fillColor.map(textColor), padding: importedBox.padding)
            placed.add(place(text.runs, style: style, origin: importedBox.origin, width: importedBox.width, height: importedBox.height,
                             rotationRadiansClockwise: importedBox.rotationRadiansClockwise, onPageAt: pageIndex, of: document, coordinates: coordinates))
        }
        return placed
    }

    /// One box from a top-left corner in page points, as tall as `height` or as its text.
    static func place(_ runs: [PDFTextRun], style: PDFTextBoxStyle, origin: CGPoint, width: Double, height: Double?, rotationRadiansClockwise: Double,
                      onPageAt pageIndex: Int, of document: PDFDocument, coordinates: PageCoordinates) -> Placed {
        var placed = Placed()
        let box = PDFTextBox(runs: runs, origin: coordinates.pdfPoint(fromOverlay: origin), width: width, height: height ?? 1,
                             rotationRadians: rotationRadiansClockwise, style: style)
        let sizedBox = height == nil ? PDFTextBoxLayout.fitted(box) : box
        do {
            try PDFPageManager.apply(.addTextBox(page: pageIndex, textBox: sizedBox), to: document, drawsInkOutlines: true)
            placed.boxCount = 1
        } catch {
            // A box whose geometry is not a number or whose text is past a box's limits (`PDFTextBox.hasValidGeometry`).
            placed.notPlacedCount = 1
        }
        return placed
    }

    /// The page's report with what its text could not keep: fonts replaced, styles not kept (added to the planner's
    /// count of them) and boxes not placed.
    static func report(_ entries: [ImportReportEntry], adding placed: Placed) -> [ImportReportEntry] {
        var merged = entries
        func add(_ count: Int, to entry: (Int) -> ImportReportEntry, matching existingCount: (ImportReportEntry) -> Int?) {
            guard count > 0 else { return }
            if let entryIndex = merged.firstIndex(where: { existing in existingCount(existing) != nil }), let earlier = existingCount(merged[entryIndex]) {
                merged[entryIndex] = entry(earlier + count)
            } else {
                merged.append(entry(count))
            }
        }
        add(placed.stylesNotKeptRunCount, to: { count in .textStylesNotKept(runCount: count) }, matching: { entry in
            if case .textStylesNotKept(let count) = entry { count } else { nil }
        })
        add(placed.fontsReplacedRunCount, to: { count in .fontsReplaced(runCount: count) }, matching: { entry in
            if case .fontsReplaced(let count) = entry { count } else { nil }
        })
        add(placed.notPlacedCount, to: { count in .textBoxesNotPlaced(count: count) }, matching: { entry in
            if case .textBoxesNotPlaced(let count) = entry { count } else { nil }
        })
        return merged
    }

    static func textColor(_ color: NotebookImportColor) -> PDFTextColor {
        PDFTextColor(red: color.red, green: color.green, blue: color.blue)
    }
}

/// Notability's typed text as it flows from page to page while the notebook is written: the page that starts it gives
/// its runs, and each page from there holds the whole lines that fit between its top (or the text's top on the first
/// page) and its bottom edge, in one box; the rest waits for the next page. Pages are added after the last source page
/// while text is left (`continuationPage`).
///
/// A page's lines are measured on a piece of the text at a time, doubled while it all fits, so a long text is laid out
/// in work proportional to its length rather than once per page (FR-104); lines before a piece's end break as they do
/// in the whole text.
struct ImportedFlowingTextPlacement {
    private struct Pending {
        var runs: [PDFTextRun]
        let left: Double
        let width: Double
        let continuationPageSize: CGSize
        let continuationBackground: ImportedPageBackground
    }

    /// The UTF-16 units first measured for a page; doubled while they all fit.
    static let firstMeasuredLength = 4_096

    private var pending: Pending?
    private(set) var fontsReplacedRunCount = 0

    var hasTextLeft: Bool { pending.map { pending in !pending.runs.isEmpty } ?? false }

    /// Starts the text a plan's page carries; text still waiting from an earlier page is replaced (a plan starts it only
    /// on its first page).
    mutating func start(_ flowingText: ImportedFlowingText) -> ImportedPageText.Placed {
        let text = ImportedTextRuns(flowingText.runs)
        pending = Pending(runs: text.runs, left: flowingText.left, width: flowingText.width, continuationPageSize: flowingText.continuationPageSize,
                          continuationBackground: flowingText.continuationBackground)
        return ImportedPageText.Placed(fontsReplacedRunCount: text.fontsReplacedRunCount)
    }

    /// The plan of the next page added for the text left: the note's paper, nothing else on it.
    func continuationPlan(sourcePageNumber: Int) -> ImportedPagePlan? {
        guard let pending, hasTextLeft else { return nil }
        return ImportedPagePlan(sourcePageNumber: sourcePageNumber, sizeInPoints: pending.continuationPageSize, background: pending.continuationBackground,
                                strokes: [], report: [])
    }

    /// Places on the page the lines that fit below `top` (page points from the page's top), and keeps the rest.
    mutating func placeLines(onPageAt pageIndex: Int, of document: PDFDocument, pageSize: CGSize, top: Double) throws -> ImportedPageText.Placed {
        guard var current = pending, !current.runs.isEmpty, let page = document.page(at: pageIndex) else { return ImportedPageText.Placed() }
        let coordinates = try PageCoordinates(cropBox: page.bounds(for: .cropBox), overlaySize: pageSize)
        let availableHeight = Double(pageSize.height) - top
        let style = PDFTextBoxStyle(alignment: .left, padding: 0)
        let fittingLength = Self.fittingLength(of: current.runs, width: current.width, height: availableHeight, style: style)
        let (onPage, rest) = PDFTextRun.split(current.runs, atUTF16Offset: fittingLength)
        current.runs = rest
        pending = current
        guard !onPage.isEmpty else { return ImportedPageText.Placed() }
        return ImportedPageText.place(onPage, style: style, origin: CGPoint(x: current.left, y: top), width: current.width, height: nil,
                                      rotationRadiansClockwise: 0, onPageAt: pageIndex, of: document, coordinates: coordinates)
    }

    /// The UTF-16 units of the runs that fit `height` in whole lines; at least the first line, so a line taller than a
    /// page still moves the text on.
    static func fittingLength(of runs: [PDFTextRun], width: Double, height: Double, style: PDFTextBoxStyle) -> Int {
        let totalLength = runs.reduce(0) { total, run in total + run.text.utf16.count }
        var measuredLength = min(totalLength, firstMeasuredLength)
        while true {
            let piece = measuredLength < totalLength ? PDFTextRun.split(runs, atUTF16Offset: boundary(of: runs, near: measuredLength)).before : runs
            let pieceLength = piece.reduce(0) { total, run in total + run.text.utf16.count }
            let layout = PDFTextBoxLayout(box: PDFTextBox(runs: piece, origin: .zero, width: width, height: max(height, 1), style: style))
            let fitting = layout.textLengthFitting(height: height)
            if fitting < pieceLength || pieceLength >= totalLength {
                guard fitting == 0, let firstLine = layout.lines.first else { return fitting }
                let range = CTLineGetStringRange(firstLine)
                return range.location + range.length
            }
            measuredLength = min(totalLength, measuredLength * 2)
        }
    }

    /// The offset, at or before `offset`, that does not cut a UTF-16 surrogate pair in two.
    private static func boundary(of runs: [PDFTextRun], near offset: Int) -> Int {
        var start = 0
        for run in runs {
            let length = run.text.utf16.count
            if offset > start, offset < start + length {
                let units = Array(run.text.utf16)
                return UTF16.isLeadSurrogate(units[offset - start - 1]) ? offset - 1 : offset
            }
            start += length
        }
        return offset
    }
}
