import XCTest
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
private final class RecordingSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test", name: "Test", language: "en-US", quality: 3)]
    var requests: [(text: String, identifier: UUID)] = []
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { requests.append((text, requestIdentifier)) }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

@MainActor
final class ReadAloudNavigatorStopTests: XCTestCase {
    private func makePDF(in directory: URL, pageTexts: [String]) throws -> URL {
        let location = directory.appendingPathComponent("Paper.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 600)
        let context = try XCTUnwrap(CGContext(location as CFURL, mediaBox: &mediaBox, nil))
        for text in pageTexts {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18)]).draw(at: CGPoint(x: 40, y: 500))
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return location
    }

    /// Yields to the preparation tasks until `reader` has prepared, with a bound so a stuck
    /// preparation fails the test instead of hanging it.
    private func finishPreparing(_ reader: ReadAloudController) async {
        let deadline = ContinuousClock.now + .seconds(30)
        while reader.isPreparing, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(reader.isPreparing, "Preparation did not finish.")
    }

    func testStopInThePlayerWhileTheNextPDFPageIsPreparingCancelsThatPage() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudNavigatorStop", for: self).root
        let pdf = try await PDFSession.open(try makePDF(in: directory, pageTexts: ["First page.", "Second page."]))
        let speech = RecordingSpeech()
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudNavigatorStopTests", for: self).preferences
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        let reader = ReadAloudController(session: session, preferences: preferences)
        reader.choosePDFReadingOrder(.file)
        let navigator = ReadAloudNavigator(reader: reader, preferences: preferences)
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        await finishPreparing(reader)
        session.play()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        XCTAssertTrue(reader.isPreparing, "The first page ended, so the second page is being prepared.")

        navigator.stopAndRewind()

        XCTAssertFalse(reader.isPreparing, "Stop must cancel the page being prepared, or it starts reading after Stop.")
        XCTAssertNotEqual(session.state, .speaking)

        session.play()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        await finishPreparing(reader)
        XCTAssertEqual(reader.sourcePageIndex, 1, "Play after Stop reads the first page again and goes on to the second.")
        XCTAssertEqual(speech.requests.map(\.text), ["First page.", "First page.", "Second page."])
        reader.clear()
    }

    func testStopInThePlayerBetweenPagesStillLetsPlayGoOnThroughTheChosenPages() async throws {
        let directory = try TemporaryVault.make(prefix: "ReadAloudNavigatorStop", for: self).root
        let pdf = try await PDFSession.open(try makePDF(in: directory, pageTexts: ["First page.", "Second page."]))
        let speech = RecordingSpeech()
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudNavigatorStopTests", for: self).preferences
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        let reader = ReadAloudController(session: session, preferences: preferences)
        reader.choosePDFReadingOrder(.file)
        let navigator = ReadAloudNavigator(reader: reader, preferences: preferences)
        reader.readPDF(pdf, firstPageIndex: 0, lastPageIndex: 1)
        await finishPreparing(reader)
        session.play()

        navigator.stopAndRewind()
        session.play()
        speech.eventHandler?(.finished(try XCTUnwrap(speech.requests.last?.identifier)))
        await finishPreparing(reader)

        XCTAssertEqual(reader.sourcePageIndex, 1)
        XCTAssertEqual(speech.requests.map(\.text), ["First page.", "First page.", "Second page."])
        reader.clear()
    }

    /// BUG-VOICE-02: Stop in the player while a fold change is prepared: the note with its new folds replaces
    /// the old one, and reading stays stopped at the beginning until Play.
    func testStopInThePlayerWhileAFoldChangeIsPreparedDoesNotStartReadingAgain() async throws {
        let speech = RecordingSpeech()
        let preferences = try IsolatedDeviceState.make(prefix: "ReadAloudNavigatorStopTests", for: self).preferences
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        let reader = ReadAloudController(session: session, preferences: preferences)
        let navigator = ReadAloudNavigator(reader: reader, preferences: preferences)
        let path = try VaultPath("Folds.md")
        let note = "Opening line.\n\n> [!note]- Hidden derivation\n> The long hidden proof.\n\nClosing line."
        reader.readMarkdown(note, path: path, hiddenRanges: ReadAloudFolding.hiddenRanges(in: note, foldedKeys: [], calloutExpansion: [:]))
        await finishPreparing(reader)
        session.play()
        XCTAssertEqual(speech.requests.map(\.text), ["Opening line."])
        let expanded = ReadAloudFolding.hiddenRanges(in: note, foldedKeys: [],
                                                     calloutExpansion: [ReadAloudFolding.calloutKey(type: "note", title: "Hidden derivation"): true])

        reader.foldsDidChange(in: path, hiddenRanges: expanded)
        navigator.stopAndRewind()
        try await waitUntil("the note is prepared again with the unfolded callout", timeoutSeconds: 10) {
            session.document?.passages.count == 4
        }

        XCTAssertNotEqual(session.state, .speaking, "Stop must hold while the fold change is prepared; reading started again by itself.")
        XCTAssertEqual(session.passageIndex, 0, "Stop goes back to the beginning.")
        XCTAssertEqual(speech.requests.map(\.text), ["Opening line."], "Nothing more is spoken after Stop.")
        reader.clear()
    }
}
