import XCTest
import AppKit
import SwiftUI
@testable import Textual
import GraphiteCore
@testable import GraphiteUI

/// Equation numbers as drawn: rendered in a window and read back pixel by pixel.
@MainActor
final class UiNumberedEquationTests: XCTestCase {
    private static let textSize: Double = 17

    /// A block drawn at `width` points, two pixels to the point.
    private struct Rendering {
        let bitmap: NSBitmapImageRep
        let size: CGSize

        func isInk(horizontalPixel: Int, verticalPixel: Int) -> Bool {
            guard let color = bitmap.colorAt(x: horizontalPixel, y: verticalPixel)?.usingColorSpace(.deviceRGB) else { return false }
            return color.alphaComponent > 0.5 && (color.redComponent + color.greenComponent + color.blueComponent) / 3 < 0.5
        }

        var inkPixelCount: Int { inkPixelCount(inColumns: 0...(bitmap.pixelsWide - 1)) }

        func inkPixelCount(inRows rows: ClosedRange<Int>) -> Int {
            rows.reduce(0) { count, verticalPixel in
                count + (0..<bitmap.pixelsWide).filter { horizontalPixel in isInk(horizontalPixel: horizontalPixel, verticalPixel: verticalPixel) }.count
            }
        }

        func inkPixelCount(inColumns columns: ClosedRange<Int>) -> Int {
            (0..<bitmap.pixelsHigh).reduce(0) { count, verticalPixel in
                count + columns.filter { horizontalPixel in isInk(horizontalPixel: horizontalPixel, verticalPixel: verticalPixel) }.count
            }
        }

        /// Runs of pixel columns with ink, apart from each other by more than `gap` columns.
        func inkColumnRuns(separatedByMoreThan gap: Int, inRows rows: Range<Int>? = nil) -> [ClosedRange<Int>] {
            let inkColumns = (0..<bitmap.pixelsWide).filter { horizontalPixel in
                (rows ?? 0..<bitmap.pixelsHigh).contains { verticalPixel in isInk(horizontalPixel: horizontalPixel, verticalPixel: verticalPixel) }
            }
            return runs(of: inkColumns, separatedByMoreThan: gap)
        }

        /// Runs of pixel rows with ink between the columns `columns`.
        func inkRowRuns(inColumns columns: ClosedRange<Int>, separatedByMoreThan gap: Int = 0) -> [ClosedRange<Int>] {
            let inkRows = (0..<bitmap.pixelsHigh).filter { verticalPixel in
                columns.contains { horizontalPixel in isInk(horizontalPixel: horizontalPixel, verticalPixel: verticalPixel) }
            }
            return runs(of: inkRows, separatedByMoreThan: gap)
        }

        private func runs(of positions: [Int], separatedByMoreThan gap: Int) -> [ClosedRange<Int>] {
            var runs: [ClosedRange<Int>] = []
            for position in positions {
                if let last = runs.last, position - last.upperBound <= gap + 1 {
                    runs[runs.count - 1] = last.lowerBound...position
                } else {
                    runs.append(position...position)
                }
            }
            return runs
        }
    }

    /// The display formula `markdown` drawn as reading view and Live Preview draw a math
    /// block, in a column `width` points wide.
    private func rendering(ofDisplayMath markdown: String, width: CGFloat) async throws -> Rendering {
        let prepared = ObsidianPreviewText.applyingSoftLineBreaks(to: ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: true, paletteHexByName: [:]))
        let block = ObsidianMarkdownText(markdown: prepared, root: URL(fileURLWithPath: NSTemporaryDirectory()), textSize: Self.textSize, navigate: { _, _ in }, scrollToHeading: { _ in })
            .frame(maxWidth: .infinity)
            .frame(width: width)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let hostingView = NSHostingView(rootView: block)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        defer { window.contentView = nil }
        // The Markdown renderer parses its text after it first appears.
        for _ in 0..<10 {
            hostingView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let size = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["GRAPHITE_EQUATION_RENDERINGS"] {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(abs(markdown.hashValue))-\(Int(width)).png"))
        }
        return Rendering(bitmap: bitmap, size: size)
    }

    /// Wider than the space between two glyphs of a formula, narrower than MathJax's
    /// 0.8em between a formula and its number.
    private static let numberGapPixels = 16

