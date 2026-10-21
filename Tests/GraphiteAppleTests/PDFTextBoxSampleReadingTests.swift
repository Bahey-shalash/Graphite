import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// Text boxes other applications made, opened in Graphite as editable boxes.
///
/// The samples under `Tests/Fixtures/PDFTextBoxes` are not files from Preview or Acrobat
/// themselves, which cannot be run here: `preview-style-free-text.pdf` was written by
/// PDFKit's own `/FreeText` annotation, which is what Preview uses; `acrobat-style-free-text.pdf`
/// was written by hand with the keys Acrobat writes (`/RC` XHTML with `xfa:spec` 2.0.2, `/DS`,
/// `/IT`, `/RD`, `/Subj`, a vendor key) and an appearance of its own.
final class PDFTextBoxSampleReadingTests: XCTestCase {
    private typealias Documents = PDFTextBoxTestDocuments

    private func sample(_ name: String) throws -> PDFDocument {
        try Documents.shownDocument(from: Data(contentsOf: Documents.samplesFolder.appendingPathComponent(name)))
    }

    func testABoxMadeAsPreviewMakesOneOpensWithItsFontColorAlignmentFillAndBorder() throws {
        let page = try XCTUnwrap(try sample("preview-style-free-text.pdf").page(at: 0))
        let boxes = PDFPageManager.textBoxes(on: page)
        XCTAssertEqual(boxes.count, 2)
        let box = try XCTUnwrap(boxes.first)
        XCTAssertEqual(box.plainText, "Made like Preview\nSecond line")
        let attributes = box.leadingAttributes
        XCTAssertEqual(attributes.fontFamily, "Georgia")
        XCTAssertTrue(attributes.isBold)
        XCTAssertEqual(attributes.fontSize, 16, accuracy: 0.01)
        XCTAssertEqual(attributes.color.blue, 1, accuracy: 0.02)
        XCTAssertEqual(box.style.alignment, .center)
        XCTAssertEqual(try XCTUnwrap(box.style.fillColor).blue, 0.6, accuracy: 0.02)
        XCTAssertEqual(box.style.borderWidth, 1)
        XCTAssertEqual(box.annotationBounds, CGRect(x: 40, y: 180, width: 220, height: 60))
        XCTAssertEqual(box.rotationRadians, 0)
        // A box without a name is found again by its rectangle.
        let unnamed = try XCTUnwrap(boxes.last)
        XCTAssertEqual(unnamed.name, "")
        XCTAssertNil(unnamed.style.fillColor)
        XCTAssertNil(unnamed.reference(onPageAt: 0).name)
    }

