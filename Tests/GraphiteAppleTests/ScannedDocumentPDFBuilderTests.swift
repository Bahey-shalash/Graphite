import XCTest
import CoreGraphics
import CoreText
import PDFKit
@testable import GraphiteApple
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

final class ScannedDocumentPDFBuilderTests: XCTestCase {
    private static let knownWords = [
        ScannedPageWord(text: "alpha", normalizedBounds: CGRect(x: 0.10, y: 0.80, width: 0.20, height: 0.04)),
        ScannedPageWord(text: "bravo", normalizedBounds: CGRect(x: 0.40, y: 0.80, width: 0.20, height: 0.04)),
        ScannedPageWord(text: "charlie", normalizedBounds: CGRect(x: 0.10, y: 0.40, width: 0.30, height: 0.04)),
    ]

    private func builder(words: [ScannedPageWord] = []) -> ScannedDocumentPDFBuilder {
        ScannedDocumentPDFBuilder(wordRecognizer: ScannedPageWordRecognizer { _ in words })
    }

    // MARK: Pages

    func testEveryImageBecomesAPageAtA4WidthWithTheImagesOwnProportions() async throws {
        let images = [try Self.blankImage(width: 1200, height: 1600), try Self.blankImage(width: 1600, height: 1000),
                      try Self.blankImage(width: 900, height: 900)]
        let scan = try await builder().build(pageImages: images)
        let document = try XCTUnwrap(PDFDocument(data: scan.data))
        XCTAssertEqual(scan.pageCount, 3)
        XCTAssertEqual(document.pageCount, 3)
        let expectedHeights: [CGFloat] = [595 * 1600 / 1200, 595 * 1000 / 1600, 595]
        for (pageIndex, expectedHeight) in expectedHeights.enumerated() {
            let bounds = try XCTUnwrap(document.page(at: pageIndex)).bounds(for: .mediaBox)
            XCTAssertEqual(bounds.width, 595, accuracy: 0.01, "page \(pageIndex)")
            XCTAssertEqual(bounds.height, expectedHeight, accuracy: 0.01, "page \(pageIndex)")
        }
    }

    func testAPictureWithTransparencyIsFlattenedAndStillBecomesAPage() async throws {
        let scan = try await builder().build(pageImages: [try Self.blankImage(width: 600, height: 800, hasAlpha: true)])
        XCTAssertEqual(PDFDocument(data: scan.data)?.pageCount, 1)
    }

    func testNoPagesIsRefused() async {
        do {
            _ = try await builder().build(pageImages: [])
            XCTFail("An empty scan has no PDF")
        } catch {
            XCTAssertEqual(error as? ScannedDocumentError, .noPages)
        }
    }

    func testAnExtremelyTallPictureKeepsAPageTheReadersCanOpen() throws {
        let size = try ScannedDocumentPDFBuilder.pageSize(for: Self.blankImage(width: 100, height: 100_000), pageIndex: 0)
        XCTAssertEqual(size.width, 595)
        XCTAssertEqual(size.height, ScannedDocumentPDFBuilder.maximumPageHeightPoints)
    }

    // MARK: Text layer

    func testRecognizedWordsAreSearchableAndSelectableWhereTheyWerePrinted() async throws {
        let scan = try await builder(words: Self.knownWords).build(pageImages: [try Self.blankImage(width: 1000, height: 1400)])
        let document = try XCTUnwrap(PDFDocument(data: scan.data))
        let text = try XCTUnwrap(document.string)
        for word in Self.knownWords { XCTAssertTrue(text.contains(word.text), "“\(text)” lacks \(word.text)") }
        XCTAssertEqual(scan.recognizedWordCount, 3)
        XCTAssertEqual(scan.pageIndicesWithoutRecognizedText, [])

        let page = try XCTUnwrap(document.page(at: 0))
        let pageBounds = page.bounds(for: .mediaBox)
        let found = try XCTUnwrap(document.findString("bravo", withOptions: []).first)
        let foundBounds = found.bounds(for: page)
        let printed = Self.knownWords[1].normalizedBounds
        let expectedCenter = CGPoint(x: printed.midX * pageBounds.width, y: printed.midY * pageBounds.height)
        XCTAssertEqual(foundBounds.midX, expectedCenter.x, accuracy: 6)
        XCTAssertEqual(foundBounds.midY, expectedCenter.y, accuracy: 6)
        XCTAssertEqual(foundBounds.width, printed.width * pageBounds.width, accuracy: 6)
    }

    func testTheTextLayerPaintsNothing() async throws {
        let image = try Self.blankImage(width: 600, height: 800)
        let withText = try await builder(words: Self.knownWords).build(pageImages: [image])
        let withoutText = try await builder().build(pageImages: [image])
        let bytesWithText = try Self.renderedPixels(of: withText.data)
        let bytesWithoutText = try Self.renderedPixels(of: withoutText.data)
        XCTAssertEqual(bytesWithText, bytesWithoutText)
    }

    func testAPageWhoseRecognitionFailedIsStillWrittenWithoutText() async throws {
        struct RecognitionFailure: Error {}
        let failingOnSecondPage = ScannedPageWordRecognizer.failing(onCallNumber: 2, error: RecognitionFailure(), words: Self.knownWords)
        let scan = try await ScannedDocumentPDFBuilder(wordRecognizer: failingOnSecondPage)
            .build(pageImages: [try Self.blankImage(width: 600, height: 800), try Self.blankImage(width: 600, height: 800)])
        let document = try XCTUnwrap(PDFDocument(data: scan.data))
        XCTAssertEqual(document.pageCount, 2)
        XCTAssertEqual(scan.pageIndicesWithoutRecognizedText, [1])
        XCTAssertTrue(try XCTUnwrap(document.page(at: 0)?.string).contains("alpha"))
        XCTAssertTrue((document.page(at: 1)?.string ?? "").isEmpty)
    }

