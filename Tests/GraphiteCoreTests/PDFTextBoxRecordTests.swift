import XCTest
import CoreGraphics
@testable import GraphiteCore

/// Graphite's record of a text box: written the same for the same box, read back exactly,
/// and refused, so the standard keys are read instead, when it is not one this build wrote.
final class PDFTextBoxRecordTests: XCTestCase {
    private func box() -> PDFTextBox {
        var linked = PDFTextAttributes(fontFamily: "Georgia", fontSize: 16, color: PDFTextColor(red: 0, green: 0.3, blue: 0.8), isUnderlined: true)
        linked.link = URL(string: "https://example.com/a?b=c")
        return PDFTextBox(name: "recorded", runs: [PDFTextRun(text: "See ", attributes: .plain), PDFTextRun(text: "this page", attributes: linked)],
                          origin: CGPoint(x: 72.5, y: 700.25), width: 220, height: 36.5, rotationRadians: -0.25,
                          style: PDFTextBoxStyle(alignment: .justified, lineSpacing: 1.2, fillColor: PDFTextColor(red: 1, green: 1, blue: 0.8),
                                                 borderColor: .black, borderWidth: 1.5, padding: 6))
    }

    func testARecordReadsBackAsTheSameBox() throws {
        let original = box()
        let text = try PDFTextBoxRecord(box: original).encodedText()
        let record = try XCTUnwrap(PDFTextBoxRecord.decoded(from: text))
        XCTAssertEqual(record.box(named: original.name, preservedEntries: [:]), original)
        XCTAssertEqual(record.contents, "See this page")
        XCTAssertEqual(record.writtenRectangle, original.annotationBounds)
    }

    func testTheSameBoxIsAlwaysWrittenTheSame() throws {
        XCTAssertEqual(try PDFTextBoxRecord(box: box()).encodedText(), try PDFTextBoxRecord(box: box()).encodedText())
        XCTAssertTrue(try PDFTextBoxRecord(box: box()).encodedText().hasPrefix("{\"contents\":"))
    }

    func testARecordOfAnotherVersionOrForm() throws {
        let text = try PDFTextBoxRecord(box: box()).encodedText()
        XCTAssertNil(PDFTextBoxRecord.decoded(from: text.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")))
        XCTAssertNil(PDFTextBoxRecord.decoded(from: text.replacingOccurrences(of: "\"justified\"", with: "\"diagonal\"")))
        XCTAssertNil(PDFTextBoxRecord.decoded(from: "{}"))
        XCTAssertNil(PDFTextBoxRecord.decoded(from: "not json"))
        XCTAssertNil(PDFTextBoxRecord.decoded(from: String(repeating: " ", count: PDFTextBoxRecord.maximumEncodedBytes + 1)))
    }

    func testARecordWithValuesNoBoxCanHaveIsRefusedOrBroughtInside() throws {
        let text = try PDFTextBoxRecord(box: box()).encodedText()
        XCTAssertNil(PDFTextBoxRecord.decoded(from: text.replacingOccurrences(of: "\"width\":220", with: "\"width\":-1")))
        let oversized = text.replacingOccurrences(of: "\"fontSize\":16", with: "\"fontSize\":100000")
        let record = try XCTUnwrap(PDFTextBoxRecord.decoded(from: oversized))
        XCTAssertEqual(record.box(named: "n", preservedEntries: [:]).runs.last?.attributes.fontSize, PDFTextAttributes.fontSizeRange.upperBound)
    }
}