    func testNumberStandsAtTheRightEdgeAndTheFormulaWhereItIsWithoutANumber() async throws {
        let unnumbered = try await rendering(ofDisplayMath: "$$\nE = mc^2\n$$", width: 400)
        let numbered = try await rendering(ofDisplayMath: "$$\nE = mc^2 \\tag{1}\n$$", width: 400)
        let formula = try XCTUnwrap(unnumbered.inkColumnRuns(separatedByMoreThan: Self.numberGapPixels).first)
        let numberedRuns = numbered.inkColumnRuns(separatedByMoreThan: Self.numberGapPixels)
        XCTAssertEqual(numberedRuns.count, 2, "The formula, then its number.")
        // Within a pixel: the two are drawn by different views, and each is placed on whole pixels.
        let numberedFormula = try XCTUnwrap(numberedRuns.first)
        XCTAssertEqual(numberedFormula.lowerBound, formula.lowerBound, accuracy: 1, "The formula stays centered, where it is without a number.")
        XCTAssertEqual(numberedFormula.upperBound, formula.upperBound, accuracy: 1)
        let number = try XCTUnwrap(numberedRuns.last)
        XCTAssertGreaterThanOrEqual(number.upperBound, numbered.bitmap.pixelsWide - 8, "The number ends at the right edge of the column.")
        XCTAssertLessThan(number.upperBound, numbered.bitmap.pixelsWide)
        XCTAssertEqual(numbered.size, unnumbered.size, "A numbered formula's line is as tall as the formula's.")
    }

    func testNumberStandsOnTheBaselineOfItsFormula() async throws {
        // The same letter as the formula, as a starred tag: drawn on one baseline, both
        // have the same rows of ink.
        let rendering = try await rendering(ofDisplayMath: "$$x \\tag*{$x$}$$", width: 300)
        let runs = rendering.inkColumnRuns(separatedByMoreThan: Self.numberGapPixels)
        XCTAssertEqual(runs.count, 2)
        assertSameRows(rendering.inkRowRuns(inColumns: runs[0]).first, rendering.inkRowRuns(inColumns: runs[1]).first)
    }

    /// Two runs of pixel rows that are the same glyph on the same baseline: equal within a
    /// pixel, since the formula and its number are separate views, each placed on whole pixels.
    private func assertSameRows(_ numberRows: ClosedRange<Int>?, _ formulaRows: ClosedRange<Int>?, _ message: String = "", line: UInt = #line) {
        guard let numberRows, let formulaRows else { return XCTFail("No ink. " + message, line: line) }
        XCTAssertEqual(numberRows.lowerBound, formulaRows.lowerBound, accuracy: 1, message, line: line)
        XCTAssertEqual(numberRows.upperBound, formulaRows.upperBound, accuracy: 1, message, line: line)
    }

    func testEachNumberStandsOnTheBaselineOfItsRow() async throws {
        let markdown = "$$\n\\begin{gather}\nx \\tag*{$x$} \\\\\n\\frac{\\frac{1}{2}}{\\frac{3}{4}} \\\\\nx \\tag*{$x$}\n\\end{gather}\n$$"
        for markdownWithAlignment in [markdown, markdown.replacingOccurrences(of: "gather", with: "align")] {
            let rendering = try await rendering(ofDisplayMath: markdownWithAlignment, width: 300)
            let runs = rendering.inkColumnRuns(separatedByMoreThan: Self.numberGapPixels)
            XCTAssertEqual(runs.count, 2, markdownWithAlignment)
            let formulaRows = rendering.inkRowRuns(inColumns: runs[0], separatedByMoreThan: 2)
            let numberRows = rendering.inkRowRuns(inColumns: runs[1], separatedByMoreThan: 2)
            XCTAssertEqual(numberRows.count, 2, markdownWithAlignment)
            assertSameRows(numberRows.first, formulaRows.first, "The first row's number is on its baseline.")
            assertSameRows(numberRows.last, formulaRows.last, "The last row's number is on its baseline, below the tall row.")
        }
    }

    func testNarrowColumnPutsTheNumberBelowAndCutsNothingOff() async throws {
        let wide = try await rendering(ofDisplayMath: "$$\nE = mc^2 \\tag{1}\n$$", width: 400)
        let narrow = try await rendering(ofDisplayMath: "$$\nE = mc^2 \\tag{1}\n$$", width: 100)
        XCTAssertEqual(narrow.size.width, 100)
        XCTAssertGreaterThan(narrow.size.height, wide.size.height, "The number goes on a line of its own.")
        XCTAssertEqual(Double(narrow.inkPixelCount), Double(wide.inkPixelCount), accuracy: Double(wide.inkPixelCount) * 0.03,
                       "Every glyph of the formula and its number is drawn.")
        let numberRows = try XCTUnwrap(narrow.inkRowRuns(inColumns: 0...(narrow.bitmap.pixelsWide - 1), separatedByMoreThan: 4).last)
        let numberColumns = try XCTUnwrap(narrow.inkColumnRuns(separatedByMoreThan: 4, inRows: numberRows.lowerBound..<(numberRows.upperBound + 1)).last)
        XCTAssertGreaterThanOrEqual(numberColumns.upperBound, narrow.bitmap.pixelsWide - 8, "The number stays at the right edge.")
    }

