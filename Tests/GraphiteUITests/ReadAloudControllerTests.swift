import XCTest
import AppKit
import PDFKit
import SwiftUI
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

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
    private func makeReader() throws -> (ReadAloudController, ControllerTestSpeech) {
        let speech = ControllerTestSpeech()
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudControllerTests-\(UUID().uuidString)"))
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        return (ReadAloudController(session: session), speech)
    }

    private func waitForPreparation(_ reader: ReadAloudController) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudBlankPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["", "Later."]))
        let (reader, speech) = try makeReader()
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        try await waitForPreparation(reader)
        XCTAssertNotNil(reader.errorMessage)
        XCTAssertTrue(speech.requests.isEmpty)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudSelection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudAcrossPages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        XCTAssertEqual(reader.session.currentPassage?.text, "alpha\nbeta\ngamma")
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudUnicodePDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudHostedPDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["Follow these words."]))
        let (reader, speech) = try makeReader()
        let hosting = NSHostingView(rootView: PDFPane(session: pdf, readAloud: reader, resolveConflict: { _ in }).frame(width: 640, height: 720))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 720), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudMarkedRange-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudPDFFollow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = try await PDFSession.open(makePDF(in: directory, pageTexts: ["First page.", "Second page."]))
        let (reader, speech) = try makeReader()
        let view = PDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        view.document = pdf.document
        view.displayMode = .singlePageContinuous
        view.autoScales = true
        pdf.pdfView = view
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
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
