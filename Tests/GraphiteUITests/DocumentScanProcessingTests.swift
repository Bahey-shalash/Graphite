import XCTest
import CoreGraphics
import GraphiteApple
import GraphiteTestSupport
@testable import GraphiteUI

@MainActor
final class DocumentScanProcessingTests: XCTestCase {
    private func pageImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        return try XCTUnwrap(context.makeImage())
    }

    private let recognizerWithNoWords = ScannedPageWordRecognizer { _ in [] }

    func testAFinishedScanIsHandedToSaveOnceAndProcessingEnds() async throws {
        let processing = DocumentScanProcessing(wordRecognizer: recognizerWithNoWords)
        var savedPageCounts: [Int] = []
        var reportedMessages: [String] = []
        let task = processing.process(pageImages: [try pageImage(), try pageImage()],
                                      save: { scan, _ in savedPageCounts.append(scan.pageCount) },
                                      report: { error in reportedMessages.append(DocumentScanProcessing.message(for: error)) })
        XCTAssertTrue(processing.isProcessing)
        await task?.value
        XCTAssertEqual(savedPageCounts, [2])
        XCTAssertEqual(reportedMessages, [])
        XCTAssertFalse(processing.isProcessing)
    }

    func testAScanWithoutPagesIsReportedAndSavesNothing() async throws {
        let processing = DocumentScanProcessing(wordRecognizer: recognizerWithNoWords)
        var saveCount = 0
        var reportedErrors: [ScannedDocumentError] = []
        await processing.process(pageImages: [], save: { _, _ in saveCount += 1 },
                                 report: { error in reportedErrors.append(error as? ScannedDocumentError ?? .pdfWritingFailed) })?.value
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(reportedErrors, [.noPages])
        XCTAssertFalse(processing.isProcessing)
    }

    func testCancellingWhileTheTextIsRecognizedSavesNothing() async throws {
        let recognitionStarted = expectation(description: "recognition started")
        let (neverEndingStream, _) = AsyncStream<Void>.makeStream()
        // Waits until its task is cancelled, which ends iteration of a stream nothing writes to.
        let recognizerThatWaitsForCancellation = ScannedPageWordRecognizer { _ in
            recognitionStarted.fulfill()
            for await _ in neverEndingStream {}
            return []
        }
        let processing = DocumentScanProcessing(wordRecognizer: recognizerThatWaitsForCancellation)
        var saveCount = 0
        var reportCount = 0
        let task = processing.process(pageImages: [try pageImage()], save: { _, _ in saveCount += 1 }, report: { _ in reportCount += 1 })
        await fulfillment(of: [recognitionStarted], timeout: 20)

        processing.cancel()
        XCTAssertFalse(processing.isProcessing)
        await task?.value
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(reportCount, 0, "A cancelled scan is not an error")
    }

    func testAScanCanStartAgainAfterTheLastOneEnded() async throws {
        let processing = DocumentScanProcessing(wordRecognizer: recognizerWithNoWords)
        var saveCount = 0
        await processing.process(pageImages: [try pageImage()], save: { _, _ in saveCount += 1 }, report: { _ in })?.value
        await processing.process(pageImages: [try pageImage()], save: { _, _ in saveCount += 1 }, report: { _ in })?.value
        XCTAssertEqual(saveCount, 2)
    }

    func testEveryFailureHasWordsForThePerson() {
        XCTAssertFalse(DocumentScanProcessing.message(for: ScannedDocumentError.noPages).isEmpty)
        XCTAssertFalse(DocumentScanProcessing.message(for: ScannedDocumentError.pdfWritingFailed).isEmpty)
        XCTAssertFalse(DocumentScanProcessing.message(for: CocoaError(.fileWriteUnknown)).isEmpty)
    }
}