    func testFormulaWiderThanTheColumnIsBrokenAsWithoutANumberAndKeepsItsNumber() async throws {
        let formula = "a + b + c + d + e + f"
        let unnumberedWide = try await rendering(ofDisplayMath: "$$" + formula + "$$", width: 400)
        let numberedWide = try await rendering(ofDisplayMath: "$$" + formula + " \\tag{1}$$", width: 400)
        let unnumberedNarrow = try await rendering(ofDisplayMath: "$$" + formula + "$$", width: 60)
        let numberedNarrow = try await rendering(ofDisplayMath: "$$" + formula + " \\tag{1}$$", width: 60)
        XCTAssertGreaterThan(unnumberedNarrow.size.height, unnumberedWide.size.height, "The formula is broken into lines.")
        XCTAssertEqual(numberedNarrow.size.width, 60)
        let number = try XCTUnwrap(numberedWide.inkColumnRuns(separatedByMoreThan: Self.numberGapPixels).last)
        let numberInk = numberedWide.inkPixelCount(inColumns: number)
        XCTAssertGreaterThan(numberInk, 0)
        // The number has a line of its own below the formula.
        let numberRows = try XCTUnwrap(numberedNarrow.inkRowRuns(inColumns: 0...(numberedNarrow.bitmap.pixelsWide - 1), separatedByMoreThan: 4).last)
        let narrowNumberInk = numberedNarrow.inkPixelCount(inRows: numberRows)
        XCTAssertEqual(Double(narrowNumberInk), Double(numberInk), accuracy: Double(numberInk) * 0.1, "All of the number is drawn.")
        XCTAssertGreaterThanOrEqual(Double(numberedNarrow.inkPixelCount - narrowNumberInk), Double(unnumberedNarrow.inkPixelCount) * 0.95,
                                    "All of the broken formula is drawn, as it is without a number.")
    }

    func testNarrowColumnDrawsARowByRowFormulaWithEveryNumber() async throws {
        let markdown = "$$\n\\begin{align}\na + b + c &= d \\tag{1} \\\\\ne &= f + g \\tag{2}\n\\end{align}\n$$"
        let wide = try await rendering(ofDisplayMath: markdown, width: 400)
        XCTAssertEqual(wide.inkColumnRuns(separatedByMoreThan: Self.numberGapPixels).count, 2)
        let narrow = try await rendering(ofDisplayMath: markdown, width: 130)
        XCTAssertEqual(narrow.size.width, 130)
        XCTAssertEqual(Double(narrow.inkPixelCount), Double(wide.inkPixelCount), accuracy: Double(wide.inkPixelCount) * 0.05)
        XCTAssertGreaterThan(narrow.size.height, wide.size.height)
    }

    // MARK: Shared with Live Preview

    func testLivePreviewMathBlockIsTheSameNumberedFormula() throws {
        let source = "$$\n\\begin{align}\na &= b \\tag{1}\n\\end{align}\n$$"
        let livePreviewText = LivePreviewText.prepared(source, colorsEnabled: true, paletteHexByName: [:])
        let readingText = ObsidianPreviewText.applyingSoftLineBreaks(to: ObsidianInlineMarkup.preparedForReading(source, colorsEnabled: true, paletteHexByName: [:]))
        let equation = try XCTUnwrap(ObsidianInlineMarkup.numberedEquation(aloneIn: livePreviewText))
        XCTAssertEqual(ObsidianInlineMarkup.numberedEquation(aloneIn: readingText), equation)
        XCTAssertTrue(NumberedEquationView.canDraw(equation, textSize: Self.textSize))
    }

    // MARK: Where a number cannot stand at the right

    func testNumberedFormulaInAListItemTakesItsNumberAfterItsRow() throws {
        let markdown = ObsidianInlineMarkup.preparedForReading("- Energy\n  $$\n  E = mc^2 \\tag{1}\n  $$", colorsEnabled: true, paletteHexByName: [:])
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: Self.textSize).attributedString(for: markdown)
        let formulas = attributed.runs.compactMap { run in run[AttributeScopes.TextualAttributes.AttachmentAttribute.self]?.description }
        XCTAssertEqual(formulas, ["$$ E = mc^2  \\qquad \\text{(}\\text{1}\\text{)} $$"])
    }

    func testFormulaTheTypesetterCannotDrawStaysItsSource() throws {
        let markdown = ObsidianInlineMarkup.preparedForReading("$$\\unknowncommand{x} \\tag{1}$$", colorsEnabled: true, paletteHexByName: [:])
        let equation = try XCTUnwrap(ObsidianInlineMarkup.numberedEquation(aloneIn: markdown))
        XCTAssertFalse(NumberedEquationView.canDraw(equation, textSize: Self.textSize))
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: Self.textSize).attributedString(for: markdown)
        XCTAssertTrue(String(attributed.characters).hasPrefix("$$ \\unknowncommand{x}"), String(attributed.characters))
    }
}
