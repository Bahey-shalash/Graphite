import XCTest
import CoreGraphics
import CoreText
import GraphiteCore
@testable import GraphiteApple

/// A text box's text laid out with Core Text: its height follows the text, its lines and
/// links are where the box is, and it draws inside the box as turned.
final class PDFTextBoxLayoutTests: XCTestCase {
    private func box(_ text: String, width: Double = 200, rotation: Double = 0, attributes: PDFTextAttributes = .plain) -> PDFTextBox {
        PDFTextBox(name: "layout", runs: [PDFTextRun(text: text, attributes: attributes)], origin: CGPoint(x: 100, y: 500), width: width,
                   height: 1, rotationRadians: rotation)
    }

    func testTheHeightGrowsWithTheTextAndAnEmptyBoxHoldsOneLine() {
        let empty = PDFTextBoxLayout(box: box("")).fittedHeight
        let oneLine = PDFTextBoxLayout(box: box("One line")).fittedHeight
        let wrapped = PDFTextBoxLayout(box: box(String(repeating: "Several words wrap here. ", count: 12))).fittedHeight
        let afterReturn = PDFTextBoxLayout(box: box("One line\n")).fittedHeight
        XCTAssertEqual(empty, oneLine, accuracy: 1)
        XCTAssertGreaterThan(wrapped, oneLine * 4)
        XCTAssertGreaterThan(afterReturn, oneLine + 10, "The empty line after Return is inside the box.")
        XCTAssertGreaterThan(oneLine, PDFTextAttributes.defaultFontSize + 2 * PDFTextBoxStyle.defaultPadding)
        XCTAssertLessThan(oneLine, 2 * PDFTextAttributes.defaultFontSize + 2 * PDFTextBoxStyle.defaultPadding)
    }

    func testANarrowerBoxIsTaller() {
        let text = String(repeating: "word ", count: 40)
        XCTAssertGreaterThan(PDFTextBoxLayout(box: box(text, width: 100)).fittedHeight, PDFTextBoxLayout(box: box(text, width: 300)).fittedHeight)
    }

    func testTheFirstBaselineIsTheFontsAscentBelowThePadding() throws {
        let layout = PDFTextBoxLayout(box: PDFTextBoxLayout.fitted(box("Baseline", attributes: PDFTextAttributes(fontFamily: "Helvetica Neue", fontSize: 24, color: .black))))
        let firstOrigin = try XCTUnwrap(layout.lineOrigins.first)
        let font = PDFTextBoxFonts.font(for: PDFTextAttributes(fontFamily: "Helvetica Neue", fontSize: 24, color: .black))
        // Goodnotes' boxes put the first baseline 0.952 of the font size below the inset: Helvetica Neue's ascent.
        XCTAssertEqual(layout.box.height - Double(firstOrigin.y), PDFTextBoxStyle.defaultPadding + Double(CTFontGetAscent(font)), accuracy: 0.5)
        XCTAssertEqual(Double(CTFontGetAscent(font)) / 24, 0.952, accuracy: 0.01)
    }

    func testUnderlinesAndLinksAreUnderTheirRunsInsideTheBox() throws {
        var linked = PDFTextAttributes.plain
        linked.isUnderlined = true
        linked.link = URL(string: "https://example.com")
        let made = PDFTextBoxLayout.fitted(PDFTextBox(name: "links", runs: [PDFTextRun(text: "Go to ", attributes: .plain), PDFTextRun(text: "the site", attributes: linked)],
                                                      origin: CGPoint(x: 0, y: 100), width: 200, height: 1))
        let layout = PDFTextBoxLayout(box: made)
        let underline = try XCTUnwrap(layout.underlines().first)
        let link = try XCTUnwrap(layout.linkAreas().first)
        XCTAssertEqual(link.url, linked.link)
        XCTAssertGreaterThan(link.rectangle.minX, 20, "The link starts after the plain words.")
        XCTAssertEqual(underline.rectangle.minX, link.rectangle.minX, accuracy: 0.01)
        XCTAssertTrue(layout.boxRectangle.contains(link.rectangle))
        XCTAssertLessThan(underline.rectangle.maxY, link.rectangle.midY)
    }

