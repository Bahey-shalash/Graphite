import XCTest
import AppKit
import SwiftUI
import GraphiteCore
@testable import Textual
import SwiftUIMath

/// Regression tests for the patches Graphite carries in its vendored Textual
/// (Vendor/textual/GRAPHITE-PATCHES.md) and SwiftUIMath (Vendor/swiftui-math/GRAPHITE-PATCHES.md).
/// Upstream's own tests are not vendored.
@MainActor
final class AppProjectTextualPatchTests: XCTestCase {
    private static let objectReplacementCharacter: Character = "\u{FFFC}"

    private func inlineMathFormulas(in text: String) throws -> [String] {
        try PatternTokenizer(patterns: [.mathBlock, .mathInline]).tokenize(text)
            .filter { token in token.type == .mathInline }
            .compactMap(\.capturedContent)
    }

    private func mathAttachmentCount(inMarkdown markdown: String) throws -> Int {
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        return String(try parser.attributedString(for: markdown).characters)
            .filter { character in character == Self.objectReplacementCharacter }.count
    }

    // MARK: Patch 4, Obsidian's inline math delimiters

    func testInlineMathNeedsNoSpaceInsideTheDollarsAndNoDigitAfterTheClosingOne() throws {
        XCTAssertEqual(try inlineMathFormulas(in: "$x$"), ["x"])
        XCTAssertEqual(try inlineMathFormulas(in: "$x_1$, $x_2$"), ["x_1", "x_2"])
        XCTAssertEqual(try inlineMathFormulas(in: "It costs $5 and $10"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "$x$2"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "$ x$ and $x $"), [])
        XCTAssertEqual(try inlineMathFormulas(in: "a \\$ sign: $\\$5$"), ["\\$5"])
    }

