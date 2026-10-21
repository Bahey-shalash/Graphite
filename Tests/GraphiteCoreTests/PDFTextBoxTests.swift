import XCTest
import CoreGraphics
@testable import GraphiteCore

/// The text box value: its runs kept in one form, and where it is on its page as turned.
final class PDFTextBoxTests: XCTestCase {
    private func box(rotation: Double = 0, width: Double = 100, height: Double = 40) -> PDFTextBox {
        PDFTextBox(name: "box-1", runs: [PDFTextRun(text: "Hello", attributes: .plain)], origin: CGPoint(x: 50, y: 500),
                   width: width, height: height, rotationRadians: rotation)
    }

    func testRunsAreKeptWithoutEmptyRunsAndWithNeighboursOfOneLookJoined() {
        let bold = PDFTextAttributes(fontFamily: "Georgia", fontSize: 12, color: .black, isBold: true)
        let made = PDFTextBox(name: "box", runs: [PDFTextRun(text: "a", attributes: .plain), PDFTextRun(text: "", attributes: bold),
                                                  PDFTextRun(text: "b\r\nc", attributes: .plain), PDFTextRun(text: "d", attributes: bold)],
                              origin: .zero, width: 50, height: 20)
        XCTAssertEqual(made.runs, [PDFTextRun(text: "ab\nc", attributes: .plain), PDFTextRun(text: "d", attributes: bold)])
        XCTAssertEqual(made.plainText, "ab\ncd")
    }

    func testRunsSetLaterAreKeptInTheSameForm() {
        var changed = box()
        changed.runs = [PDFTextRun(text: "x", attributes: .plain), PDFTextRun(text: "y", attributes: .plain)]
        XCTAssertEqual(changed.runs, [PDFTextRun(text: "xy", attributes: .plain)])
    }

    func testAnUprightBoxHangsDownFromItsTopLeftCorner() {
        let upright = box()
        XCTAssertEqual(upright.annotationBounds, CGRect(x: 50, y: 460, width: 100, height: 40))
        XCTAssertEqual(upright.corners[0], CGPoint(x: 50, y: 500))
        XCTAssertTrue(upright.contains(CGPoint(x: 60, y: 490)))
        XCTAssertFalse(upright.contains(CGPoint(x: 60, y: 501)))
    }

    func testABoxTurnedAQuarterClockwiseRunsDownThePageFromItsCorner() throws {
        let turned = box(rotation: .pi / 2)
        // The text runs down the page (y decreasing) and its lines follow each other leftward.
        let topRight = turned.corners[1]
        XCTAssertEqual(topRight.x, 50, accuracy: 1e-9)
        XCTAssertEqual(topRight.y, 400, accuracy: 1e-9)
        let bounds = turned.annotationBounds
        XCTAssertEqual(bounds.minX, 10, accuracy: 1e-9)
        XCTAssertEqual(bounds.maxX, 50, accuracy: 1e-9)
        XCTAssertEqual(bounds.minY, 400, accuracy: 1e-9)
        XCTAssertEqual(bounds.maxY, 500, accuracy: 1e-9)
        XCTAssertTrue(turned.contains(CGPoint(x: 30, y: 450)))
    }

    func testTurningAboutTheMiddleKeepsTheMiddleWhereItWas() {
        let upright = box()
        let turned = upright.rotated(to: 0.7)
        XCTAssertEqual(turned.middle.x, upright.middle.x, accuracy: 1e-9)
        XCTAssertEqual(turned.middle.y, upright.middle.y, accuracy: 1e-9)
        XCTAssertEqual(turned.rotationRadians, 0.7, accuracy: 1e-12)
    }

    func testAPointOfTheBoxIsFoundBackInItsOwnTerms() {
        let turned = box(rotation: -0.4)
        let point = turned.pagePoint(along: 30, down: 12)
        let position = turned.boxPoint(fromPage: point)
        XCTAssertEqual(position.alongText, 30, accuracy: 1e-9)
        XCTAssertEqual(position.down, 12, accuracy: 1e-9)
    }