    func testTheOutlinesOfTheTextAreInsideTheBoxAndOnePathForEachColor() throws {
        let red = PDFTextAttributes(fontFamily: "Georgia", fontSize: 20, color: PDFTextColor(red: 1, green: 0, blue: 0))
        let made = PDFTextBoxLayout.fitted(PDFTextBox(name: "outlines", runs: [PDFTextRun(text: "Black ", attributes: .plain), PDFTextRun(text: "Red", attributes: red),
                                                                              PDFTextRun(text: " black", attributes: .plain)],
                                                      origin: .zero, width: 300, height: 1))
        let outlines = PDFTextBoxLayout(box: made).textOutlines()
        XCTAssertEqual(outlines.map(\.color), [.black, red.color])
        for outline in outlines { XCTAssertTrue(CGRect(x: 0, y: 0, width: made.width, height: made.height).contains(outline.path.boundingBoxOfPath)) }
    }

    func testATurnedBoxDrawsInsideItsAnnotationRectangle() throws {
        let made = PDFTextBoxLayout.fitted(box("Turned text that draws inside", rotation: 0.6))
        let layout = PDFTextBoxLayout(box: made)
        let pageRectangle = layout.boxRectangle.applying(layout.boxToPage)
        XCTAssertEqual(pageRectangle.minX, made.annotationBounds.minX, accuracy: 0.01)
        XCTAssertEqual(pageRectangle.maxY, made.annotationBounds.maxY, accuracy: 0.01)
        XCTAssertEqual(CGPoint.zero.applying(layout.boxToPage).x, made.corners[3].x, accuracy: 0.01)
        XCTAssertEqual(CGPoint(x: 0, y: made.height).applying(layout.boxToPage).y, made.origin.y, accuracy: 0.01)
    }

    func testAFamilyThisDeviceLacksIsDrawnInHelveticaAndKeepsItsName() {
        let missing = PDFTextAttributes(fontFamily: "A Font Nobody Has", fontSize: 12, color: .black)
        XCTAssertEqual(CTFontCopyFamilyName(PDFTextBoxFonts.font(for: missing)) as String, "Helvetica")
        XCTAssertFalse(PDFTextBoxFonts.isAvailable(family: missing.fontFamily))
        for family in PDFTextBoxFonts.offeredFamilies { XCTAssertTrue(PDFTextBoxFonts.isAvailable(family: family), family) }
        var bold = PDFTextAttributes(fontFamily: "Georgia", fontSize: 12, color: .black)
        bold.isBold = true
        XCTAssertTrue(CTFontGetSymbolicTraits(PDFTextBoxFonts.font(for: bold)).contains(.traitBold))
    }

    func testTheStandardAbbreviationsOfDefaultAppearancesAreTheirFonts() {
        let attributes = PDFTextBoxFonts.attributes(fromPostScriptName: "TiBI", size: 10, color: .black)
        XCTAssertEqual(attributes.fontFamily, "Times New Roman")
        XCTAssertTrue(attributes.isBold && attributes.isItalic)
        let named = PDFTextBoxFonts.attributes(fromPostScriptName: "Georgia-Italic", size: 10, color: .black)
        XCTAssertEqual(named.fontFamily, "Georgia")
        XCTAssertTrue(named.isItalic)
    }

    func testTheTextThatFitsAHeightEndsAtAWholeLine() throws {
        let lines = (1...20).map { lineNumber in "Line \(lineNumber)" }.joined(separator: "\n")
        let layout = PDFTextBoxLayout(box: PDFTextBoxLayout.fitted(box(lines)))
        XCTAssertEqual(layout.textLengthFitting(height: layout.fittedHeight + 1), lines.utf16.count)
        let firstFive = (1...5).map { lineNumber in "Line \(lineNumber)" }.joined(separator: "\n")
        let fiveLinesHeight = PDFTextBoxLayout(box: PDFTextBoxLayout.fitted(box(firstFive))).fittedHeight
        // The fifth line's range takes its line break.
        XCTAssertEqual(layout.textLengthFitting(height: fiveLinesHeight + 0.25), firstFive.utf16.count + 1)
        XCTAssertEqual(layout.textLengthFitting(height: 1), 0)
    }
}
