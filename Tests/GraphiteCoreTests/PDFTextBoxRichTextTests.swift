import XCTest
import CoreGraphics
@testable import GraphiteCore

/// The `/RC` rich text of a text box: written as Acrobat writes it, read from Acrobat's and
/// Graphite's, and refused when it is not well-formed, so the box opens as plain text.
final class PDFTextBoxRichTextTests: XCTestCase {
    private let regular = PDFTextAttributes(fontFamily: "Helvetica Neue", fontSize: 14, color: .black)

    private func box(_ runs: [PDFTextRun], alignment: PDFTextAlignment = .left) -> PDFTextBox {
        PDFTextBox(name: "rich", runs: runs, origin: .zero, width: 200, height: 40, style: PDFTextBoxStyle(alignment: alignment))
    }

    func testRichTextWrittenByGraphiteReadsBackAsTheSameRunsAndAlignment() throws {
        var bold = regular
        bold.isBold = true
        var red = regular
        red.color = PDFTextColor(red: 1, green: 0, blue: 0)
        red.isItalic = true
        red.isUnderlined = true
        red.fontSize = 18.5
        let runs = [PDFTextRun(text: "Plain & <bold> ", attributes: regular), PDFTextRun(text: "Bold", attributes: bold),
                    PDFTextRun(text: "\n\nRed \"quoted\"", attributes: red)]
        let written = PDFTextBoxRichText.richText(of: box(runs, alignment: .center))
        let reading = try XCTUnwrap(PDFTextBoxRichText.reading(written, defaults: .plain))
        XCTAssertEqual(reading.runs, PDFTextRun.normalized(runs))
        XCTAssertEqual(reading.alignment, .center)
    }

    func testEachLineIsAParagraphAsAcrobatWritesIt() {
        let written = PDFTextBoxRichText.richText(of: box([PDFTextRun(text: "one\ntwo", attributes: regular)]))
        XCTAssertTrue(written.hasPrefix("<?xml version=\"1.0\"?><body xmlns=\"http://www.w3.org/1999/xhtml\""))
        XCTAssertTrue(written.contains("xfa:spec=\"2.0.2\""))
        XCTAssertEqual(written.components(separatedBy: "<p dir=\"ltr\">").count - 1, 2)
        XCTAssertTrue(written.contains("font-family:'Helvetica Neue';font-size:14pt;color:#000000;font-weight:normal"))
    }

    func testAcrobatsRichTextIsReadWithItsBoldItalicUnderlineColorsAndSizes() throws {
        let acrobat = """
            <?xml version="1.0"?><body xmlns="http://www.w3.org/1999/xhtml" xmlns:xfa="http://www.xfa.org/schema/xfa-data/1.0/" \
            xfa:APIVersion="Acrobat:23.6.0" xfa:spec="2.0.2" style="font-size:12.0pt;text-align:left;color:#FF0000;font-weight:normal;\
            font-style:normal;font-family:Helvetica,sans-serif;font-stretch:normal"><p dir="ltr"><span style="font-family:Helvetica">\
            Hello <b>bold</b> <i>italic</i> <span style="text-decoration:underline">under</span></span></p><p dir="ltr">\
            <span style="color:#0000FF;font-size:18.0pt">Second line</span></p></body>
            """
        let reading = try XCTUnwrap(PDFTextBoxRichText.reading(acrobat, defaults: .plain))
        let red = PDFTextColor(red: 1, green: 0, blue: 0)
        let base = PDFTextAttributes(fontFamily: "Helvetica", fontSize: 12, color: red)
        var bold = base; bold.isBold = true
        var italic = base; italic.isItalic = true
        var underlined = base; underlined.isUnderlined = true
        let blue = PDFTextAttributes(fontFamily: "Helvetica", fontSize: 18, color: PDFTextColor(red: 0, green: 0, blue: 1))
        XCTAssertEqual(reading.runs, [PDFTextRun(text: "Hello ", attributes: base), PDFTextRun(text: "bold", attributes: bold),
                                      PDFTextRun(text: " ", attributes: base), PDFTextRun(text: "italic", attributes: italic),
                                      PDFTextRun(text: " ", attributes: base), PDFTextRun(text: "under", attributes: underlined),
                                      PDFTextRun(text: "\nSecond line", attributes: blue)])
        XCTAssertEqual(reading.alignment, .left)
    }

