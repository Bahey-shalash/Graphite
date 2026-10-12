import XCTest
import CoreGraphics
import CoreText
import PDFKit
import GraphiteCore
@testable import GraphiteApple

final class PDFReadAloudScanTests: XCTestCase {
    private static let lines = ["Repeat this word: alpha.", "Repeat this word: beta.", "The measurement is 3.25 meters."]

    func testImageOnlyPDFProducesRecognizedWordsWithPageCoordinates() async throws {
        let bytes = try Self.fixture()
        let nativePage = try XCTUnwrap(PDFDocument(data: bytes)?.page(at: 0))
        XCTAssertTrue((nativePage.string ?? "").isEmpty)
        let snapshot = try await PDFReadAloudExtraction().page(in: bytes, readingOrder: .layout)
        XCTAssertEqual(snapshot.text, Self.lines.joined(separator: "\n"))
        XCTAssertTrue(snapshot.segments.isEmpty)
        XCTAssertEqual(snapshot.originalText, "")
        let recognition = try XCTUnwrap(snapshot.recognition)
        XCTAssertEqual(recognition.geometry.mediaBounds, nativePage.bounds(for: .mediaBox))
        XCTAssertEqual(recognition.geometry.cropBounds, nativePage.bounds(for: .cropBox))
        XCTAssertTrue(snapshot.layoutNotice?.contains("pauses for review") == true)
        let source = snapshot.text as NSString
        XCTAssertEqual(recognition.words.map { source.substring(with: $0.textRange) }, Self.lines.joined(separator: " ").components(separatedBy: " "))
        let repeats = recognition.words.filter { source.substring(with: $0.textRange) == "Repeat" }
        XCTAssertEqual(repeats.count, 2)
        XCTAssertNotEqual(repeats.first?.pageBounds, repeats.last?.pageBounds)
        let first = try XCTUnwrap(repeats.first?.pageBounds)
        XCTAssertEqual(first.minX, 60, accuracy: 3)
        let fontDescent = CTFontGetDescent(CTFontCreateWithName("Helvetica" as CFString, 20, nil))
        XCTAssertEqual(first.minY, 710 - fontDescent, accuracy: 4)
        XCTAssertGreaterThan(first.width, 50)
        XCTAssertLessThan(first.width, 80)
        for word in recognition.words {
            XCTAssertTrue(recognition.geometry.cropBounds.contains(word.pageBounds))
            XCTAssertTrue((0...1).contains(word.confidence))
        }
        XCTAssertEqual(try snapshot.selectedRange(startOffset: nil, endOffset: nil), NSRange(location: 0, length: source.length))
        XCTAssertThrowsError(try snapshot.selectedRange(startOffset: 0, endOffset: nil))
    }

    func testBaselineTextRecognizerHasTheSameWordsAndCoordinateContract() async throws {
        let snapshot = try await PDFReadAloudExtraction().page(in: Self.fixture(), readingOrder: .file)
        XCTAssertFalse(snapshot.usesLayout)
        XCTAssertEqual(snapshot.text, Self.lines.joined(separator: "\n"))
        XCTAssertFalse(try XCTUnwrap(snapshot.recognition).words.isEmpty)
        XCTAssertTrue(snapshot.layoutNotice?.contains("line order") == true)
    }

    func testCropAndEveryQuarterTurnKeepRecognitionInOriginalPageCoordinates() async throws {
        let extraction = PDFReadAloudExtraction()
        for rotation in [0, 90, 180, 270] {
            let snapshot = try await extraction.page(in: Self.fixture(rotation: rotation, isCropped: true), readingOrder: .layout)
            XCTAssertEqual(snapshot.text, Self.lines.joined(separator: "\n"), "Rotation \(rotation)")
            let recognition = try XCTUnwrap(snapshot.recognition)
            XCTAssertEqual(recognition.geometry.rotation, rotation)
            let first = try XCTUnwrap(recognition.words.first?.pageBounds)
            XCTAssertEqual(first.minX, 60, accuracy: 3, "Rotation \(rotation)")
            let fontDescent = CTFontGetDescent(CTFontCreateWithName("Helvetica" as CFString, 20, nil))
            XCTAssertEqual(first.minY, 710 - fontDescent, accuracy: 4, "Rotation \(rotation)")
        }
    }

    func testCorrectionsKeepTheOriginalWordRegionAndRebuildLaterOffsets() async throws {
        let snapshot = try await PDFReadAloudExtraction().page(in: Self.fixture(), readingOrder: .layout)
        let corrected = try snapshot.correctingRecognizedWords([0: "Repeat slowly", 7: "gamma."])
        XCTAssertEqual(corrected.text, "Repeat slowly this word: alpha.\nRepeat this word: gamma.\nThe measurement is 3.25 meters.")
        let originalWords = try XCTUnwrap(snapshot.recognition?.words)
        let correctedWords = try XCTUnwrap(corrected.recognition?.words)
        XCTAssertEqual(originalWords.map(\.pageBounds), correctedWords.map(\.pageBounds))
        XCTAssertEqual(correctedWords.count, originalWords.count)
        XCTAssertTrue(correctedWords[0].isCorrected)
        XCTAssertTrue(correctedWords[7].isCorrected)
        XCTAssertFalse(correctedWords[1].isCorrected)
        XCTAssertEqual((corrected.text as NSString).substring(with: correctedWords[0].textRange), "Repeat slowly")
        XCTAssertEqual((corrected.text as NSString).substring(with: correctedWords[7].textRange), "gamma.")
        XCTAssertEqual(corrected.originalText, snapshot.originalText)
        XCTAssertEqual((corrected.text as NSString).substring(with: try corrected.recognizedTextRange(words: 4...7)), "Repeat this word: gamma.")
        XCTAssertEqual((corrected.text as NSString).substring(with: try corrected.recognizedTextRange(words: 0...0)), "Repeat slowly")
        XCTAssertThrowsError(try corrected.recognizedTextRange(words: -1...0))
        XCTAssertThrowsError(try corrected.recognizedTextRange(words: 0...correctedWords.count))
        for replacement in ["", "two\nlines", String(repeating: "x", count: 257)] {
            XCTAssertThrowsError(try snapshot.correctingRecognizedWords([0: replacement]))
        }
        XCTAssertThrowsError(try snapshot.correctingRecognizedWords([-1: "invalid"]))
        XCTAssertThrowsError(try snapshot.correctingRecognizedWords([correctedWords.count: "invalid"]))
    }

    private static func fixture(rotation: Int = 0, isCropped: Bool = false) throws -> Data {
        let bitmap = try XCTUnwrap(CGContext(data: nil, width: 1_200, height: 1_600, bitsPerComponent: 8, bytesPerRow: 4_800,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_600))
        bitmap.scaleBy(x: 2, y: 2)
        for (lineIndex, text) in lines.enumerated() {
            let font = CTFontCreateWithName("Helvetica" as CFString, 20, nil)
            let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            bitmap.textPosition = CGPoint(x: 60, y: 710 - CGFloat(lineIndex) * 50)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), bitmap)
        }
        let image = try XCTUnwrap(bitmap.makeImage())
        let bytes = NSMutableData()
        var mediaBounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: bytes)), mediaBox: &mediaBounds, nil))
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBounds)
        context.endPDFPage()
        context.closePDF()
        let document = try XCTUnwrap(PDFDocument(data: bytes as Data))
        let page = try XCTUnwrap(document.page(at: 0))
        page.rotation = rotation
        if isCropped { page.setBounds(CGRect(x: 40, y: 50, width: 520, height: 720), for: .cropBox) }
        return try XCTUnwrap(document.dataRepresentation())
    }
}
