import XCTest
import PDFKit
import CoreGraphics
import GraphiteCore
@testable import GraphiteApple

/// Text boxes as Graphite writes them into a PDF, read with Core Graphics, as another
/// reader sees them: a standard `/FreeText` with its text, looks and appearance, the rich
/// text under `/RC` once saved, and Graphite's record beside the standard keys.
final class PDFTextBoxFileFormatTests: XCTestCase {
    private typealias Documents = PDFTextBoxTestDocuments
    private typealias Reading = PDFAnnotationDictionaryReading

    func testABoxIsAStandardFreeTextWithItsTextLooksAndAppearance() throws {
        let box = Documents.sampleBox()
        let saved = try Documents.savedData(applying: [.addTextBox(page: 0, textBox: box)])
        try Reading.withAnnotationDictionaries(in: saved) { dictionaries in
            XCTAssertEqual(dictionaries.count, 1)
            let freeText = try XCTUnwrap(dictionaries.first)
            XCTAssertEqual(Reading.name("Subtype", in: freeText), "FreeText")
            XCTAssertEqual(Reading.string("NM", in: freeText), box.name)
            XCTAssertEqual(Reading.string("Contents", in: freeText), "Typed text, bold\nand a second line")
            XCTAssertEqual(Reading.integer("Q", in: freeText), 0)
            XCTAssertEqual(Reading.integer("F", in: freeText).map { flags in flags & 4 }, 4)
            let defaultAppearance = try XCTUnwrap(Reading.string("DA", in: freeText))
            XCTAssertTrue(defaultAppearance.contains("Helvetica") && defaultAppearance.contains("14 Tf"), defaultAppearance)
            XCTAssertEqual(Reading.string("DS", in: freeText), "font: Helvetica 14pt; text-align:left; color:#000000")
            XCTAssertEqual(try XCTUnwrap(Reading.numbers("C", in: freeText)), [1, 1, 0.8], accuracy: 0.01)
            let rectangle = try XCTUnwrap(Reading.numbers("Rect", in: freeText))
            XCTAssertEqual(rectangle[0], 60, accuracy: 0.01)
            XCTAssertEqual(rectangle[3], 500, accuracy: 0.01)
            XCTAssertNotNil(Reading.normalAppearanceContent(of: freeText), "Every reader draws the box from its appearance.")
            XCTAssertFalse(Reading.hasKey("Rotate", in: freeText), "An upright box has no /Rotate.")
        }
    }

    func testTheSavedFileHasTheRichTextUnderItsStandardKeyAndNoMarkupCopy() throws {
        let box = Documents.sampleBox()
        let written = try Documents.writtenData(applying: [.addTextBox(page: 0, textBox: box)])
        let compacted = try XCTUnwrap(PDFObjectCompaction.compacted(written))
        XCTAssertEqual(compacted.report.textBoxRichTextsNamed, 1)
        try Reading.withAnnotationDictionaries(in: compacted.data) { dictionaries in
            let freeText = try XCTUnwrap(dictionaries.first)
            let richText = try XCTUnwrap(Reading.string("RC", in: freeText))
            XCTAssertEqual(richText, PDFTextBoxRichText.richText(of: box))
            XCTAssertFalse(Reading.hasKey("GraphiteRichTextV1", in: freeText))
            XCTAssertFalse(Reading.hasKey("AAPL:AKExtras", in: freeText))
            let record = try XCTUnwrap(Reading.string("GraphiteTextBoxV1", in: freeText).flatMap(PDFTextBoxRecord.decoded(from:)))
            XCTAssertEqual(record, PDFTextBoxRecord(box: box))
        }
        XCTAssertEqual(PDFDocument(data: compacted.data)?.pageCount, 1)
    }