    func testPricesStayTextWhileFormulasBecomeAttachments() throws {
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: "It costs $5 and $10."), 0)
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: "Energy $E = mc^2$ and $k_n$."), 2)
    }

    // MARK: Patch 5, formulas that cannot be typeset stay as text

    func testUnparseableFormulaStaysAsItsSource() throws {
        XCTAssertTrue(MathAttachment.canTypeset("x^2"))
        XCTAssertFalse(MathAttachment.canTypeset("\\begin{notanenvironment}x\\end{notanenvironment}"))
        let markdown = "See $\\begin{notanenvironment}x\\end{notanenvironment}$ here."
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        XCTAssertEqual(String(try parser.attributedString(for: markdown).characters), markdown)
    }

    // MARK: Patch 3, inline math for other text views

    func testInlineMathRenderingMeasuresFormulasAndRejectsUnparseableOnes() {
        let metrics = InlineMathRendering.metrics(for: "x^2", fontSize: 17)
        XCTAssertGreaterThan(metrics?.width ?? 0, 0)
        XCTAssertGreaterThan(metrics?.ascent ?? 0, 0)
        XCTAssertNil(InlineMathRendering.metrics(for: "\\begin{notanenvironment}x\\end{notanenvironment}", fontSize: 17))
    }

    // MARK: Patch 1, math keeps its natural width

    func testReportedColoredRankFormulaBecomesDisplayMathAndDrawsInItsColor() throws {
        let formula = #"\color{#7852ee} A^{T}A:\mathbb{R}^{n}\to\mathbb{R}^{n},\qquad (A^{T}A)^{T}=A^{T}A, \qquad \operatorname{rank}(A^{T}A)=r."#
        for markdown in ["$$ " + formula + " $$", "$$\n" + formula + "\n$$"] {
            let prepared = ObsidianInlineMarkup.preparedForReading(markdown, colorsEnabled: false, paletteHexByName: [:])
            let parsed = try AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: [.math]).attributedString(for: prepared)
            let attachment = try XCTUnwrap(parsed.attachments().first?.base as? MathAttachment)
            XCTAssertEqual(attachment.displayStyle, .block)
            XCTAssertFalse(String(parsed.characters).contains("$$"), "The formula must not fall back to source text.")

            let renderer = ImageRenderer(content: attachment.body.font(.system(size: 22)).padding(12).background(.black).environment(\.colorScheme, .dark))
            let renderedImage = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: renderedImage)
            var purplePixelsByHalf = [0, 0]
            for verticalPosition in 0..<bitmap.pixelsHigh {
                for horizontalPosition in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: horizontalPosition, y: verticalPosition)?.usingColorSpace(.deviceRGB) else { continue }
                    if abs(color.redComponent - 120.0 / 255) < 0.08,
                       abs(color.greenComponent - 82.0 / 255) < 0.08,
                       abs(color.blueComponent - 238.0 / 255) < 0.08 {
                        purplePixelsByHalf[horizontalPosition < bitmap.pixelsWide / 2 ? 0 : 1] += 1
                    }
                }
            }
            XCTAssertGreaterThan(purplePixelsByHalf[0], 30)
            XCTAssertGreaterThan(purplePixelsByHalf[1], 30, "The declaration colors the entire formula, including rank.")
            if let outputPath = ProcessInfo.processInfo.environment["GRAPHITE_MATH_PREVIEW_PATH"] {
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: outputPath))
            }
        }
    }

    func testColorDeclarationsRespectBraceScopeAndEscapedBraces() {
        XCTAssertEqual(LaTeXCompatibility.normalized(#"a+{\color{#7852ee}b+c}+d"#), #"a+{\textcolor{#7852ee}{b+c}}+d"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\color{#7852ee}a+{\color{#ff0000}b}+c"#), #"\textcolor{#7852ee}{a+{\textcolor{#ff0000}{b}}+c}"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\color{#7852ee}\{a\}+b"#), #"\textcolor{#7852ee}{\{a\}+b}"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\textcolor{#7852ee}{a}+b"#), #"\textcolor{#7852ee}{a}+b"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\operatorname{rank}(A)"#), #"\mathrm{rank}(A)"#)
        XCTAssertEqual(LaTeXCompatibility.normalized(#"\operatorname*{argmax}_x f(x)"#), #"\operatorname*{argmax}_x f(x)"#)
    }

    func testInlineMathKeepsItsNaturalWidthInANarrowProposal() {
        let attachment = MathAttachment(latex: "k_n", style: .inline)
        let environment = TextEnvironmentValues()
        let naturalSize = attachment.sizeThatFits(.unspecified, in: environment)
        XCTAssertGreaterThan(naturalSize.width, 0)
        let narrowSize = attachment.sizeThatFits(ProposedViewSize(width: naturalSize.width / 2, height: nil), in: environment)
        XCTAssertEqual(narrowSize, naturalSize)
    }

    // MARK: SwiftUIMath patch 1, a formula is not broken by its rounded frame

    /// `Math` typesets its formula again at the width of its canvas. A canvas a fraction of
    /// a point narrower than the formula, as frames rounded to whole pixels are, broke `g_m`
    /// into `g` over `m`, and the reading view showed only the subscript (Vendor/swiftui-math/
    /// GRAPHITE-PATCHES.md). Each formula is drawn in a frame of its own height, 0.4 points
    /// narrower than it: everything must be drawn on one line, around the frame.
    func testFormulaInAFrameNarrowerByAFractionOfAPointStaysOnOneLine() throws {
        let fontSize: CGFloat = 22
        for latex in ["g_m", "r_o", "V_A", "V_{ov}", "k_n"] {
            let metrics = try XCTUnwrap(InlineMathRendering.metrics(for: latex, fontSize: fontSize))
            let height = metrics.ascent + metrics.descent
            let narrowMetrics = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: fontSize, fittingWidth: metrics.width - 0.4))
            XCTAssertEqual(narrowMetrics.width, metrics.width, accuracy: 0.001, latex)

            let margin: CGFloat = 30
            let renderer = ImageRenderer(content: Math(latex)
                .mathFont(Math.Font(name: .latinModern, size: fontSize))
                .mathTypesettingStyle(.text)
                .frame(width: metrics.width - 0.4, height: height, alignment: .topLeading)
                .padding(margin)
                .background(Color.white)
                .environment(\.colorScheme, .light))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            var inkInsideFrame = 0
            var inkOutsideFrame = 0
            for row in 0..<bitmap.pixelsHigh {
                for column in 0..<bitmap.pixelsWide {
                    // The image is a whole number of pixels; its partly covered last row and
                    // column are transparent, not ink.
                    guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB),
                          color.alphaComponent > 0.9, color.brightnessComponent < 0.5 else { continue }
                    let point = CGPoint(x: CGFloat(column) / 2, y: CGFloat(row) / 2)
                    // Descenders and subscripts reach below the typographic height; a
                    // second line would start a whole line lower.
                    if CGRect(x: margin, y: margin, width: metrics.width, height: height).insetBy(dx: -1, dy: -height / 2).contains(point) {
                        inkInsideFrame += 1
                    } else {
                        inkOutsideFrame += 1
                    }
                }
            }
            XCTAssertGreaterThan(inkInsideFrame, 20, latex)
            XCTAssertEqual(inkOutsideFrame, 0, "\(latex) broke onto a second line")
        }
        // A formula genuinely wider than its width still breaks into lines.
        let long = "a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p"
        let naturalLong = try XCTUnwrap(DisplayMathRendering.metrics(for: long, fontSize: fontSize))
        let brokenLong = try XCTUnwrap(DisplayMathRendering.metrics(for: long, fontSize: fontSize, fittingWidth: naturalLong.width / 2))
        XCTAssertGreaterThan(brokenLong.ascent + brokenLong.descent, 1.5 * (naturalLong.ascent + naturalLong.descent))
    }

    /// A fraction late in a long formula goes onto a new line when it would run past the
    /// width. The typesetter measured only the text since the last fraction, so the third
    /// fraction here was placed past the edge of a callout and cut off.
    func testFractionAfterEarlierFractionsBreaksOntoANewLine() throws {
        let fontSize: CGFloat = 22
        let latex = #"\text{new time} = \frac{1-f}{s} + f, \qquad \text{memory share} = \frac{f}{\frac{1-f}{s} + f}, \qquad \text{overall speedup} = \frac{1}{\frac{1-f}{s} + f}"#
        let natural = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: fontSize))
        for fraction in [0.95, 0.8, 0.6] {
            let width = natural.width * fraction
            let fitted = try XCTUnwrap(DisplayMathRendering.metrics(for: latex, fontSize: fontSize, fittingWidth: width))
            XCTAssertLessThanOrEqual(fitted.width, width + MathAttachment.naturalWidthTolerance, "at \(fraction) of its width")
            XCTAssertGreaterThan(fitted.ascent + fitted.descent, 1.5 * (natural.ascent + natural.descent), "at \(fraction) of its width")
        }
    }

    /// `\underbrace` and `\overbrace` are typeset, with their labels below or above the
    /// brace. The typesetter did not know them, so a formula using one showed as its source.
    func testUnderbraceAndOverbraceAreTypesetWithTheirLabels() throws {
        let fontSize: CGFloat = 22
        let note = #"t_{\text{wear-out}} = \underbrace{\frac{C}{G}}_{\text{write requests to write every cell once}} \times \underbrace{E}_{\text{writes each cell survives}} \times \underbrace{t_{req}}_{\text{time per write request}}"#
        XCTAssertTrue(MathAttachment.canTypeset(note))
        XCTAssertEqual(try mathAttachmentCount(inMarkdown: #"Under $\underbrace{a+b}_{n}$ and over $\overbrace{a+b}^{n}$."#), 2)

        let plain = try XCTUnwrap(DisplayMathRendering.metrics(for: "a+b", fontSize: fontSize))
        let under = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\underbrace{a+b}"#, fontSize: fontSize))
        let underLabelled = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\underbrace{a+b}_{\text{a long label}}"#, fontSize: fontSize))
        let over = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\overbrace{a+b}"#, fontSize: fontSize))
        let overLabelled = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\overbrace{a+b}^{\text{a long label}}"#, fontSize: fontSize))
        let label = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\scriptstyle\text{a long label}"#, fontSize: fontSize))
        // The brace adds height on its side only, and is as wide as what it spans.
        XCTAssertEqual(under.width, plain.width, accuracy: 0.01)
        XCTAssertEqual(under.ascent, plain.ascent, accuracy: 0.01)
        XCTAssertGreaterThan(under.descent, plain.descent + 0.3 * fontSize)
        XCTAssertEqual(over.descent, plain.descent, accuracy: 0.01)
        XCTAssertGreaterThan(over.ascent, plain.ascent + 0.3 * fontSize)
        // The label goes beyond the brace, as wide as it is, and not beside it.
        XCTAssertGreaterThan(underLabelled.descent, under.descent + label.ascent)
        XCTAssertEqual(underLabelled.width, label.width, accuracy: 0.5)
        XCTAssertGreaterThan(overLabelled.ascent, over.ascent + label.descent)
        XCTAssertEqual(overLabelled.width, label.width, accuracy: 0.5)
    }

    /// A hyphen inside `\text` stays a hyphen: `\text{wear-out}` read as "wear − out",
    /// with a minus sign and the spaces of a binary operator.
    func testHyphenInsideTextIsAHyphen() throws {
        let fontSize: CGFloat = 22
        let hyphenated = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\text{wear-out}"#, fontSize: fontSize))
        let minus = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\text{wear}-\text{out}"#, fontSize: fontSize))
        let joined = try XCTUnwrap(DisplayMathRendering.metrics(for: #"\text{wearout}"#, fontSize: fontSize))
        XCTAssertLessThan(hyphenated.width, minus.width - 0.3 * fontSize)
        XCTAssertLessThan(hyphenated.width - joined.width, 0.4 * fontSize, "one hyphen wide")
    }

    /// The view draws display math at its natural width when it overhangs the column by
    /// up to a point; the measurement used to refit it (and reserve the wrapped height)
    /// as soon as it overhung at all.
    func testDisplayMathOverhangingByLessThanTheToleranceIsMeasuredAtItsNaturalSize() {
        let attachment = MathAttachment(latex: "a + b + c + d + e + f + g + h + i + j + k + l + m + n", style: .block)
        let environment = TextEnvironmentValues()
        let naturalSize = attachment.sizeThatFits(.unspecified, in: environment)
        XCTAssertGreaterThan(naturalSize.width, 0)
        let slightOverhang = MathAttachment.naturalWidthTolerance / 2
        let almostWideEnough = ProposedViewSize(width: naturalSize.width - slightOverhang, height: nil)
        XCTAssertEqual(attachment.sizeThatFits(almostWideEnough, in: environment), naturalSize)
        let halfWidth = ProposedViewSize(width: naturalSize.width / 2, height: nil)
        let wrappedSize = attachment.sizeThatFits(halfWidth, in: environment)
        XCTAssertNotEqual(wrappedSize, naturalSize, "Display math genuinely wider than the column still wraps.")
    }

    // MARK: Patch 7, tables fit the width they are offered

    func testColumnsGiveUpTheSameShareOfTheWidthTheyCanGiveUp() {
        func columnWidths(availableWidth: CGFloat?) -> [CGFloat] {
            StructuredText.TableColumnsLayout.columnWidths(narrowestWidths: [40, 60], widestWidths: [100, 300], availableWidth: availableWidth)
        }
        XCTAssertEqual(columnWidths(availableWidth: nil), [100, 300], "any width: nothing wraps")
        XCTAssertEqual(columnWidths(availableWidth: 500), [100, 300], "more than the table needs: it does not stretch")
        XCTAssertEqual(columnWidths(availableWidth: 250), [70, 180], "half of what each column can give up")
        XCTAssertEqual(columnWidths(availableWidth: 251.5), [70, 181], "whole points, never more than is available")
        XCTAssertEqual(columnWidths(availableWidth: 80), [40, 60], "less than the widest words: the table overflows")
    }

    func testEveryWordGetsALineOfItsOwnExceptAcrossNonBreakingSpacesAndAttachments() throws {
        XCTAssertEqual(String(AttributedString("one two\tthree\u{00A0}four").breakingAfterEveryWord().characters), "one\ntwo\nthree\u{00A0}four")

        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        let formulaBetweenWords = try parser.attributedString(for: "**bold** then $a + b$ end")
        let broken = formulaBetweenWords.breakingAfterEveryWord()
        XCTAssertEqual(String(broken.characters), "bold\nthen\n\u{FFFC}\nend")
        XCTAssertEqual(broken.attachments(), formulaBetweenWords.attachments(), "the formula stays whole")
        XCTAssertEqual(broken.runs.first?.inlinePresentationIntent, .stronglyEmphasized, "words keep their style")
    }

    func testOnlyAttachmentsThatShrinkMakeACellFollowItsColumn() throws {
        let environment = TextEnvironmentValues()
        let parser = AttributedStringMarkdownParser.inlineMarkdown(syntaxExtensions: [.math])
        XCTAssertFalse(try parser.attributedString(for: "Energy $E = mc^2$").hasAttachmentsThatFitTheirWidth(in: environment))

        var figure = AttributedString("\u{FFFC}")
        figure.textual.attachment = AnyAttachment(ShrinkingFigureAttachment(naturalWidth: 400))
        XCTAssertTrue(figure.hasAttachmentsThatFitTheirWidth(in: environment))
    }

    /// Three figures, each wider than the table is offered in all: each shrinks to its
    /// column, as an image does in a browser's table, where it used to keep the width of
    /// the whole text and push the table far past its container.
    func testFiguresInATableShrinkToTheirColumns() async throws {
        let markdown = "| One | Two | Six |\n| --- | --- | --- |\n| ![](a.png) | ![](b.png) | ![](c.png) |\n"
        let layout = try await tableLayout(ofMarkdown: markdown, offeredWidth: 302) { layout in
            layout.numberOfRows == 2 && layout.bounds.width <= 302 && layout.rowBounds(1).height > 40
        }
        XCTAssertEqual(layout.numberOfColumns, 3)
        XCTAssertLessThanOrEqual(layout.bounds.width, 302)
        for column in 0..<3 {
            // 302 less the two gaps of one point, shared by three equal columns.
            XCTAssertEqual(layout.cellBounds(row: 1, column: column).width, 100, accuracy: 1)
        }
        // A figure is half as tall as it is wide, so the row is as tall as a figure one column
        // wide, and the line it is on adds a few points below it.
        XCTAssertGreaterThanOrEqual(layout.rowBounds(1).height, 49)
        XCTAssertLessThanOrEqual(layout.rowBounds(1).height, 56)
    }

    func testFiguresThatFitKeepTheirSizeAndTheTableDoesNotStretch() async throws {
        let markdown = "| One | Two |\n| --- | --- |\n| ![](a.png) | ![](b.png) |\n"
        let layout = try await tableLayout(ofMarkdown: markdown, offeredWidth: 2000) { layout in
            layout.numberOfRows == 2 && layout.rowBounds(1).height > 190
        }
        XCTAssertEqual(layout.bounds.width, 2 * ShrinkingFigureLoader.naturalWidth + 1, accuracy: 1)
        XCTAssertGreaterThanOrEqual(layout.rowBounds(1).height, ShrinkingFigureLoader.naturalWidth / 2)
        XCTAssertLessThanOrEqual(layout.rowBounds(1).height, ShrinkingFigureLoader.naturalWidth / 2 + 6)
    }

    func testTextWrapsToTheOfferedWidthButNoWordIsBroken() async throws {
        let sentence = "alpha beta gamma delta epsilon zeta eta theta iota kappa"
        let markdown = "| Name | Notes |\n| --- | --- |\n| x | \(sentence) |\n"
        let unwrapped = try await tableLayout(ofMarkdown: markdown, offeredWidth: 2000) { layout in layout.numberOfRows == 2 }
        let wrapped = try await tableLayout(ofMarkdown: markdown, offeredWidth: 160) { layout in layout.numberOfRows == 2 }
        XCTAssertGreaterThan(unwrapped.bounds.width, 160, "the sentence on one line is wider than the narrow table")
        XCTAssertLessThanOrEqual(wrapped.bounds.width, 160)
        XCTAssertGreaterThan(wrapped.rowBounds(1).height, unwrapped.rowBounds(1).height * 2, "the sentence takes several lines")

        // Offered almost nothing, the table keeps the width of its widest words and
        // overflows; a word broken letter by letter would make the row far taller.
        let narrowest = try await tableLayout(ofMarkdown: markdown, offeredWidth: 10) { layout in layout.numberOfRows == 2 }
        XCTAssertGreaterThan(narrowest.bounds.width, 40)
        let wordsInTheSentence = CGFloat(sentence.split(separator: " ").count)
        XCTAssertLessThanOrEqual(narrowest.rowBounds(1).height, unwrapped.rowBounds(1).height * wordsInTheSentence + 1, "one word on each line at most")
    }

    // MARK: Patch 8, empty table cells keep their place

    func testEmptyCellsAndRowsKeepTheirPlaceInATable() throws {
        let markdown = "|  | A | B |\n| --- | --- | --- |\n| x |  | z |\n|  |  |  |\n| p | q | r |\n"
        let attributed = try AttributedStringMarkdownParser(baseURL: nil, syntaxExtensions: []).attributedString(for: markdown)
        let table = try XCTUnwrap(attributed.blockRuns().first)
        let cellContents = StructuredText.Table.cellContents(in: attributed[table.range], tableIntent: table.intent, columnCount: 3)
        let cellTexts = cellContents.map { row in row.map { cell in String(cell.characters[...]) } }
        XCTAssertEqual(cellTexts, [["", "A", "B"], ["x", "", "z"], ["", "", ""], ["p", "q", "r"]])
    }

    /// The header `| | A long heading | B |` used to put the long heading over the first
    /// column, because the empty cell before it was not laid out.
    func testHeadingAfterAnEmptyCellStaysOverItsColumn() async throws {
        let markdown = "|  | A long heading over the second column | B |\n| --- | --- | --- |\n| x | y | z |\n"
        let layout = try await tableLayout(ofMarkdown: markdown, offeredWidth: 2000) { layout in layout.numberOfRows == 2 }
        XCTAssertEqual(layout.numberOfColumns, 3)
        XCTAssertGreaterThan(layout.cellBounds(row: 0, column: 1).width, layout.cellBounds(row: 0, column: 0).width * 4)
    }

    /// The layout of the table in `markdown` inside a frame `offeredWidth` wide, once it
    /// satisfies `isSettled`: images load after the first layout.
    private func tableLayout(ofMarkdown markdown: String, offeredWidth: CGFloat,
                             isSettled: (StructuredText.TableLayout) -> Bool) async throws -> StructuredText.TableLayout {
        let recorder = TableLayoutRecorder()
        let table = StructuredText(markdown: markdown)
            .textual.imageAttachmentLoader(ShrinkingFigureLoader())
            .textual.tableStyle(RecordingTableStyle(offeredWidth: offeredWidth, recorder: recorder))
            .textual.tableCellStyle(BareTableCellStyle())
        let hostingView = NSHostingView(rootView: table.frame(width: 3000, alignment: .leading))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 3000, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        defer { window.contentView = nil }
        for _ in 0..<60 {
            hostingView.layoutSubtreeIfNeeded()
            if let layout = recorder.layout, isSettled(layout) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try XCTUnwrap(recorder.layout, "the table was never laid out")
    }
}

@MainActor
private final class TableLayoutRecorder {
    var layout: StructuredText.TableLayout?
}

/// Offers the table a fixed width and records where its cells end up.
private struct RecordingTableStyle: StructuredText.TableStyle {
    let offeredWidth: CGFloat
    let recorder: TableLayoutRecorder

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.tableCellSpacing(horizontal: 1, vertical: 1)
            .textual.tableOverlay { layout in
                // Recorded as the overlay is built: in a window that is never shown, `onChange`
                // drops all but the first change of a frame that never ends.
                let _ = MainActor.assumeIsolated { recorder.layout = layout }
                Color.clear
            }
            .frame(width: offeredWidth, alignment: .leading)
    }
}

/// Cells without padding, so a column is as wide as its content.
private struct BareTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// A figure that fits the width it is offered, as an image does; half as tall as it is wide.
private struct ShrinkingFigureAttachment: Attachment {
    let naturalWidth: CGFloat
    var description: String { "figure" }
    var body: some View { Color.blue }

    func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
        let width = min(proposal.width ?? naturalWidth, naturalWidth)
        return CGSize(width: width, height: width / 2)
    }
}

private struct ShrinkingFigureLoader: AttachmentLoader {
    static let naturalWidth: CGFloat = 400

    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> ShrinkingFigureAttachment {
        ShrinkingFigureAttachment(naturalWidth: Self.naturalWidth)
    }
}
