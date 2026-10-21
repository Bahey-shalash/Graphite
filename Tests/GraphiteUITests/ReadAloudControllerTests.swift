import XCTest
import AppKit
import PDFKit
import SwiftUI
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
private final class ControllerTestSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test", name: "Test", language: "en-US", quality: 3)]
    var requests: [(text: String, identifier: UUID)] = []
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { requests.append((text, requestIdentifier)) }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

@MainActor
final class ReadAloudControllerTests: XCTestCase {
    private func makeReader(playsWhenPrepared: Bool = false) throws -> (ReadAloudController, ControllerTestSpeech) {
        let speech = ControllerTestSpeech()
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudControllerTests", for: self).preferences
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        let reader = ReadAloudController(session: session, preferences: preferences, playsWhenPrepared: playsWhenPrepared)
        reader.choosePDFReadingOrder(.file)
        return (reader, speech)
    }

    private func waitForPreparation(_ reader: ReadAloudController, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while reader.isPreparing, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertFalse(reader.isPreparing, "Reader preparation did not finish.")
    }

    private func makePDF(in directory: URL, pageTexts: [String]) throws -> URL {
        let location = directory.appendingPathComponent("Paper.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for text in pageTexts {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)])
                .draw(at: CGPoint(x: 40, y: 500))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    private func makeScannedPage() throws -> PDFPage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1_200, height: 1_600, bitsPerComponent: 8, bytesPerRow: 4_800,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_600))
        context.scaleBy(x: 2, y: 2)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (lineIndex, text) in ["Repeat first.", "Repeat second."].enumerated() {
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 20)])
                .draw(at: CGPoint(x: 60, y: 710 - CGFloat(lineIndex) * 50))
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: CGSize(width: 600, height: 800))
        return try XCTUnwrap(PDFPage(image: image))
    }

    func testOutlineReadingPagesIncludeBoundaryPagesAndSubsections() {
        let entries = [
            PDFOutlineEntry(path: [0], label: "Introduction", pageIndex: 0, hasChildren: true),
            PDFOutlineEntry(path: [0, 0], label: "Background", pageIndex: 1, hasChildren: false),
            PDFOutlineEntry(path: [1], label: "Methods", pageIndex: 3, hasChildren: false),
            PDFOutlineEntry(path: [2], label: "Results", pageIndex: 3, hasChildren: false),
            PDFOutlineEntry(path: [3], label: "Page 5", pageIndex: 4, hasChildren: false),
            PDFOutlineEntry(path: [4], label: "Conclusion", pageIndex: 5, hasChildren: false)
        ]
        XCTAssertEqual(entries[0].readingPages(in: entries, pageCount: 7), 0...3)
        XCTAssertEqual(entries[1].readingPages(in: entries, pageCount: 7), 1...3)
        XCTAssertEqual(entries[2].readingPages(in: entries, pageCount: 7), 3...3)
        XCTAssertEqual(entries[3].readingPages(in: entries, pageCount: 7), 3...5)
        XCTAssertNil(entries[4].readingPages(in: entries, pageCount: 7))
        XCTAssertEqual(entries[5].readingPages(in: entries, pageCount: 7), 5...6)
        XCTAssertNil(entries[5].readingPages(in: entries, pageCount: 5))
        XCTAssertNil(entries[2].readingPages(in: Array(entries.reversed()), pageCount: 7))
        XCTAssertNil(entries[0].readingPages(in: [], pageCount: 7))
    }

    func testRecognizedWordRangeKeepsSecondOccurrenceAndStopsBeforeNextPage() async throws {
        try await TextRecognitionCapability.requireOnDeviceTextRecognition()
        let directory = try TemporaryVault.make(prefix: "ReadAloudScanRange", for: self).root
        let location = try makePDF(in: directory, pageTexts: ["Next page."])
        let document = try XCTUnwrap(PDFDocument(url: location))
        document.insert(try makeScannedPage(), at: 0)
        XCTAssertTrue(document.write(to: location))
        let originalBytes = try Data(contentsOf: location)
        let pdf = try await PDFSession.open(location)
        let (reader, speech) = try makeReader()
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        try await waitForPreparation(reader, timeout: .seconds(30))
        let snapshot = try XCTUnwrap(reader.recognizedPDFPage)
        let identifier = try XCTUnwrap(reader.recognizedPageIdentifier)
        reader.applyRecognizedPDFReview([0: "Repeat slowly", 3: "corrected ending."], words: 2...3, pageIdentifier: identifier)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.recognizedWordRange, 2...3)
        XCTAssertEqual(reader.session.currentPassage?.text, "Repeat corrected ending.")
        XCTAssertTrue(speech.requests.isEmpty, "Choosing a passage must wait for Play.")
        reader.session.play()
        let requestIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(requestIdentifier, NSRange(location: 0, length: 6)))
        let secondBounds = try XCTUnwrap(snapshot.recognition?.words[2].pageBounds)
        XCTAssertEqual(reader.highlights(in: pdf).first?.pageBounds(in: pdf.document), secondBounds)
        reader.applyRecognizedPDFReview([2: "Stale"], words: 0...1, pageIdentifier: identifier)
        XCTAssertEqual(reader.session.currentPassage?.text, "Repeat corrected ending.")
        speech.eventHandler?(.finished(requestIdentifier))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(reader.sourcePageIndex, 0)
        XCTAssertEqual(speech.requests.count, 1)
        XCTAssertEqual(reader.session.state, .finished)
        let currentIdentifier = try XCTUnwrap(reader.recognizedPageIdentifier)
        reader.correctRecognizedPDFWords([2: "Again"], pageIdentifier: currentIdentifier)
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.recognizedWordRange, 2...3)
        XCTAssertEqual(reader.session.currentPassage?.text, "Again corrected ending.")
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
        XCTAssertFalse(pdf.hasUnsavedChanges)
        reader.clear()
        XCTAssertNil(reader.recognizedWordRange)
    }

    func testMixedPDFPausesForScanReviewCorrectionsKeepWordGeometryAndSourceFile() async throws {
        try await TextRecognitionCapability.requireOnDeviceTextRecognition()
        let directory = try TemporaryVault.make(prefix: "ReadAloudScannedPDF", for: self).root
        let location = try makePDF(in: directory, pageTexts: ["Opening page.", "Closing page."])
        let document = try XCTUnwrap(PDFDocument(url: location))
        document.insert(try makeScannedPage(), at: 1)
        XCTAssertTrue(document.write(to: location))
        let originalBytes = try Data(contentsOf: location)
        let pdf = try await PDFSession.open(location)
        let (reader, speech) = try makeReader()
        reader.choosePDFReadingOrder(.layout)
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 2)
        try await waitForPreparation(reader, timeout: .seconds(30))
        reader.session.play()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        try await waitForPreparation(reader, timeout: .seconds(30))
        XCTAssertEqual(reader.sourcePageIndex, 1)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(speech.requests.count, 1, "A newly recognized page must wait for review and Play.")
        let snapshot = try XCTUnwrap(reader.recognizedPDFPage)
        let identifier = try XCTUnwrap(reader.recognizedPageIdentifier)
        XCTAssertEqual(snapshot.text, "Repeat first.\nRepeat second.")
        reader.session.play()
        let scanRequest = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(scanRequest, NSRange(location: 0, length: 6)))
        let originalBounds = try XCTUnwrap(reader.highlights(in: pdf).first?.pageBounds(in: pdf.document))
        reader.correctRecognizedPDFWords([0: "Repeat slowly"], pageIdentifier: identifier)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.currentPassage?.text, "Repeat slowly first. Repeat second.")
        XCTAssertEqual(speech.requests.count, 2)
        speech.eventHandler?(.spoken(scanRequest, NSRange(location: 0, length: 6)))
        XCTAssertTrue(reader.highlights(in: pdf).isEmpty)
        reader.session.play()
        let correctedRequest = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(correctedRequest, NSRange(location: 7, length: 6)))
        XCTAssertEqual(reader.highlights(in: pdf).first?.pageBounds(in: pdf.document), originalBounds)
        reader.correctRecognizedPDFWords([0: "Stale edit"], pageIdentifier: identifier)
        XCTAssertEqual(reader.session.currentPassage?.text, "Repeat slowly first. Repeat second.")
        speech.eventHandler?(.finished(correctedRequest))
        try await waitForPreparation(reader, timeout: .seconds(30))
        XCTAssertEqual(reader.sourcePageIndex, 2)
        XCTAssertNil(reader.recognizedPDFPage)
        XCTAssertEqual(speech.requests.last?.text, "Closing page.")
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
        XCTAssertFalse(pdf.hasUnsavedChanges)
        XCTAssertTrue((pdf.document.page(at: 1)?.annotations ?? []).isEmpty)
        reader.clear()
    }

    func testRecognizedWordOverlayFollowsNativeZoomAndClearsWithoutAnnotations() async throws {
        try await TextRecognitionCapability.requireOnDeviceTextRecognition()
        let document = PDFDocument()
        let page = try makeScannedPage()
        document.insert(page, at: 0)
        let originalBytes = try XCTUnwrap(document.dataRepresentation())
        let snapshot = try await PDFReadAloudExtraction().page(in: originalBytes, readingOrder: .layout)
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
        view.document = document
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.showInvisibly()
        defer { window.orderOut(nil); window.contentView = nil }
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let recognition = try XCTUnwrap(snapshot.recognition)
        let geometry = recognition.geometry
        let bounds = try XCTUnwrap(recognition.words.first?.pageBounds)
        let highlight = PDFReadAloudHighlight(pageIndex: 0, location: .pageArea(bounds, geometry), expectedText: "Repeat")
        let highlighter = PDFReadAloudHighlighter()
        let beforePixels = try readingOverlayBitmap(view)
        highlighter.update([highlight], in: view)
        let overlay = try XCTUnwrap(view.documentView?.subviews.compactMap { $0 as? PDFRecognizedReadingOverlay }.first)
        let wordView = try XCTUnwrap(overlay.subviews.first)
        var actualBounds = wordView.convert(wordView.bounds, to: view)
        var expectedBounds = view.convert(bounds, from: page)
        XCTAssertEqual(actualBounds.minX, expectedBounds.minX, accuracy: 0.5)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 0.5)
        XCTAssertGreaterThan(wordView.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertNil(overlay.hitTest(overlay.convert(wordView.frame.origin, from: wordView.superview)))
        window.displayIfNeeded()
        let highlightedPixels = try readingOverlayBitmap(view)
        XCTAssertGreaterThan(highlightPixelCount(highlightedPixels), highlightPixelCount(beforePixels) + 50)
        if let artifactDirectory = ProcessInfo.processInfo.environment["GRAPHITE_READ_ALOUD_ARTIFACT_DIRECTORY"] {
            let directory = URL(fileURLWithPath: artifactDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try originalBytes.write(to: directory.appendingPathComponent("scanned-page.pdf"))
            try XCTUnwrap(beforePixels.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("scanned-page-before-highlight.png"))
            try XCTUnwrap(highlightedPixels.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("scanned-word-highlight.png"))
        }
        view.scaleFactor *= 1.5
        view.layoutDocumentView()
        highlighter.refreshGeometry(in: view)
        actualBounds = wordView.convert(wordView.bounds, to: view)
        expectedBounds = view.convert(bounds, from: page)
        XCTAssertEqual(actualBounds.width, expectedBounds.width, accuracy: 0.5)
        XCTAssertEqual(actualBounds.minY, expectedBounds.minY, accuracy: 0.5)
        highlighter.clear(in: view)
        XCTAssertNil(overlay.superview)
        XCTAssertTrue(page.annotations.isEmpty)
        XCTAssertNil(view.currentSelection)
        XCTAssertTrue(view.highlightedSelections?.isEmpty ?? true)
    }

    private func readingOverlayBitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
            pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    private func highlightPixelCount(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for verticalPixel in 0..<bitmap.pixelsHigh {
            for horizontalPixel in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: horizontalPixel, y: verticalPixel)?.usingColorSpace(.deviceRGB) else { continue }
                // The reading highlight's light blue over the white page.
                if color.blueComponent > 0.8, color.blueComponent > color.redComponent + 0.12,
                   color.blueComponent > color.greenComponent + 0.04 { count += 1 }
            }
        }
        return count
    }

    /// PDFKit extracts a re-saved page's text a little differently (here: a figure label moved);
    /// the words that did not change must still find their exact place on the live page.
    /// Before, any difference switched off every highlight on the page.
    func testHighlightsSurviveSmallDifferencesBetweenExportedAndLivePageText() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudAlign", for: self).root
        let location = try makePDF(in: directory, pageTexts: ["Static logic keeps its output level."])
        let pageBytes = try XCTUnwrap(PDFDocument(url: location)?.dataRepresentation())
        let snapshot = try await PDFReadAloudExtraction().page(in: pageBytes, readingOrder: .file)
        let liveText = "(a) " + snapshot.originalText
        let source = try XCTUnwrap(PDFReadAloudSource.page(snapshot, pageIndex: 0, livePageText: liveText))
        let word = (snapshot.text as NSString).range(of: "output")
        let highlight = try XCTUnwrap(source.highlights(for: word).first)
        XCTAssertEqual((liveText as NSString).substring(with: try XCTUnwrap(highlight.characterRange)), "output")
        XCTAssertNil(PDFReadAloudSource.page(snapshot, pageIndex: 0, livePageText: "Something else entirely, nothing alike."),
                     "A page that hardly matches is not trusted.")
    }

    /// Expanding a folded callout while the note is read brings its body into what is still to
    /// be read, and reading carries on from where it was.
    func testUnfoldingWhileReadingAddsTheUnfoldedPassage() async throws {
        let (reader, speech) = try makeReader()
        let path = try VaultPath("Folds.md")
        let note = "Opening line.\n\n> [!note]- Hidden derivation\n> The long hidden proof.\n\nClosing line."
        let collapsed = ReadAloudFolding.hiddenRanges(in: note, foldedKeys: [], calloutExpansion: [:])
        reader.readMarkdown(note, path: path, hiddenRanges: collapsed)
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.session.document?.passages.map(\.text), ["Opening line.", "Hidden derivation", "Closing line."])
        reader.session.play()
        XCTAssertEqual(speech.requests.last?.text, "Opening line.")
        let expanded = ReadAloudFolding.hiddenRanges(in: note, foldedKeys: [],
                                                     calloutExpansion: [ReadAloudFolding.calloutKey(type: "note", title: "Hidden derivation"): true])
        reader.foldsDidChange(in: path, hiddenRanges: expanded)
        let deadline = ContinuousClock.now + .seconds(5)
        while reader.session.document?.passages.count != 4, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(reader.session.document?.passages.map(\.text), ["Opening line.", "Hidden derivation", "The long hidden proof.", "Closing line."])
        XCTAssertEqual(reader.session.passageIndex, 0, "Reading carries on from the same place.")
        XCTAssertEqual(reader.session.state, .speaking)
    }

    /// BUG-VOICE-09: Folding while a passage is read keeps the word reached: reading goes on from it, not from
    /// the passage's first word.
    func testUnfoldingWhileReadingGoesOnFromTheWordReached() async throws {
        let (reader, speech) = try makeReader()
        let path = try VaultPath("Folds.md")
        let opening = "Opening line has several words."
        let note = opening + "\n\n> [!note]- Hidden derivation\n> The long hidden proof.\n\nClosing line."
        reader.readMarkdown(note, path: path, hiddenRanges: ReadAloudFolding.hiddenRanges(in: note, foldedKeys: [], calloutExpansion: [:]))
        try await waitForPreparation(reader)
        reader.session.play()
        let request = try XCTUnwrap(speech.requests.last)
        XCTAssertEqual(request.text, opening)
        let wordReached = (opening as NSString).range(of: "several")
        speech.eventHandler?(.spoken(request.identifier, wordReached))
        XCTAssertEqual(reader.session.currentOffset, wordReached.location)
        let expanded = ReadAloudFolding.hiddenRanges(in: note, foldedKeys: [],
                                                     calloutExpansion: [ReadAloudFolding.calloutKey(type: "note", title: "Hidden derivation"): true])

        reader.foldsDidChange(in: path, hiddenRanges: expanded)
        try await waitUntil("the note is prepared again with the unfolded callout", timeoutSeconds: 10) {
            reader.session.document?.passages.count == 4
        }

        XCTAssertEqual(reader.session.passageIndex, 0)
        XCTAssertEqual(reader.session.state, .speaking)
        XCTAssertEqual(speech.requests.last?.text, "several words.", "Reading goes on from the word reached, not from the passage's first word.")
        XCTAssertEqual(reader.session.currentOffset, wordReached.location)
    }

    /// In the app, choosing Read Document starts reading as soon as the passage is ready and
    /// keeps the page in view; rebuilding it for another math style waits for Play.
    func testAppReadingStartsWhenPreparedWithoutCoveringThePage() async throws {
        let (reader, speech) = try makeReader(playsWhenPrepared: true)
        let path = try VaultPath("Started.md")
        reader.readMarkdown("## Start\n\nRead $x^2$ now.", path: path)
        XCTAssertTrue(reader.isActive)
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.session.state, .speaking)
        XCTAssertEqual(speech.requests.map(\.text), ["Start"])
        XCTAssertFalse(reader.showsReader, "The options sheet must not cover the page being read.")
        reader.chooseMathematicalStyle(.detailed)
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.session.state, .idle)
        XCTAssertEqual(speech.requests.count, 1)
        reader.readMarkdown("", path: path)
        try await waitForPreparation(reader)
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertTrue(reader.showsReader, "A passage that cannot be read says why.")
        XCTAssertTrue(reader.isActive)
        reader.clear()
        XCTAssertFalse(reader.isActive)
    }

    func testMarkdownPreparationIsReviewableAndLatestRequestWins() async throws {
        let (reader, speech) = try makeReader()
        reader.readMarkdown(String(repeating: "Old words. ", count: 10_000), path: try VaultPath("Old.md"))
        reader.readMarkdown("## New\n\nOnly this.", path: try VaultPath("New.md"))
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.title, "New")
        XCTAssertEqual(reader.session.document?.passages.map(\.text), ["New", "Only this."])
        XCTAssertEqual(reader.session.state, .idle)
        XCTAssertTrue(speech.requests.isEmpty, "Preparation must wait for the user's Play action.")
        reader.clear()
    }

    func testMathStyleRebuildsTheChosenRangeAndRejectsOldSpeechEvents() async throws {
        let (reader, speech) = try makeReader()
        let path = try VaultPath("Mathematics.md")
        let source = #"Before. Read $\frac{a+b}{c}$ now. After."#
        let range = (source as NSString).range(of: #"Read $\frac{a+b}{c}$ now."#)
        reader.readMarkdown(source, path: path, range: range, scope: "Selected passage")
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.session.currentPassage?.text, "Read the fraction with numerator a plus b and denominator c now.")
        reader.session.play()
        let oldIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        reader.chooseMathematicalStyle(.detailed)
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.scopeDescription, "Selected passage")
        XCTAssertEqual(reader.session.currentPassage?.text, "Read StartFraction a plus b Over c EndFraction now.")
        XCTAssertEqual(reader.session.state, .idle)
        speech.eventHandler?(.spoken(oldIdentifier, NSRange(location: 0, length: 4)))
        XCTAssertNil(reader.highlight(in: path))
        reader.session.play()
        let currentIdentifier = try XCTUnwrap(speech.requests.last?.identifier)
        let fractionRange = try XCTUnwrap(reader.session.currentPassage).text as NSString
        speech.eventHandler?(.spoken(currentIdentifier, fractionRange.range(of: "StartFraction")))
        XCTAssertEqual(reader.highlight(in: path), (source as NSString).range(of: #"$\frac{a+b}{c}$"#))
        reader.documentDidChange(path.rawValue)
        reader.chooseMathematicalStyle(.concise)
        XCTAssertNil(reader.session.document, "Changing detail must not revive an invalidated source snapshot.")
        XCTAssertNotNil(reader.errorMessage)
    }

    func testMathPreferenceIsRememberedAndVoiceSampleUsesProductionPreparation() async throws {
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudMathPreference", for: self).preferences
        let reader = ReadAloudController(session: ReadAloudSession(speech: ControllerTestSpeech(), preferences: preferences), preferences: preferences)
        reader.chooseMathematicalStyle(.detailed)
        let sample = try await reader.prepareVoiceSample()
        XCTAssertTrue(sample.passages.map(\.text).joined(separator: " ").contains("StartFraction a plus b Over c EndFraction"))
        XCTAssertNil(reader.session.document, "A preview must not replace the chosen document.")
        let reopened = ReadAloudController(session: ReadAloudSession(speech: ControllerTestSpeech(), preferences: preferences), preferences: preferences)
        XCTAssertEqual(reopened.mathematicalStyle, .detailed)
        reopened.chooseMathematicalStyle(.concise)
        let concise = try await reopened.prepareVoiceSample()
        XCTAssertTrue(concise.passages.map(\.text).joined(separator: " ").contains("the fraction with numerator a plus b and denominator c"))
    }

    func testDocumentEditCancelsReadingAndClearsSourceHighlights() async throws {
        let (reader, speech) = try makeReader()
        let path = try VaultPath("Note.md")
        reader.readMarkdown("## Read this.", path: path)
        try await waitForPreparation(reader)
        reader.session.play()
        let identifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(identifier, NSRange(location: 0, length: 4)))
        XCTAssertEqual(reader.highlight(in: path), NSRange(location: 3, length: 4))
        reader.documentDidChange(path.rawValue)
        speech.eventHandler?(.finished(identifier))
        XCTAssertNil(reader.highlight(in: path))
        XCTAssertNil(reader.session.document)
        XCTAssertNotNil(reader.errorMessage)
    }

    func testPDFRangeAdvancesLazilyStopsAtEndpointAndPreservesOriginalBytes() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudPDF", for: self).root
        let location = try makePDF(in: directory, pageTexts: ["First page.", "Second page.", "Third page."])
        let originalBytes = try Data(contentsOf: location)
        let pdf = try await PDFSession.open(location)
        let (reader, speech) = try makeReader()
        reader.readPDF(pdf, firstPageIndex: 1, lastPageIndex: 2)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.sourcePageIndex, 1)
        XCTAssertEqual(reader.session.currentPassage?.text, "Second page.")
        XCTAssertTrue(speech.requests.isEmpty)
        reader.session.play()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        try await waitForPreparation(reader)
        XCTAssertEqual(reader.sourcePageIndex, 2)
        XCTAssertEqual(speech.requests.map(\.text), ["Second page.", "Third page."])
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        XCTAssertEqual(reader.session.state, .finished)
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
        XCTAssertFalse(pdf.hasUnsavedChanges)
        reader.clear()
    }

    func testBlankPDFPageStopsWithExplanationInsteadOfSilentlySkipping() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudBlankPDF", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["", "Later."]))
        let (reader, speech) = try makeReader()
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        try await waitForPreparation(reader)
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertTrue(speech.requests.isEmpty)
        reader.clear()
    }

    func testPDFLayoutHighlightsOriginalWordsAndOrderChangesRequirePlay() async throws {
        try await TextRecognitionCapability.requireOnDeviceTextRecognition()
        let directory = try TemporaryVault.make(prefix: "ReadAloudPDFLayout", for: self).root
        let location = try makePDF(in: directory, pageTexts: ["Before repeated word. After repeated word."])
        let originalBytes = try Data(contentsOf: location)
        let pdf = try await PDFSession.open(location)
        let page = try XCTUnwrap(pdf.document.page(at: 0))
        let text = try XCTUnwrap(page.string) as NSString
        let repeatedRange = text.range(of: "repeated", options: .backwards)
        let (reader, speech) = try makeReader()
        reader.choosePDFReadingOrder(.layout)
        reader.readPDFRange(pdf, start: PDFReadAloudEndpoint(pageIndex: 0, offset: repeatedRange.location, revision: pdf.changeVersion),
                            end: PDFReadAloudEndpoint(pageIndex: 0, offset: NSMaxRange(text.range(of: "word.", options: .backwards)), revision: pdf.changeVersion))
        try await waitForPreparation(reader, timeout: .seconds(30))
        XCTAssertNil(reader.errorMessage)
        XCTAssertTrue(reader.sourceHighlightNotice?.contains("on-device") == true)
        XCTAssertEqual(reader.session.currentPassage?.text, "repeated word.")
        reader.session.play()
        let originalRequest = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(originalRequest, NSRange(location: 0, length: 8)))
        XCTAssertEqual(reader.highlights(in: pdf).map(\.characterRange), [repeatedRange])
        reader.choosePDFReadingOrder(.file)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.currentPassage?.text, "repeated word.")
        XCTAssertEqual(speech.requests.count, 1)
        XCTAssertNotEqual(reader.session.state, .speaking)
        speech.eventHandler?(.spoken(originalRequest, NSRange(location: 9, length: 4)))
        XCTAssertTrue(reader.highlights(in: pdf).isEmpty)
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
        XCTAssertFalse(pdf.hasUnsavedChanges)
        reader.clear()
    }

    /// A page turned between two pages read: the text is the same, so reading goes on to it.
    func testPDFPageTurnedBetweenLazyPagesReadsOn() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudPDFRevision", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["First page.", "Second page."]))
        let (reader, speech) = try makeReader()
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        try await waitForPreparation(reader)
        reader.session.play()
        let request = try XCTUnwrap(speech.requests.last?.identifier)
        try pdf.apply(.rotate(page: 1, clockwise: true))
        speech.eventHandler?(.finished(request))
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.sourcePageIndex, 1)
        XCTAssertEqual(reader.session.document?.passages.first?.text, "Second page.")
        reader.clear()
    }

    /// Ink and saves are not changes to what is read: the highlight stays and reading goes on.
    func testInkOnThePageReadKeepsReadingAndItsHighlight() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudPDFInk", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["First page words.", "Second page."]))
        let (reader, speech) = try makeReader()
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        try await waitForPreparation(reader)
        reader.session.play()
        let request = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.started(request)); speech.eventHandler?(.spoken(request, NSRange(location: 6, length: 4)))
        let before = reader.highlights(in: pdf)
        XCTAssertFalse(before.isEmpty)
        let versionBefore = pdf.readingTextVersion
        // A picture placed on the page, as ink and markup are, changes the PDF but not its text.
        let page = try XCTUnwrap(pdf.document.page(at: 0))
        page.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 40, height: 40), forType: .ink, withProperties: nil))
        pdf.contentDidChange?()
        XCTAssertEqual(pdf.readingTextVersion, versionBefore)
        reader.pdfContentDidChange(pdf)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.state, .speaking)
        XCTAssertEqual(reader.highlights(in: pdf), before)
        reader.clear()
    }

    func testStopCancelsPendingPreparation() async throws {
        let (reader, speech) = try makeReader()
        reader.readMarkdown(String(repeating: "Words. ", count: 50_000), path: try VaultPath("Long.md"))
        reader.stop()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(reader.isPreparing)
        XCTAssertNil(reader.session.document)
        XCTAssertTrue(speech.requests.isEmpty)
    }

    func testReaderScreenRendersWithChosenVoiceAndTranscript() async throws {
        let (reader, _) = try makeReader()
        reader.readMarkdown("## Introduction\n\nRead this passage.", path: try VaultPath("Note.md"))
        try await waitForPreparation(reader)
        let hosting = NSHostingView(rootView: ReadAloudReader(reader: reader))
        hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 720)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(hosting.fittingSize.width, 0)
        reader.clear()
    }

    func testPDFSelectionHighlightsExactRepeatedOccurrenceAndPreservesSelectionSearchAndFile() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudSelection", for: self).root
        let location = try makePDF(in: directory, pageTexts: ["Echo first. Echo last."])
        let originalBytes = try Data(contentsOf: location)
        let pdf = try await PDFSession.open(location)
        let page = try XCTUnwrap(pdf.document.page(at: 0))
        let pageText = try XCTUnwrap(page.string) as NSString
        let selectedRange = pageText.range(of: "Echo", options: .backwards)
        pdf.readAloudSelection = try XCTUnwrap(page.selection(for: selectedRange))
        let view = PDFView()
        view.document = pdf.document
        pdf.pdfView = view
        let userSelection = try XCTUnwrap(page.selection(for: pageText.range(of: "last")))
        view.currentSelection = userSelection
        let searchSelection = try XCTUnwrap(page.selection(for: pageText.range(of: "first")))
        view.highlightedSelections = [searchSelection]
        let annotationCount = page.annotations.count
        let highlighter = PDFReadAloudHighlighter()
        let (reader, speech) = try makeReader()
        reader.readPDFSelection(pdf)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.currentPassage?.text, "Echo")
        reader.session.play()
        speech.eventHandler?(.spoken(try XCTUnwrap(speech.requests.last?.identifier), NSRange(location: 0, length: 4)))
        let highlights = reader.highlights(in: pdf)
        XCTAssertEqual(highlights, [PDFReadAloudHighlight(pageIndex: 0, characterRange: selectedRange, expectedText: "Echo")])
        highlighter.update(highlights, in: view)
        let readingSelection = try XCTUnwrap(view.highlightedSelections?.last)
        XCTAssertEqual(readingSelection.range(at: 0, on: page), selectedRange)
        XCTAssertEqual(view.highlightedSelections?.count, 2)
        XCTAssertEqual(view.currentSelection?.string, userSelection.string)
        XCTAssertEqual(view.currentSelection?.range(at: 0, on: page), userSelection.range(at: 0, on: page))
        XCTAssertTrue(reader.canShowPDFPassage)
        XCTAssertTrue(reader.showPDFPassage())
        XCTAssertEqual(view.currentSelection?.string, userSelection.string)
        reader.session.pause()
        XCTAssertEqual(reader.highlights(in: pdf), highlights)
        reader.stop()
        highlighter.update(reader.highlights(in: pdf), in: view)
        XCTAssertEqual(view.highlightedSelections?.count, 1)
        XCTAssertTrue(view.highlightedSelections?.first === searchSelection)
        XCTAssertEqual(page.annotations.count, annotationCount)
        XCTAssertFalse(pdf.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: location), originalBytes)
    }

    func testPDFSelectionAcrossPagesRetainsOnlySelectedRanges() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudAcrossPages", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["Before alpha ignored beta after.", "Outside gamma tail."]))
        let selection = PDFSelection(document: pdf.document)
        for (pageIndex, word) in [(0, "alpha"), (0, "beta"), (1, "gamma")] {
            let page = try XCTUnwrap(pdf.document.page(at: pageIndex))
            let pageText = try XCTUnwrap(page.string) as NSString
            selection.add(try XCTUnwrap(page.selection(for: pageText.range(of: word))))
        }
        pdf.readAloudSelection = selection
        let (reader, speech) = try makeReader()
        reader.readPDFSelection(pdf)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.currentPassage?.text, "alpha beta gamma")
        reader.session.play()
        let identifier = try XCTUnwrap(speech.requests.last?.identifier)
        speech.eventHandler?(.spoken(identifier, NSRange(location: 11, length: 5)))
        XCTAssertEqual(reader.highlights(in: pdf).map(\.pageIndex), [1])
        XCTAssertEqual(reader.highlights(in: pdf).map(\.expectedText), ["gamma"])
        speech.eventHandler?(.spoken(identifier, NSRange(location: 0, length: 16)))
        XCTAssertEqual(reader.highlights(in: pdf).map(\.expectedText), ["alpha", "beta", "gamma"])
        reader.documentDidChange(pdf.location.path)
        XCTAssertTrue(reader.highlights(in: pdf).isEmpty)
    }

    func testPDFUnicodeCoordinatesAndHighlightValidation() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudUnicodePDF", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["café e\u{301} ﬁ 😀 omega"]))
        let page = try XCTUnwrap(pdf.document.page(at: 0))
        let pageText = try XCTUnwrap(page.string) as NSString
        XCTAssertEqual(page.numberOfCharacters, pageText.length)
        let wordRange = pageText.range(of: "omega")
        XCTAssertNotEqual(wordRange.location, NSNotFound)
        let nativeSelection = try XCTUnwrap(page.selection(for: wordRange))
        let source = try PDFReadAloudSource.selection(nativeSelection, in: pdf.document)
        XCTAssertEqual(source.text, "omega")
        let highlights = source.highlights(for: NSRange(location: 0, length: 5))
        let view = PDFView()
        view.document = pdf.document
        page.rotation = 90
        let highlighter = PDFReadAloudHighlighter()
        highlighter.update(highlights, in: view)
        XCTAssertEqual(view.highlightedSelections?.first?.string, "omega")
        XCTAssertFalse(try XCTUnwrap(view.highlightedSelections?.first).bounds(for: page).isEmpty)
        highlighter.update([PDFReadAloudHighlight(pageIndex: 0, characterRange: wordRange, expectedText: "wrong")], in: view)
        XCTAssertTrue(view.highlightedSelections?.isEmpty ?? true)
        highlighter.update([PDFReadAloudHighlight(pageIndex: 0, characterRange: NSRange(location: Int.max, length: 10), expectedText: "omega")], in: view)
        XCTAssertTrue(view.highlightedSelections?.isEmpty ?? true)
        highlighter.clear(in: view)
    }

    func testNativePDFPaneReceivesSpeechHighlightsAndClearsThemOnStop() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudHostedPDF", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["Follow these words."]))
        let (reader, speech) = try makeReader()
        let hosting = NSHostingView(rootView: PDFPane(session: pdf, readAloud: reader, resolveConflict: { _ in }).frame(width: 640, height: 720))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.showInvisibly()
        defer { window.orderOut(nil); window.contentView = nil }
        hosting.frame = CGRect(x: 0, y: 0, width: 640, height: 720)
        hosting.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(pdf.pdfView)
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 0)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.sourceHighlightNotice)
        reader.session.play()
        speech.eventHandler?(.spoken(try XCTUnwrap(speech.requests.last?.identifier), NSRange(location: 0, length: 6)))
        let deadline = ContinuousClock.now + .seconds(2)
        while view.highlightedSelections?.first?.string != "Follow", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            hosting.layoutSubtreeIfNeeded()
        }
        XCTAssertEqual(view.highlightedSelections?.first?.string, "Follow")
        reader.stop()
        let stopDeadline = ContinuousClock.now + .seconds(2)
        while view.highlightedSelections?.isEmpty == false, ContinuousClock.now < stopDeadline {
            try await Task.sleep(for: .milliseconds(10))
            hosting.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(view.highlightedSelections?.isEmpty ?? true)
        XCTAssertFalse(pdf.hasUnsavedChanges)
    }

    func testMarkedPDFRangeReadsInclusiveWordsAcrossPagesAndStopsAtEnd() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudMarkedRange", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["Before alpha beta.", "Gamma delta after.", "Do not read."]))
        let firstPage = try XCTUnwrap(pdf.document.page(at: 0))
        let lastPage = try XCTUnwrap(pdf.document.page(at: 1))
        let firstText = try XCTUnwrap(firstPage.string) as NSString
        let lastText = try XCTUnwrap(lastPage.string) as NSString
        pdf.readAloudSelection = firstPage.selection(for: firstText.range(of: "alpha"))
        let start = try PDFReadAloudSource.endpoint(in: pdf, isEnd: false)
        pdf.readAloudSelection = lastPage.selection(for: lastText.range(of: "delta"))
        let end = try PDFReadAloudSource.endpoint(in: pdf, isEnd: true)
        let (reader, speech) = try makeReader()
        reader.readPDFRange(pdf, start: start, end: end)
        try await waitForPreparation(reader)
        XCTAssertNil(reader.errorMessage)
        XCTAssertEqual(reader.session.currentPassage?.text, "alpha beta.")
        reader.session.play()
        speech.eventHandler?(.spoken(try XCTUnwrap(speech.requests.last?.identifier), NSRange(location: 0, length: 5)))
        XCTAssertEqual(reader.highlights(in: pdf).first?.characterRange, firstText.range(of: "alpha"))
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        try await waitForPreparation(reader)
        XCTAssertEqual(speech.requests.last?.text, "Gamma delta")
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        XCTAssertEqual(reader.session.state, .finished)
        XCTAssertEqual(speech.requests.count, 2)
        reader.readPDFRange(pdf, start: end, end: start)
        XCTAssertNotNil(reader.errorMessage)
        reader.readPDFRange(pdf, start: PDFReadAloudEndpoint(pageIndex: 0, offset: 0, revision: -1), end: end)
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertFalse(pdf.hasUnsavedChanges)
    }

    func testNativePDFFollowingRevealsNextPageAndCanBeSuspendedAndResumed() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudPDFFollow", for: self).root
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["First page.", "Second page."]))
        let (reader, speech) = try makeReader()
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        view.document = pdf.document
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        pdf.pdfView = view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.showInvisibly()
        defer { window.orderOut(nil); window.contentView = nil }
        view.layoutDocumentView()
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let observer = PDFViewPageObserver(session: pdf, view: view)
        defer { observer.stop() }
        let firstPage = try XCTUnwrap(pdf.document.page(at: 0))
        let secondPage = try XCTUnwrap(pdf.document.page(at: 1))
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        try await waitForPreparation(reader)
        reader.session.play()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        try await waitForPreparation(reader)
        reader.suspendFollowing()
        XCTAssertFalse(reader.shouldFollow(pdf))
        view.go(to: firstPage)
        speech.eventHandler?(.spoken(try XCTUnwrap(speech.requests.last?.identifier), NSRange(location: 0, length: 6)))
        observer.highlightReading(reader.highlights(in: pdf), followsReading: reader.shouldFollow(pdf), suspendFollowing: { reader.suspendFollowing() })
        for _ in 0..<10 { try await Task.sleep(for: .milliseconds(10)); view.layoutSubtreeIfNeeded() }
        let selection = try XCTUnwrap(secondPage.selection(for: NSRange(location: 0, length: 6)))
        XCTAssertFalse(view.bounds.intersects(view.convert(selection.bounds(for: secondPage), from: secondPage)))
        reader.followsReading = true
        XCTAssertTrue(reader.shouldFollow(pdf))
        observer.highlightReading(reader.highlights(in: pdf), followsReading: reader.shouldFollow(pdf), suspendFollowing: { reader.suspendFollowing() })
        let deadline = ContinuousClock.now + .seconds(2)
        while !view.bounds.contains(view.convert(selection.bounds(for: secondPage), from: secondPage)), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10)); view.layoutSubtreeIfNeeded()
        }
        XCTAssertTrue(view.bounds.contains(view.convert(selection.bounds(for: secondPage), from: secondPage)), "view=\(view.bounds) word=\(view.convert(selection.bounds(for: secondPage), from: secondPage)) document=\(String(describing: view.documentView?.frame)) scroll=\(String(describing: view.documentView?.enclosingScrollView?.contentView.bounds)) currentPage=\(pdf.currentPageIndex)")
        reader.session.pause()
        XCTAssertFalse(reader.shouldFollow(pdf))
        reader.clear()
    }
}
