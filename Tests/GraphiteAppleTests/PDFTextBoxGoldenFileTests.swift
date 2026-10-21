import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// A PDF with text boxes as the first build with text boxes wrote it
/// (`Tests/Fixtures/PDFTextBoxes/graphite-text-box-v1.pdf`, record version 1), read back by
/// this build: every later build must read it the same, and write it again the same.
final class PDFTextBoxGoldenFileTests: XCTestCase {
    private typealias Documents = PDFTextBoxTestDocuments

    private func golden() throws -> Data {
        try Data(contentsOf: Documents.samplesFolder.appendingPathComponent("graphite-text-box-v1.pdf"))
    }

    /// The boxes the file was written with: one turned by hand with a link, one turned a
    /// quarter, one with every face and a fill and border.
    static func writtenBoxes() -> [PDFTextBox] {
        var underlinedLink = PDFTextAttributes(fontFamily: "Georgia", fontSize: 16, color: PDFTextColor(red: 0, green: 0.3, blue: 0.8), isUnderlined: true)
        underlinedLink.link = URL(string: "https://example.com/lecture-3")
        let turned = PDFTextBox(name: "golden-turned", runs: [PDFTextRun(text: "Turned by hand, see ", attributes: .plain),
                                                              PDFTextRun(text: "the notes", attributes: underlinedLink)],
                                origin: CGPoint(x: 60, y: 520), width: 220, height: 10, rotationRadians: -0.35)
        let quarter = PDFTextBox(name: "golden-quarter", runs: [PDFTextRun(text: "A quarter turn", attributes: PDFTextAttributes(fontFamily: "Helvetica Neue", fontSize: 12, color: .black))],
                                 origin: CGPoint(x: 330, y: 80), width: 160, height: 10, rotationRadians: -.pi / 2)
        let faces = PDFTextBox(name: "golden-faces", runs: [
            PDFTextRun(text: "Bold ", attributes: PDFTextAttributes(fontFamily: "Helvetica", fontSize: 14, color: .black, isBold: true)),
            PDFTextRun(text: "italic ", attributes: PDFTextAttributes(fontFamily: "Helvetica", fontSize: 14, color: .black, isItalic: true)),
            PDFTextRun(text: "red\nsecond line", attributes: PDFTextAttributes(fontFamily: "Times New Roman", fontSize: 20, color: PDFTextColor(red: 0.8, green: 0, blue: 0))),
        ], origin: CGPoint(x: 60, y: 300), width: 200, height: 10,
                               style: PDFTextBoxStyle(alignment: .center, lineSpacing: 1.2, fillColor: PDFTextColor(red: 1, green: 0.96, blue: 0.62),
                                                      borderColor: .black, borderWidth: 1, padding: 6))
        return [turned, quarter, faces].map(PDFTextBoxLayout.fitted)
    }

    func testTheFirstVersionsFileReadsBackAsTheBoxesItWasWrittenWith() throws {
        let page = try XCTUnwrap(try Documents.shownDocument(from: golden()).page(at: 0))
        let read = PDFPageManager.textBoxes(on: page)
        XCTAssertEqual(read.map(\.name), ["golden-turned", "golden-quarter", "golden-faces"])
        for (readBox, writtenBox) in zip(read, Self.writtenBoxes()) {
            XCTAssertEqual(readBox.runs, writtenBox.runs)
            XCTAssertEqual(readBox.style, writtenBox.style)
            XCTAssertEqual(readBox.rotationRadians, writtenBox.rotationRadians, accuracy: 1e-9)
            XCTAssertEqual(readBox.origin.x, writtenBox.origin.x, accuracy: 1e-6)
            XCTAssertEqual(readBox.origin.y, writtenBox.origin.y, accuracy: 1e-6)
            XCTAssertEqual(readBox.width, writtenBox.width, accuracy: 1e-6)
            XCTAssertGreaterThan(readBox.height, 0)
        }
    }

    func testTheFirstVersionsFileHasTheStandardKeysEveryReaderUses() throws {
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: golden()) { dictionaries in
            let freeTexts = dictionaries.filter { dictionary in PDFAnnotationDictionaryReading.name("Subtype", in: dictionary) == "FreeText" }
            XCTAssertEqual(freeTexts.count, 3)
            for freeText in freeTexts {
                XCTAssertNotNil(PDFAnnotationDictionaryReading.string("RC", in: freeText))
                XCTAssertNotNil(PDFAnnotationDictionaryReading.normalAppearanceContent(of: freeText))
                XCTAssertNotNil(PDFAnnotationDictionaryReading.string("DA", in: freeText))
                XCTAssertNotNil(PDFAnnotationDictionaryReading.string("GraphiteTextBoxV1", in: freeText))
            }
            XCTAssertEqual(dictionaries.filter { dictionary in PDFAnnotationDictionaryReading.name("Subtype", in: dictionary) == "Link" }.count, 1)
            XCTAssertEqual(PDFAnnotationDictionaryReading.integer("Rotate", in: freeTexts[1]), 90)
        }
    }

    func testTheFirstVersionsFileIsWrittenAgainWithItsBoxesUnchanged() throws {
        let original = try golden()
        let moved = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.writtenDocument(from: original).page(at: 0))).last)
        var edited = moved
        edited.origin.y -= 20
        let saved = try Documents.savedData(applying: [.replaceTextBox(moved.reference(onPageAt: 0), with: edited)], to: original)
        let reread = PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: saved).page(at: 0)))
        XCTAssertEqual(reread.count, 3)
        XCTAssertEqual(reread.dropLast(), PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: original).page(at: 0))).dropLast())
        XCTAssertEqual(reread.last, edited)
    }
}
