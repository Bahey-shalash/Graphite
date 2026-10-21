import XCTest
import CoreGraphics
import PDFKit
import GraphiteCore
import NotebookImport
import GraphiteTestSupport
@testable import GraphiteApple

/// Imported typed text written as Graphite text boxes and read back with PDFKit: where each box is, its text and looks,
/// its links, its place over the ink, Notability's text flowing onto later pages, and the report of what it could not keep.
final class NotebookImportTextWriterTests: XCTestCase {
    private struct NoFiles: ImportSourceFiles {
        struct Missing: Error {}
        func contents(of file: ImportedSourceFile) throws -> Data { throw Missing() }
    }

    private static let pageSize = CGSize(width: 455.04, height: 588.45)
    private static let black = NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let red = NotebookImportColor(red: 0.95, green: 0.25, blue: 0.25, alpha: 1)
    private static let white = NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let accuracy = 0.01

    private func run(_ text: String, font: ImportedTextFont = .family("Helvetica Neue"), size: Double = 13.09, color: NotebookImportColor = black,
                     isUnderlined: Bool = false, link: URL? = nil) -> ImportedTextRun {
        ImportedTextRun(text: text, font: font, sizeInPoints: size, color: color, isUnderlined: isUnderlined, link: link)
    }

    private func written(_ plans: [ImportedPagePlan]) throws -> (document: PDFDocument, writing: NotebookImportWriting) {
        let vault = try TemporaryVault.make(prefix: "NotebookImportText", for: self)
        let destination = vault.location(of: "Imported.pdf")
        let writing = try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(
            sourcePageCount: plans.count, outcomeForPage: { pageIndex in .planned(plans[pageIndex]) }, outline: [], sourceFiles: NoFiles(),
            strokeCreationDate: Date(timeIntervalSinceReferenceDate: 0), to: destination)
        return (try XCTUnwrap(PDFDocument(url: destination)), writing)
    }

    private func plan(_ number: Int = 1, textBoxes: [ImportedTextBox] = [], flowingText: ImportedFlowingText? = nil,
                      strokes: [ImportedStroke] = [], report: [ImportReportEntry] = []) -> ImportedPagePlan {
        ImportedPagePlan(sourcePageNumber: number, sizeInPoints: Self.pageSize, background: .plainColor(Self.white), strokes: strokes,
                         textBoxes: textBoxes, flowingText: flowingText, report: report)
    }

