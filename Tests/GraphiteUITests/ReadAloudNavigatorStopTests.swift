import XCTest
import AppKit
import PDFKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI

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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudNavigatorStop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = try await PDFSession.open(try makePDF(in: directory, pageTexts: ["First page.", "Second page."]))
        let speech = RecordingSpeech()
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudNavigatorStopTests-\(UUID().uuidString)"))
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudNavigatorStop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pdf = try await PDFSession.open(try makePDF(in: directory, pageTexts: ["First page.", "Second page."]))
        let speech = RecordingSpeech()
        let preferences = try XCTUnwrap(UserDefaults(suiteName: "ReadAloudNavigatorStopTests-\(UUID().uuidString)"))
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
}