    func testEveryStreamOfTheSavedFileHasItsLengthAndTheEmbeddedFontsTheirs() throws {
        // PDFKit writes the font an appearance embeds without `/Length` when the document was
        // read from a file; compaction gives it its length (`StreamLengthRepair`).
        let written = try Documents.writtenData(applying: [.addTextBox(page: 0, textBox: Documents.sampleBox())])
        let compacted = try XCTUnwrap(PDFObjectCompaction.compacted(written))
        let text = String(decoding: compacted.data, as: UTF8.self)
        let streamDictionaries = text.components(separatedBy: "stream\n").dropLast().map { before in before.components(separatedBy: " obj").last ?? "" }
        XCTAssertFalse(streamDictionaries.isEmpty)
        for dictionary in streamDictionaries where !dictionary.hasSuffix("end") {
            XCTAssertTrue(dictionary.contains("/Length "), dictionary)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: compacted.data as CFData))
        XCTAssertNotNil(CGPDFDocument(provider)?.page(at: 1))
        XCTAssertGreaterThan(compacted.report.streamLengthsRepaired, 0, "This PDFKit leaves out the font's length; when it stops, the repair has nothing to do.")
    }

    func testABoxWrittenAndOpenedAgainIsTheSameBox() throws {
        let box = Documents.sampleBox(rotation: -0.35, link: URL(string: "https://example.com/notes"))
        let saved = try Documents.savedData(applying: [.addTextBox(page: 0, textBox: box)])
        let shown = try Documents.shownDocument(from: saved)
        let page = try XCTUnwrap(shown.page(at: 0))
        XCTAssertEqual(PDFPageManager.textBoxes(on: page), [box])
        let opened = try Documents.writtenDocument(from: saved)
        XCTAssertEqual(PDFPageManager.textBoxes(on: try XCTUnwrap(opened.page(at: 0))), [box])
    }

    func testABoxTurnedAQuarterHasTheStandardRotateAndReadsBackWithoutTheRecord() throws {
        let box = Documents.sampleBox(rotation: -.pi / 2)
        let saved = try Documents.savedData(applying: [.addTextBox(page: 0, textBox: box)])
        try Reading.withAnnotationDictionaries(in: saved) { dictionaries in
            XCTAssertEqual(Reading.integer("Rotate", in: try XCTUnwrap(dictionaries.first)), 90)
        }
        // A reader without the record, as Graphite reads another application's box.
        let document = try Documents.writtenDocument(from: saved)
        let annotation = try XCTUnwrap(document.page(at: 0)?.annotations.first)
        annotation.removeValue(forAnnotationKey: PDFPageManager.textBoxRecordKey)
        let standard = try XCTUnwrap(PDFTextBox.reading(of: annotation))
        XCTAssertEqual(standard.rotationRadians, -.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(standard.origin.x, box.origin.x, accuracy: 0.01)
        XCTAssertEqual(standard.origin.y, box.origin.y, accuracy: 0.01)
        XCTAssertEqual(standard.width, box.width, accuracy: 0.01)
        XCTAssertEqual(standard.runs, box.runs, "The rich text gives the runs back.")
    }

    func testALinkInTheTextIsALinkAnnotationThatBelongsToTheBox() throws {
        let link = try XCTUnwrap(URL(string: "https://example.com/lecture"))
        let box = Documents.sampleBox(link: link)
        let saved = try Documents.savedData(applying: [.addTextBox(page: 0, textBox: box)])
        try Reading.withAnnotationDictionaries(in: saved) { dictionaries in
            let links = dictionaries.filter { dictionary in Reading.name("Subtype", in: dictionary) == "Link" }
            XCTAssertEqual(links.count, 1)
            let linkDictionary = try XCTUnwrap(links.first)
            XCTAssertEqual(Reading.string("GraphiteTextBoxLinkOwner", in: linkDictionary), box.name)
            var action: CGPDFDictionaryRef?
            XCTAssertTrue(CGPDFDictionaryGetDictionary(linkDictionary, "A", &action))
            XCTAssertEqual(action.flatMap { action in Reading.string("URI", in: action) }, link.absoluteString)
            XCTAssertEqual(Reading.numbers("QuadPoints", in: linkDictionary)?.count, 8)
        }
    }

    func testMovingABoxMovesItsLinksAndRemovingItRemovesThem() throws {
        let box = Documents.sampleBox(link: URL(string: "https://example.com"))
        let document = try Documents.writtenDocument(from: try Documents.blankPageData())
        try PDFPageManager.replay([.addTextBox(page: 0, textBox: box)], on: document)
        let page = try XCTUnwrap(document.page(at: 0))
        let linkBefore = try XCTUnwrap(page.annotations.first { annotation in annotation.type == "Link" }).bounds
        var moved = box
        moved.origin.x += 40
        try PDFPageManager.apply(.replaceTextBox(box.reference(onPageAt: 0), with: moved), to: document, drawsInkOutlines: true)
        let linksAfterMove = page.annotations.filter { annotation in annotation.type == "Link" }
        XCTAssertEqual(linksAfterMove.count, 1)
        XCTAssertEqual(try XCTUnwrap(linksAfterMove.first).bounds.minX, linkBefore.minX + 40, accuracy: 0.01)
        try PDFPageManager.apply(.removeTextBox(moved.reference(onPageAt: 0)), to: document, drawsInkOutlines: true)
        XCTAssertTrue(page.annotations.isEmpty)
    }

    func testAnEmptyOrDamagedBoxIsRefusedBeforeItIsWritten() throws {
        let document = try Documents.writtenDocument(from: try Documents.blankPageData())
        var damaged = Documents.sampleBox()
        damaged.origin = CGPoint(x: CGFloat.nan, y: 0)
        XCTAssertThrowsError(try PDFPageManager.apply(.addTextBox(page: 0, textBox: damaged), to: document, drawsInkOutlines: true))
        XCTAssertThrowsError(try PDFPageManager.apply(.addTextBox(page: 3, textBox: Documents.sampleBox()), to: document, drawsInkOutlines: true))
        XCTAssertEqual(document.page(at: 0)?.annotations.count, 0)
    }
}

private func XCTAssertEqual(_ first: [Double], _ second: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(first.count, second.count, file: file, line: line)
    for (firstValue, secondValue) in zip(first, second) { XCTAssertEqual(firstValue, secondValue, accuracy: accuracy, file: file, line: line) }
}