    func testRichTextThatIsNotWellFormedIsRefused() {
        XCTAssertNil(PDFTextBoxRichText.reading("<body><p>unclosed", defaults: .plain))
        XCTAssertNil(PDFTextBoxRichText.reading("not markup at all", defaults: .plain))
        XCTAssertNil(PDFTextBoxRichText.reading("<html><p>no body</p></html>", defaults: .plain))
        XCTAssertNil(PDFTextBoxRichText.reading("", defaults: .plain))
    }

    func testRichTextNestedPastTheLimitIsRefused() {
        let depth = PDFTextBoxRichText.maximumNesting + 4
        let nested = "<body>" + String(repeating: "<span>", count: depth) + "deep" + String(repeating: "</span>", count: depth) + "</body>"
        XCTAssertNil(PDFTextBoxRichText.reading(nested, defaults: .plain))
    }

    func testAnEntityDefinedInTheTextIsNotExpanded() throws {
        let withEntity = "<?xml version=\"1.0\"?><!DOCTYPE body [<!ENTITY x SYSTEM \"file:///etc/passwd\">]><body><p>a&x;b</p></body>"
        let reading = PDFTextBoxRichText.reading(withEntity, defaults: .plain)
        XCTAssertFalse(reading?.runs.map(\.text).joined().contains("root") ?? false)
    }

    func testTheDefaultStyleIsWrittenAsAcrobatWritesIt() {
        var attributes = regular
        attributes.isBold = true
        let written = PDFTextStyleDeclarations.defaultStyleText(of: box([PDFTextRun(text: "x", attributes: attributes)], alignment: .right))
        XCTAssertEqual(written, "font: bold 'Helvetica Neue' 14pt; text-align:right; color:#000000")
    }

    func testTheDefaultStyleIsReadInAcrobatsOrderAndInTheOrderCSSGives() {
        let acrobat = PDFTextStyleDeclarations.properties(of: "font: Helvetica,sans-serif 12.0pt; text-align:left; color:#FF0000 ")
        XCTAssertEqual(acrobat.fontFamily, "Helvetica")
        XCTAssertEqual(acrobat.fontSize, 12)
        XCTAssertEqual(acrobat.color, PDFTextColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(acrobat.alignment, .left)
        let css = PDFTextStyleDeclarations.properties(of: "font: italic bold 16px 'Times New Roman', serif; text-align: justify")
        XCTAssertEqual(css.fontFamily, "Times New Roman")
        XCTAssertEqual(css.fontSize, 12)
        XCTAssertEqual(css.isBold, true)
        XCTAssertEqual(css.isItalic, true)
        XCTAssertEqual(css.alignment, .justified)
        let written = PDFTextStyleDeclarations.properties(of: PDFTextStyleDeclarations.defaultStyleText(of: box([PDFTextRun(text: "x", attributes: regular)])))
        XCTAssertEqual(written.fontFamily, "Helvetica Neue")
        XCTAssertEqual(written.fontSize, 14)
    }

    func testStyleTextThatSaysNothingUsableChangesNothing() {
        let properties = PDFTextStyleDeclarations.properties(of: "garbage;;: ;color: notacolor; font-size: -3pt")
        XCTAssertEqual(properties, PDFTextStyleDeclarations.Properties())
        XCTAssertEqual(PDFTextStyleDeclarations.color("rgb(255, 128, 0)"), PDFTextColor(red: 1, green: 128.0 / 255, blue: 0))
    }
}