    func testATextBoxIsWrittenAtItsCornerWithItsTextLooksAngleAndLink() throws {
        let link = try XCTUnwrap(URL(string: "https://example.com/graphite"))
        let textBox = ImportedTextBox(content: .runs([run("Link here", color: Self.red, link: link)]), origin: CGPoint(x: 47.3, y: 479.7), width: 53.45,
                                      height: nil, rotationRadiansClockwise: 0.3, padding: 5.45, fillColor: nil)
        let (document, writing) = try written([plan(textBoxes: [textBox])])
        let page = try XCTUnwrap(document.page(at: 0))
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: page).first)
        XCTAssertEqual(box.plainText, "Link here")
        XCTAssertEqual(box.origin.x, 47.3, accuracy: Self.accuracy)
        XCTAssertEqual(box.origin.y, Self.pageSize.height - 479.7, accuracy: Self.accuracy, "y counts up from the page's bottom")
        XCTAssertEqual(box.width, 53.45, accuracy: Self.accuracy)
        XCTAssertEqual(box.rotationRadians, 0.3, accuracy: 1e-6)
        XCTAssertEqual(box.style.padding, 5.45, accuracy: Self.accuracy)
        XCTAssertEqual(box.height, PDFTextBoxLayout(box: box).fittedHeight, accuracy: Self.accuracy, "as tall as its text")
        let attributes = box.leadingAttributes
        XCTAssertEqual(attributes.fontFamily, "Helvetica Neue")
        XCTAssertEqual(attributes.fontSize, 13.09, accuracy: Self.accuracy)
        XCTAssertEqual(attributes.color, PDFTextColor(red: 0.95, green: 0.25, blue: 0.25))
        XCTAssertEqual(attributes.link, link)
        let links = page.annotations.filter { annotation in annotation.type == "Link" }
        XCTAssertEqual(links.map(\.url), [link], "the linked run is a /Link annotation every reader opens")
        XCTAssertEqual(writing.pageReports.first?.written?.textBoxCount, 1)
        XCTAssertEqual(writing.pageReports.first?.entries, [])
    }

    func testTextBoxesAreOverTheInk() throws {
        let stroke = ImportedStroke(ink: .monoline, color: Self.black, samples: [
            ImportedStrokeSample(location: CGPoint(x: 10, y: 10), width: 2, force: nil, azimuthRadians: nil, altitudeRadians: nil),
            ImportedStrokeSample(location: CGPoint(x: 100, y: 10), width: 2, force: nil, azimuthRadians: nil, altitudeRadians: nil)
        ], outline: nil)
        let textBox = ImportedTextBox(content: .runs([run("Over")]), origin: CGPoint(x: 20, y: 20), width: 100, height: nil, rotationRadiansClockwise: 0,
                                      padding: 4, fillColor: nil)
        let (document, _) = try written([plan(textBoxes: [textBox], strokes: [stroke])])
        let types = try XCTUnwrap(document.page(at: 0)).annotations.map(\.type)
        XCTAssertEqual(types, ["Ink", "FreeText"])
    }

    func testAStickyNoteKeepsItsSquareAndFill() throws {
        let fill = NotebookImportColor(red: 0.98, green: 0.906, blue: 0.471, alpha: 1)
        let note = ImportedTextBox(content: .runs([run("Sticky one")]), origin: CGPoint(x: 140, y: 278), width: 139.6, height: 139.6,
                                   rotationRadiansClockwise: 0, padding: 4.36, fillColor: fill)
        let (document, _) = try written([plan(textBoxes: [note], report: [.stickyNotesAsTextBoxes(count: 1)])])
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(document.page(at: 0))).first)
        XCTAssertEqual(box.height, 139.6, accuracy: Self.accuracy)
        XCTAssertEqual(box.style.fillColor, PDFTextColor(red: 0.98, green: 0.906, blue: 0.471))
    }

    func testAnOlderTextBoxReadsItsRTFWithSizesInSourceUnits() throws {
        let rtf = #"{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica-Bold;}}{\colortbl;\red255\green0\blue0;}\f0\fs48\cf1 Bold red}"#
        let textBox = ImportedTextBox(content: .rtf(rtf, pointsPerUnit: 6.0 / 11.0), origin: CGPoint(x: 50, y: 60), width: 200, height: nil,
                                      rotationRadiansClockwise: 0, padding: 5.45, fillColor: nil)
        let (document, _) = try written([plan(textBoxes: [textBox])])
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(document.page(at: 0))).first)
        XCTAssertEqual(box.plainText, "Bold red")
        XCTAssertEqual(box.leadingAttributes.fontSize, 24 * 6.0 / 11.0, accuracy: Self.accuracy)
        XCTAssertTrue(box.leadingAttributes.isBold)
        XCTAssertEqual(box.leadingAttributes.color, PDFTextColor(red: 1, green: 0, blue: 0))
    }

    func testAFontThisDeviceLacksAndABoxThatCannotBePlacedAreReported() throws {
        let missingFont = ImportedTextBox(content: .runs([run("Odd font", font: .family("No Such Family Graphite"))]), origin: CGPoint(x: 10, y: 10),
                                          width: 100, height: nil, rotationRadiansClockwise: 0, padding: 4, fillColor: nil)
        let unusable = ImportedTextBox(content: .runs([run("Nowhere")]), origin: CGPoint(x: Double.nan, y: 10), width: 100, height: nil,
                                       rotationRadiansClockwise: 0, padding: 4, fillColor: nil)
        let empty = ImportedTextBox(content: .runs([]), origin: .zero, width: 100, height: nil, rotationRadiansClockwise: 0, padding: 4, fillColor: nil)
        let (document, writing) = try written([plan(textBoxes: [missingFont, unusable, empty], report: [.textStylesNotKept(runCount: 1)])])
        XCTAssertEqual(PDFPageManager.textBoxes(on: try XCTUnwrap(document.page(at: 0))).map(\.plainText), ["Odd font"])
        XCTAssertEqual(writing.pageReports.first?.entries, [.textStylesNotKept(runCount: 1), .fontsReplaced(runCount: 1), .textBoxesNotPlaced(count: 1)])
    }

    func testFlowingTextFillsEachPageInWholeLinesAndGetsPagesOfItsOwn() throws {
        let line = "Line of typed text that flows from page to page.\n"
        let fullText = String(repeating: line, count: 120)
        let flowing = ImportedFlowingText(runs: [run(fullText, font: .postScriptName("HelveticaNeue"), size: 12.84)], left: 15.9375, top: 0,
                                          width: 580.125, continuationPageSize: Self.pageSize, continuationBackground: .plainColor(Self.white))
        let (document, writing) = try written([plan(1, flowingText: flowing), plan(2)])
        XCTAssertGreaterThan(document.pageCount, 2, "the text needs more pages than the note has")
        var joinedText = ""
        for pageIndex in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            let boxes = PDFPageManager.textBoxes(on: page)
            XCTAssertEqual(boxes.count, 1, "page \(pageIndex + 1)")
            let box = try XCTUnwrap(boxes.first)
            XCTAssertEqual(box.origin.x, 15.9375, accuracy: Self.accuracy)
            XCTAssertEqual(box.origin.y, Self.pageSize.height, accuracy: Self.accuracy, "each page's text starts at its top")
            XCTAssertLessThanOrEqual(box.height, Self.pageSize.height + 1, "page \(pageIndex + 1) holds only lines that fit")
            XCTAssertTrue(box.plainText.hasSuffix("\n"), "a page ends after a whole line")
            joinedText += box.plainText
        }
        XCTAssertEqual(joinedText, fullText)
        XCTAssertEqual(writing.pageReports.map(\.sourcePageNumber), Array(1...document.pageCount), "added pages are numbered after the note's")
    }

    func testTheFittingLengthGrowsPastTheFirstPieceAndNeverStopsAtNothing() {
        let style = PDFTextBoxStyle(alignment: .left, padding: 0)
        let attributes = PDFTextAttributes(fontFamily: "Helvetica", fontSize: 4, color: .black)
        let longText = String(repeating: "word ", count: 3_000)
        let fitting = ImportedFlowingTextPlacement.fittingLength(of: [PDFTextRun(text: longText, attributes: attributes)], width: 580, height: 2_000,
                                                                  style: style)
        XCTAssertGreaterThan(fitting, ImportedFlowingTextPlacement.firstMeasuredLength, "a page of small text holds more than the first piece")
        XCTAssertLessThan(fitting, longText.utf16.count)
        let tallLine = PDFTextAttributes(fontFamily: "Helvetica", fontSize: 300, color: .black)
        XCTAssertEqual(ImportedFlowingTextPlacement.fittingLength(of: [PDFTextRun(text: "Huge\nHuge", attributes: tallLine)], width: 580, height: 100,
                                                                  style: style), 5, "a line taller than the page still moves the text on")
    }
}