    func testTextIsUprightOnAPageShownTurned() {
        XCTAssertEqual(PDFTextBox.uprightRotation(forPageQuarterTurns: 0), 0)
        XCTAssertEqual(PDFTextBox.uprightRotation(forPageQuarterTurns: 1), -.pi / 2, accuracy: 1e-12)
        XCTAssertEqual(abs(PDFTextBox.uprightRotation(forPageQuarterTurns: 2)), .pi, accuracy: 1e-12)
        XCTAssertEqual(PDFTextBox.uprightRotation(forPageQuarterTurns: 3), .pi / 2, accuracy: 1e-12)
    }

    func testValuesOutsideTheLimitsAreBroughtInside() {
        let attributes = PDFTextAttributes(fontFamily: "  ", fontSize: .infinity, color: PDFTextColor(red: 2, green: -1, blue: .nan))
        XCTAssertEqual(attributes.fontFamily, PDFTextAttributes.defaultFontFamily)
        XCTAssertEqual(attributes.fontSize, PDFTextAttributes.defaultFontSize)
        XCTAssertEqual(attributes.color, PDFTextColor(red: 1, green: 0, blue: 0))
        let style = PDFTextBoxStyle(alignment: .left, lineSpacing: 99, borderWidth: -3, padding: .nan)
        XCTAssertEqual(style.lineSpacing, PDFTextBoxStyle.lineSpacingRange.upperBound)
        XCTAssertEqual(style.borderWidth, 0)
        XCTAssertEqual(style.padding, PDFTextBoxStyle.defaultPadding)
        XCTAssertEqual(PDFTextBox(name: "n", runs: [], origin: .zero, width: 1, height: -5).width, PDFTextBox.minimumWidth)
    }

    func testScalingABoxScalesItsTextAndPadding() {
        let scaled = box().scaled(by: 2)
        XCTAssertEqual(scaled.width, 200)
        XCTAssertEqual(scaled.runs.first?.attributes.fontSize, PDFTextAttributes.defaultFontSize * 2)
        XCTAssertEqual(scaled.style.padding, PDFTextBoxStyle.defaultPadding * 2)
        XCTAssertEqual(scaled.origin, box().origin)
    }

    func testColorsAreReadAndWrittenAsHexadecimal() {
        XCTAssertEqual(PDFTextColor(hex: "#FF8000"), PDFTextColor(red: 1, green: 128.0 / 255, blue: 0))
        XCTAssertEqual(PDFTextColor(hex: "#f00"), PDFTextColor(red: 1, green: 0, blue: 0))
        XCTAssertNil(PDFTextColor(hex: "red"))
        XCTAssertNil(PDFTextColor(hex: "#12345"))
        XCTAssertEqual(PDFTextColor(red: 1, green: 0.5, blue: 0).hex, "#ff8000")
    }

    func testTheAlignmentIsTheStandardQuadding() {
        XCTAssertEqual(PDFTextAlignment.allCases.map(\.quadding), [0, 1, 2, 0])
        XCTAssertEqual(PDFTextAlignment(quadding: 2), .right)
        XCTAssertEqual(PDFTextAlignment(quadding: 7), .left)
    }

    func testRunsAreCutInTwoAtAPlaceInTheirText() {
        var bold = PDFTextAttributes.plain
        bold.isBold = true
        let runs = [PDFTextRun(text: "First ", attributes: .plain), PDFTextRun(text: "bold words", attributes: bold), PDFTextRun(text: " end", attributes: .plain)]
        let (before, after) = PDFTextRun.split(runs, atUTF16Offset: 10)
        XCTAssertEqual(before, [PDFTextRun(text: "First ", attributes: .plain), PDFTextRun(text: "bold", attributes: bold)])
        XCTAssertEqual(after, [PDFTextRun(text: " words", attributes: bold), PDFTextRun(text: " end", attributes: .plain)])
        XCTAssertEqual(PDFTextRun.split(runs, atUTF16Offset: 0).before, [])
        XCTAssertEqual(PDFTextRun.split(runs, atUTF16Offset: 100).after, [])
    }
}