    func testCancellingStopsTheScanWithoutAPDF() async throws {
        let cancelsItsOwnTask = ScannedPageWordRecognizer { _ in
            withUnsafeCurrentTask { currentTask in currentTask?.cancel() }
            return []
        }
        let images = [try Self.blankImage(width: 600, height: 800), try Self.blankImage(width: 600, height: 800)]
        do {
            _ = try await ScannedDocumentPDFBuilder(wordRecognizer: cancelsItsOwnTask).build(pageImages: images)
            XCTFail("A cancelled scan must not produce a PDF")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    // MARK: Size

    func testTenPagesOfAPhotographicScanStayAFewMegabytes() async throws {
        let pages = try (0..<10).map { pageIndex in try Self.photographicPage(seed: pageIndex) }
        let scan = try await builder(words: Self.knownWords).build(pageImages: pages)
        XCTAssertEqual(PDFDocument(data: scan.data)?.pageCount, 10)
        XCTAssertLessThan(scan.data.count, 5 * 1_024 * 1_024, "\(scan.data.count) bytes")
        // The pictures are the JPEG bytes themselves, not a re-encoded raster.
        XCTAssertNotNil(scan.data.range(of: Data("/DCTDecode".utf8)))
    }

    // MARK: On-device recognition

    func testOnDeviceRecognitionMakesARenderedPageSearchable() async throws {
        try await TextRecognitionCapability.requireOnDeviceTextRecognition()
        let page = try Self.renderedTextPage(lines: ["Invoice number 4821", "Total due 120 francs"])
        let scan = try await ScannedDocumentPDFBuilder(wordRecognizer: .onDevice).build(pageImages: [page])
        let document = try XCTUnwrap(PDFDocument(data: scan.data))
        XCTAssertEqual(scan.pageIndicesWithoutRecognizedText, [])
        for word in ["Invoice", "4821", "francs"] {
            XCTAssertFalse(document.findString(word, withOptions: [.caseInsensitive]).isEmpty, "“\(word)” is not found in “\(document.string ?? "")”")
        }
    }

    func testWordRangesKeepPunctuationWithItsWord() {
        let line = "  (alpha),  3.25 m "
        let words = ScannedPageWordRecognizer.wordRanges(in: line).map { range in String(line[range]) }
        XCTAssertEqual(words, ["(alpha),", "3.25", "m"])
    }

    // MARK: Images

    private static func blankImage(width: Int, height: Int, hasAlpha: Bool = false) throws -> CGImage {
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: alphaInfo.rawValue))
        context.setFillColor(CGColor(gray: 0.95, alpha: hasAlpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    /// An A4 page at 200 dpi with a smooth shaded background, some lines of text and a shape,
    /// like a photographed page; the shading and edges are what JPEG has to carry.
    private static func photographicPage(seed: Int) throws -> CGImage {
        let width = 1654, height = 2339
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: [CGColor(red: 0.98, green: 0.97, blue: 0.9, alpha: 1), CGColor(red: 0.8, green: 0.78, blue: 0.7, alpha: 1)] as CFArray,
                                                locations: [0, 1]))
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: CGPoint(x: CGFloat(width), y: 0), options: [])
        context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.5, alpha: 1))
        context.fillEllipse(in: CGRect(x: 300 + seed * 40, y: 400, width: 600, height: 400))
        drawLines(["Lecture \(seed + 1): signal chains", "The measurement is 3.25 meters", "Second line of the scanned page"], in: context, fontSize: 70)
        return try XCTUnwrap(context.makeImage())
    }

    private static func renderedTextPage(lines: [String]) throws -> CGImage {
        let width = 1240, height = 800
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        drawLines(lines, in: context, fontSize: 72)
        return try XCTUnwrap(context.makeImage())
    }

    private static func drawLines(_ lines: [String], in context: CGContext, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for (lineIndex, text) in lines.enumerated() {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 80, y: CGFloat(context.height) - 160 - CGFloat(lineIndex) * fontSize * 1.8)
            CTLineDraw(line, context)
        }
    }

    /// The first page drawn to pixels by PDFKit, to compare what a reader would show.
    private static func renderedPixels(of pdfData: Data) throws -> Data {
        let page = try XCTUnwrap(PDFDocument(data: pdfData)?.page(at: 0))
        let width = 300, height = 400
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.scaleBy(x: CGFloat(width) / page.bounds(for: .mediaBox).width, y: CGFloat(height) / page.bounds(for: .mediaBox).height)
        page.draw(with: .mediaBox, to: context)
        return try XCTUnwrap(context.data).withMemoryRebound(to: UInt8.self, capacity: width * height * 4) { pointer in
            Data(bytes: pointer, count: width * height * 4)
        }
    }
}

private extension ScannedPageWordRecognizer {
    /// Gives `words` on every call but the numbered one, which throws `error`.
    static func failing(onCallNumber failingCallNumber: Int, error: any Error, words: [ScannedPageWord]) -> ScannedPageWordRecognizer {
        let callCounter = CallCounter()
        return ScannedPageWordRecognizer { _ in
            if await callCounter.next() == failingCallNumber { throw error }
            return words
        }
    }
}

/// Counts the recognizer's calls.
private actor CallCounter {
    private var count = 0
    func next() -> Int { count += 1; return count }
}