    func testABoxMadeAsAcrobatMakesOneOpensWithItsRichText() throws {
        let page = try XCTUnwrap(try sample("acrobat-style-free-text.pdf").page(at: 0))
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: page).first)
        XCTAssertEqual(box.name, "acrobat-box-1")
        XCTAssertEqual(box.plainText, "Hello bold italic under\nSecond line")
        XCTAssertEqual(box.runs.map(\.text), ["Hello ", "bold", " ", "italic", " ", "under", "\nSecond line"])
        XCTAssertEqual(box.runs[1].attributes.isBold, true)
        XCTAssertEqual(box.runs[3].attributes.isItalic, true)
        XCTAssertEqual(box.runs[5].attributes.isUnderlined, true)
        XCTAssertEqual(box.runs[0].attributes.color, PDFTextColor(red: 1, green: 0, blue: 0))
        XCTAssertEqual(box.runs[6].attributes.fontSize, 18)
        XCTAssertEqual(box.preservedEntries["IT"], .name("FreeTextTypeWriter"))
        XCTAssertEqual(box.preservedEntries["Subj"], .text("Typewriter"))
        XCTAssertEqual(box.preservedEntries["AcrobatVendorKey"], .text("keep me"))
        XCTAssertNil(box.preservedEntries["RD"], "The appearance Graphite draws fills the whole rectangle.")
    }

    func testAnotherApplicationsKeysAreKeptWhenGraphiteWritesTheBoxAgain() throws {
        let sampleData = try Data(contentsOf: Documents.samplesFolder.appendingPathComponent("acrobat-style-free-text.pdf"))
        let original = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.writtenDocument(from: sampleData).page(at: 0))).first)
        var edited = original
        edited.runs = [PDFTextRun(text: "Edited in Graphite", attributes: original.leadingAttributes)]
        edited.origin.y -= 50
        edited = PDFTextBoxLayout.fitted(edited)
        let saved = try Documents.savedData(applying: [.replaceTextBox(original.reference(onPageAt: 0), with: edited)], to: sampleData)
        try PDFAnnotationDictionaryReading.withAnnotationDictionaries(in: saved) { dictionaries in
            XCTAssertEqual(dictionaries.count, 1)
            let freeText = try XCTUnwrap(dictionaries.first)
            XCTAssertEqual(PDFAnnotationDictionaryReading.name("IT", in: freeText), "FreeTextTypeWriter")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("Subj", in: freeText), "Typewriter")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("AcrobatVendorKey", in: freeText), "keep me")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("NM", in: freeText), "acrobat-box-1")
            XCTAssertEqual(PDFAnnotationDictionaryReading.string("Contents", in: freeText), "Edited in Graphite")
            XCTAssertTrue(try XCTUnwrap(PDFAnnotationDictionaryReading.string("RC", in: freeText)).contains("Edited in Graphite"),
                          "The rich text is the new text, not Acrobat's old one.")
            XCTAssertFalse(PDFAnnotationDictionaryReading.hasKey("RD", in: freeText))
        }
        let reopened = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: saved).page(at: 0))).first)
        XCTAssertEqual(reopened.runs, edited.runs)
        XCTAssertEqual(reopened.preservedEntries, original.preservedEntries)
    }

    func testRichTextThatDoesNotParseOpensAsThePlainText() throws {
        let data = handWrittenFreeText(extraKeys: "/RC (<body><p>unclosed) /DA (/Helv 11 Tf 0 0 1 rg)", contents: "Plain fallback")
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: data).page(at: 0))).first)
        XCTAssertEqual(box.runs.count, 1)
        XCTAssertEqual(box.plainText, "Plain fallback")
        XCTAssertEqual(box.leadingAttributes.fontSize, 11, accuracy: 0.01)
        XCTAssertEqual(box.leadingAttributes.color.blue, 1, accuracy: 0.02)
    }

    func testRichTextThatSaysOtherThanTheContentsIsNotTrusted() throws {
        let data = handWrittenFreeText(extraKeys: "/RC (<body><p>Old text</p></body>)", contents: "New text")
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: data).page(at: 0))).first)
        XCTAssertEqual(box.plainText, "New text")
    }

    func testAGraphiteRecordThatNoLongerMatchesTheTextIsLeftForTheStandardKeys() throws {
        let record = try PDFTextBoxRecord(box: Documents.sampleBox()).encodedText()
        let escapedRecord = record.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
        let data = handWrittenFreeText(extraKeys: "/NM (changed-elsewhere) /GraphiteTextBoxV1 (\(escapedRecord))", contents: "Changed in another app")
        let box = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: data).page(at: 0))).first)
        XCTAssertEqual(box.plainText, "Changed in another app")
        XCTAssertEqual(box.annotationBounds, CGRect(x: 20, y: 20, width: 200, height: 50))
    }

    func testADamagedRecordAnEmptyBoxAndAMissingAppearanceOpenWithoutTrapping() throws {
        let damaged = handWrittenFreeText(extraKeys: "/NM (damaged) /GraphiteTextBoxV1 ({\"version\": 1, \"runs\": 7})", contents: "Still readable")
        XCTAssertEqual(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: damaged).page(at: 0))).first?.plainText,
                       "Still readable")
        let empty = handWrittenFreeText(extraKeys: "", contents: nil)
        let emptyBox = try XCTUnwrap(PDFPageManager.textBoxes(on: try XCTUnwrap(try Documents.shownDocument(from: empty).page(at: 0))).first)
        XCTAssertTrue(emptyBox.runs.isEmpty)
        let page = try XCTUnwrap(try Documents.shownDocument(from: damaged).page(at: 0))
        // Drawing a box without an appearance or record falls back to PDFKit's own drawing.
        let context = try XCTUnwrap(CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        page.draw(with: .mediaBox, to: context)
    }

    /// One page with one `/FreeText` at [20 20 220 70] and no appearance.
    private func handWrittenFreeText(extraKeys: String, contents: String?) -> Data {
        let contentsEntry = contents.map { text in "/Contents (\(text))" } ?? ""
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Annots [4 0 R] >>",
            "<< /Type /Annot /Subtype /FreeText /Rect [20 20 220 70] \(contentsEntry) \(extraKeys) >>",
        ]
        var text = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(text.utf8)
    }
}
