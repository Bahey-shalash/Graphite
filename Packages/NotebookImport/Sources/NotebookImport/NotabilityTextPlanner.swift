import CoreGraphics
import Foundation

/// Plans a Notability note's typed text, its body (`Docs/Notability-format.md`, "Typed text"), as text that flows from
/// the top of the first page onto the next ones. The text has no box: Notability lays it out from the document's top
/// left (x = 0 is 15.9375 points from the page's left edge, y = 0 the first page's top), its first baseline at the
/// font's ascent and each line a line height further, as Graphite's text box lays it out with no padding. How wide
/// Notability's text runs is not in the samples (their lines are short): the text is given the page's width less the
/// same margin on both sides.
enum NotabilityTextPlanner {
    private static let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)
    /// The look of text no run covers: Notability's body text, Helvetica Neue 12.
    private static let defaultFontName = "HelveticaNeue"
    private static let defaultSizeInUnits = 12.0

    static func flowingText(of typedText: NotabilityTypedText, pageSize: CGSize, pointsPerUnit: Double, continuationBackground: ImportedPageBackground,
                            tally: inout ImportReportTally) -> ImportedFlowingText? {
        let runs = Self.runs(of: typedText, pointsPerUnit: pointsPerUnit, tally: &tally)
        guard !runs.isEmpty else { return nil }
        let margin = NotabilityPageGeometry.leftInsetPoints
        return ImportedFlowingText(runs: runs, left: margin, top: 0, width: Double(pageSize.width) - 2 * margin, continuationPageSize: pageSize,
                                   continuationBackground: continuationBackground)
    }

    /// The text cut at its runs' ranges (UTF-16 units), each in its run's font, size and colour; text between runs
    /// takes the look of the run before it, or Notability's default. A strike-through, raised or lowered text, extra
    /// line spacing or a see-through colour is counted as a style not kept.
    static func runs(of typedText: NotabilityTypedText, pointsPerUnit: Double, tally: inout ImportReportTally) -> [ImportedTextRun] {
        let utf16 = Array(typedText.text.utf16)
        guard !utf16.isEmpty else { return [] }
        let sortedRuns = typedText.runs.sorted { first, second in first.utf16Location < second.utf16Location }
        var runs: [ImportedTextRun] = []
        var position = 0
        var previousRun: NotabilityTextRun?
        func append(upTo end: Int, look run: NotabilityTextRun?) {
            guard end > position else { return }
            let text = String(decoding: utf16[position..<end], as: UTF16.self)
            runs.append(ImportedTextRun(text: text, font: .postScriptName(run?.fontName ?? defaultFontName),
                                        sizeInPoints: (run?.fontSize ?? defaultSizeInUnits) * pointsPerUnit, color: run?.color ?? black,
                                        isUnderlined: run?.isUnderlined ?? false, link: nil))
            position = end
        }
        for run in sortedRuns {
            let start = min(max(run.utf16Location, position), utf16.count)
            append(upTo: start, look: previousRun)
            if hasStyleNotKept(run) { tally.count(.textStyle) }
            append(upTo: min(run.utf16Location + run.utf16Length, utf16.count), look: run)
            previousRun = run
        }
        append(upTo: utf16.count, look: previousRun)
        return runs
    }

    private static func hasStyleNotKept(_ run: NotabilityTextRun) -> Bool {
        run.isStruckThrough || (run.baselineOffset ?? 0) != 0 || (run.lineSpacing ?? 0) > 0 || (run.color?.alpha ?? 1) < 1
    }
}
