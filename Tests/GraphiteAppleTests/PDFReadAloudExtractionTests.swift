import XCTest
import CoreGraphics
import CoreText
import PDFKit
import GraphiteCore
@testable import GraphiteApple

final class PDFReadAloudExtractionTests: XCTestCase {
    private static let leftLines = ["Left column begins with a hypothesis.", "We test the repeated word carefully.",
                                    "The observation supports our result.", "This is the final left column sentence."]
    private static let rightLines = ["Right column begins with a conclusion.", "The repeated word occurs again here.",
                                     "Our experiment has a second outcome.", "This is the final right column sentence."]

    func testMixedColumnsAndSpanningHeadingKeepEveryOriginalWordAndCoordinate() async throws {
        guard #available(macOS 26, iOS 26, *) else { throw XCTSkip("Document layout recognition requires operating system 26.") }
        let bytes = try Self.fixture()
        let page = try await PDFReadAloudExtraction().page(in: bytes, readingOrder: .layout)
        XCTAssertTrue(page.usesLayout, page.layoutNotice ?? "")
        let expectedLines = ["Reading a Research Paper"] + Self.leftLines + Self.rightLines +
            ["A second section across both columns"] + Self.leftLines.map { $0.replacingOccurrences(of: "Left", with: "Lower left") } +
            Self.rightLines.map { $0.replacingOccurrences(of: "Right", with: "Lower right") }
        XCTAssertEqual(page.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty },
                       expectedLines.joined(separator: " ").components(separatedBy: " "))
        let nativePage = try XCTUnwrap(PDFDocument(data: bytes)?.page(at: 0))
        let original = page.originalText as NSString
        let prepared = page.text as NSString
        let originalWords = try NSRegularExpression(pattern: "\\S+").matches(in: page.originalText, range: NSRange(location: 0, length: original.length))
        XCTAssertEqual(page.segments.count, originalWords.count)
        XCTAssertEqual(Set(page.segments.map(\.pageRange)), Set(originalWords.map(\.range)))
        for segment in page.segments {
            XCTAssertEqual(prepared.substring(with: segment.textRange), original.substring(with: segment.pageRange))
            XCTAssertEqual(nativePage.selection(for: segment.pageRange)?.string, prepared.substring(with: segment.textRange))
            XCTAssertFalse(try XCTUnwrap(nativePage.selection(for: segment.pageRange)).bounds(for: nativePage).isEmpty)
        }
        let repeated = page.segments.filter { original.substring(with: $0.pageRange) == "repeated" }
        XCTAssertEqual(repeated.count, 4)
        XCTAssertEqual(Set(repeated.map(\.pageRange)).count, 4)
    }

    func testNativeRangeEndpointsMapIntoThePreparedColumnOrder() async throws {
        guard #available(macOS 26, iOS 26, *) else { throw XCTSkip("Document layout recognition requires operating system 26.") }
        let page = try await PDFReadAloudExtraction().page(in: Self.fixture(), readingOrder: .layout)
        XCTAssertTrue(page.usesLayout)
        let original = page.originalText as NSString
        let start = original.range(of: "We test the repeated word carefully.").location
        let end = NSMaxRange(original.range(of: "Right column begins with a conclusion."))
        let selectedRange = try page.selectedRange(startOffset: start, endOffset: end)
        XCTAssertEqual((page.text as NSString).substring(with: selectedRange),
                       ([Self.leftLines[1], Self.leftLines[2], Self.leftLines[3], Self.rightLines[0]]).joined(separator: "\n"))
        XCTAssertThrowsError(try page.selectedRange(startOffset: end - 1, endOffset: start))
        XCTAssertThrowsError(try page.selectedRange(startOffset: -1, endOffset: nil))
        XCTAssertThrowsError(try page.selectedRange(startOffset: nil, endOffset: original.length + 1))
    }

    func testFileOrderIsExactAndDoesNotInvokeRecognition() async throws {
        let bytes = try Self.fixture()
        let original = try XCTUnwrap(PDFDocument(data: bytes)?.page(at: 0)?.string)
        let page = try await PDFReadAloudExtraction().page(in: bytes, readingOrder: .file)
        XCTAssertEqual(page.text, original)
        XCTAssertFalse(page.usesLayout)
        XCTAssertNil(page.layoutNotice)
        XCTAssertEqual(page.segments.count, 1)
        XCTAssertEqual(try page.selectedRange(startOffset: 2, endOffset: 5), NSRange(location: 2, length: 3))
    }

    func testEndpointsCanFollowLayoutEvenWhenOriginalOffsetsAreReversed() throws {
        let page = PDFReadAloudPage(originalText: "second first", text: "first second", segments: [
            .init(textRange: NSRange(location: 0, length: 5), pageRange: NSRange(location: 7, length: 5)),
            .init(textRange: NSRange(location: 6, length: 6), pageRange: NSRange(location: 0, length: 6))
        ], layoutNotice: nil, usesLayout: true)
        XCTAssertEqual(try page.selectedRange(startOffset: 7, endOffset: 6), NSRange(location: 0, length: 12))
        XCTAssertThrowsError(try page.selectedRange(startOffset: 0, endOffset: 12))
        XCTAssertThrowsError(try page.selectedRange(startOffset: 6, endOffset: nil))
    }

    func testSingleColumnAndTableFallbackRetainAllOriginalText() async throws {
        let extraction = PDFReadAloudExtraction()
        let singleColumn = try await extraction.page(in: Self.fixture(isSingleColumn: true), readingOrder: .layout)
        if #available(macOS 26, iOS 26, *) { XCTAssertTrue(singleColumn.usesLayout) }
        XCTAssertEqual(singleColumn.text.split(whereSeparator: \.isWhitespace),
                       singleColumn.originalText.split(whereSeparator: \.isWhitespace))
        let table = try await extraction.page(in: Self.fixture(isTable: true), readingOrder: .layout)
        XCTAssertFalse(table.usesLayout)
        XCTAssertEqual(table.text, table.originalText)
        XCTAssertNotNil(table.layoutNotice)
    }

    func testRotatedCropPreservesAllTextAndSafeCoordinatesOrExplainsFallback() async throws {
        let bytes = try Self.fixture(rotation: 90)
        let page = try await PDFReadAloudExtraction().page(in: bytes, readingOrder: .layout)
        let nativePage = try XCTUnwrap(PDFDocument(data: bytes)?.page(at: 0))
        XCTAssertEqual(page.originalText, nativePage.string)
        if page.usesLayout {
            for segment in page.segments {
                XCTAssertEqual(nativePage.selection(for: segment.pageRange)?.string, (page.text as NSString).substring(with: segment.textRange))
            }
        } else {
            XCTAssertEqual(page.text, page.originalText)
            XCTAssertNotNil(page.layoutNotice)
        }
    }

    func testBlankInvalidAndCanceledPagesNeverBecomeSuccessfulNarration() async throws {
        let extraction = PDFReadAloudExtraction()
        for bytes in [Data("not a PDF".utf8), try Self.fixture(isBlank: true)] {
            do {
                _ = try await extraction.page(in: bytes, readingOrder: .layout)
                XCTFail("An unreadable page must not prepare successfully.")
            } catch ReadAloudError.noReadableText {}
        }
        let bytes = try Self.fixture()
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await extraction.page(in: bytes, readingOrder: .layout)
        }
        do { _ = try await worker.value; XCTFail("Canceled extraction must not succeed.") }
        catch is CancellationError {}
        let next = try await extraction.page(in: bytes, readingOrder: .file)
        XCTAssertFalse(next.text.isEmpty)
    }

    private static func fixture(rotation: Int = 0, isBlank: Bool = false, isSingleColumn: Bool = false, isTable: Bool = false) throws -> Data {
        let bytes = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: bytes))
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 12) {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: x, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }
        if isTable {
            for columnIndex in 0...3 {
                context.move(to: CGPoint(x: 54 + CGFloat(columnIndex) * 150, y: 400))
                context.addLine(to: CGPoint(x: 54 + CGFloat(columnIndex) * 150, y: 700))
            }
            for rowIndex in 0...6 {
                context.move(to: CGPoint(x: 54, y: 400 + CGFloat(rowIndex) * 50))
                context.addLine(to: CGPoint(x: 504, y: 400 + CGFloat(rowIndex) * 50))
            }
            context.strokePath()
            for rowIndex in 0..<6 {
                draw("Sample \(rowIndex)", x: 64, y: 665 - CGFloat(rowIndex) * 50)
                draw("Value \(rowIndex * 10)", x: 214, y: 665 - CGFloat(rowIndex) * 50)
                draw("Unit meters", x: 364, y: 665 - CGFloat(rowIndex) * 50)
            }
        } else if !isBlank {
            draw("Reading a Research Paper", x: 54, y: 738, size: 20)
            for lineIndex in leftLines.indices {
                draw(leftLines[lineIndex], x: 54, y: 690 - CGFloat(lineIndex) * 20)
                if !isSingleColumn { draw(rightLines[lineIndex], x: 324, y: 690 - CGFloat(lineIndex) * 20) }
            }
            draw("A second section across both columns", x: 54, y: 552, size: 18)
            for lineIndex in leftLines.indices {
                draw(leftLines[lineIndex].replacingOccurrences(of: "Left", with: "Lower left"), x: 54, y: 512 - CGFloat(lineIndex) * 20)
                if !isSingleColumn { draw(rightLines[lineIndex].replacingOccurrences(of: "Right", with: "Lower right"), x: 324, y: 512 - CGFloat(lineIndex) * 20) }
            }
        }
        context.endPDFPage()
        context.closePDF()
        guard rotation != 0 else { return bytes as Data }
        let document = try XCTUnwrap(PDFDocument(data: bytes as Data))
        let page = try XCTUnwrap(document.page(at: 0))
        page.rotation = rotation
        page.setBounds(CGRect(x: 20, y: 40, width: 572, height: 732), for: .cropBox)
        return try XCTUnwrap(document.dataRepresentation())
    }
}
