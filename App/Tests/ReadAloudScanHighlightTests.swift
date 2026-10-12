#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
@testable import GraphiteUI

@MainActor
private final class ScanHighlightSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "scan-test", name: "Test", language: "en-US", quality: 3)]
    var requestIdentifier: UUID?
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { self.requestIdentifier = requestIdentifier }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

private struct ScanHighlightHost: View {
    let pdf: PDFSession
    let reader: ReadAloudController
    var body: some View {
        GraphitePDFView(session: pdf, input: .init(isEnabled: false, drawsWithFinger: false, showsToolPicker: false),
            readingHighlights: reader.highlights(in: pdf), followsReading: reader.shouldFollow(pdf))
    }
}

@MainActor
final class ReadAloudScanHighlightTests: XCTestCase {
    func testScannedWordIsVisibleAlignedThroughZoomAndClearedWithoutChangingPDF() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScanHighlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            for (lineIndex, text) in ["Repeat first.", "Repeat second."].enumerated() {
                (text as NSString).draw(at: CGPoint(x: 60, y: 70 + CGFloat(lineIndex) * 50),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.black])
            }
        }
        let document = PDFDocument()
        document.insert(try XCTUnwrap(PDFPage(image: image)), at: 0)
        let location = directory.appendingPathComponent("Scan.pdf")
        let originalBytes = try XCTUnwrap(document.dataRepresentation())
        try originalBytes.write(to: location)
        let pdf = try await PDFSession.open(location)
        let speech = ScanHighlightSpeech()
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ScanHighlight-\(UUID().uuidString)"))
        let reader = ReadAloudController(session: ReadAloudSession(speech: speech, preferences: preferences), preferences: preferences)
        reader.session.chooseVoice("scan-test")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let hosting = UIHostingController(rootView: ScanHighlightHost(pdf: pdf, reader: reader))
        window.rootViewController = hosting
        window.makeKeyAndVisible()
        defer { reader.clear(); window.isHidden = true; window.rootViewController = nil }
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 0)
        try await waitUntil { !reader.isPreparing && pdf.pdfView != nil }
        XCTAssertNil(reader.errorMessage)
        let recognition = try XCTUnwrap(reader.recognizedPDFPage?.recognition)
        let page = try XCTUnwrap(pdf.document.page(at: 0))
        let pdfView = try XCTUnwrap(pdf.pdfView)
        try await Task.sleep(for: .milliseconds(300))
        reader.session.play()
        speech.eventHandler?(.spoken(try XCTUnwrap(speech.requestIdentifier), NSRange(location: 0, length: 6)))
        try await waitUntil { self.descendants(pdfView).contains { $0 is PDFRecognizedReadingOverlay } }
        let overlay = try XCTUnwrap(descendants(pdfView).compactMap { $0 as? PDFRecognizedReadingOverlay }.first)
        let wordView = try XCTUnwrap(overlay.subviews.first)
        let pageBounds = try XCTUnwrap(recognition.words.first?.pageBounds)
        var actualBounds = wordView.convert(wordView.bounds, to: pdfView)
        var expectedBounds = pdfView.convert(pageBounds, from: page)
        XCTAssertEqual(actualBounds.minX, expectedBounds.minX, accuracy: 1)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 1)
        XCTAssertFalse(overlay.isUserInteractionEnabled)
        let center = wordView.convert(CGPoint(x: wordView.bounds.midX, y: wordView.bounds.midY), to: window)
        XCTAssertFalse(window.hitTest(center, with: nil) === wordView)
        try await Task.sleep(for: .milliseconds(200))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let screenshot = UIGraphicsImageRenderer(bounds: hosting.view.bounds, format: format).image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "Recognized word on scanned PDF"
        attachment.lifetime = .keepAlways
        add(attachment)
        let counts = try pixelCounts(screenshot)
        XCTAssertGreaterThan(counts.dark, 100, "The screenshot must contain the scanned text, not only its highlight.")
        XCTAssertGreaterThan(counts.highlight, 100, "The temporary highlight must be visible over the scan.")
        pdfView.scaleFactor *= 1.3
        pdfView.layoutDocumentView()
        try await Task.sleep(for: .milliseconds(200))
        actualBounds = wordView.convert(wordView.bounds, to: pdfView)
        expectedBounds = pdfView.convert(pageBounds, from: page)
        XCTAssertEqual(actualBounds.width, expectedBounds.width, accuracy: 1)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 1)
        reader.applyRecognizedPDFReview([0: "Repeat slowly"], words: 2...2,
            pageIdentifier: try XCTUnwrap(reader.recognizedPageIdentifier))
        try await waitUntil { !reader.isPreparing }
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.currentPassage?.text, "Repeat")
        reader.session.play()
        speech.eventHandler?(.spoken(try XCTUnwrap(speech.requestIdentifier), NSRange(location: 0, length: 6)))
        try await waitUntil { self.descendants(pdfView).contains { $0 is PDFRecognizedReadingOverlay } }
        let selectedOverlay = try XCTUnwrap(descendants(pdfView).compactMap { $0 as? PDFRecognizedReadingOverlay }.first)
        let selectedWord = try XCTUnwrap(selectedOverlay.subviews.first)
        let selectedBounds = selectedWord.convert(selectedWord.bounds, to: pdfView)
        let secondWordBounds = pdfView.convert(recognition.words[2].pageBounds, from: page)
        XCTAssertEqual(selectedBounds.minX, secondWordBounds.minX, accuracy: 1)
        XCTAssertEqual(selectedBounds.minY, secondWordBounds.minY, accuracy: 1)
        let rangeScreenshot = UIGraphicsImageRenderer(bounds: hosting.view.bounds, format: format).image { _ in
            hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
        }
        let rangeAttachment = XCTAttachment(image: rangeScreenshot)
        rangeAttachment.name = "Chosen second occurrence on scanned PDF"
        rangeAttachment.lifetime = .keepAlways
        add(rangeAttachment)
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requestIdentifier)))
        XCTAssertEqual(reader.session.state, .finished)
        XCTAssertEqual(reader.sourcePageIndex, 0)
        reader.stop()
        try await waitUntil { !self.descendants(pdfView).contains { $0 is PDFRecognizedReadingOverlay } }
        XCTAssertTrue(page.annotations.isEmpty)
        XCTAssertFalse(pdf.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { child in [child] + descendants(child) }
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(predicate(), "The hosted reader did not reach the expected state.")
    }

    private func pixelCounts(_ image: UIImage) throws -> (dark: Int, highlight: Int) {
        let image = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var darkCount = 0
        var highlightCount = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let red = Int(bytes[offset]), green = Int(bytes[offset + 1]), blue = Int(bytes[offset + 2])
            if red < 80, green < 80, blue < 80 { darkCount += 1 }
            // The reading highlight's light blue over the white scan.
            if blue > 205, blue > red + 30, blue > green + 10 { highlightCount += 1 }
        }
        return (darkCount, highlightCount)
    }
}
#endif
