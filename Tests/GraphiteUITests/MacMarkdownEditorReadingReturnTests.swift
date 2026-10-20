#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

/// A kept Mac note editor shown again after reading view starts where the reading view was.
@MainActor
final class MacMarkdownEditorReadingReturnTests: XCTestCase {
    private var fixture: MacMarkdownEditorFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    private static let text = (0..<300).map { index in "Line \(index)" }.joined(separator: "\n")

    private func characterLocation(ofLine index: Int) -> Int {
        (Self.text as NSString).range(of: "Line \(index)\n").location
    }

    /// Reading view of the session's note scrolled so the block at `noteOffset` is at its top.
    private func scrollReadingView(of session: MarkdownSession, toBlockAt noteOffset: Int) {
        session.readingPosition.blockLocations = [ReadingBlockLocation(blockIdentifier: "block", noteOffset: noteOffset, lineNoteOffsets: [])]
        session.readingPosition.record(CGRect(x: 0, y: 0, width: 400, height: 200), ofBlock: "block")
        session.readingPosition.visibleTop = 0
        session.readingPosition.verticalOffset = noteOffset == 0 ? 0 : 500
    }

    /// The editor kept while the note was read, shown again by the pane's next update.
    private func showEditorAgain(_ fixture: MacMarkdownEditorFixture) {
        fixture.hostScrollViewAgain()
        fixture.coordinator.resume(fixture.scrollView)
        fixture.coordinator.serveSessionRequests(in: fixture.textView)
        fixture.coordinator.performPendingJumpIfReady(in: fixture.textView)
    }

    func testEditorShownAgainAfterReadingStartsAtThePassageThatWasRead() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.scrollToTop(ofCharacter: characterLocation(ofLine: 20))
        fixture.session.viewMode = .reading
        fixture.coordinator.suspend(fixture.scrollView)
        scrollReadingView(of: fixture.session, toBlockAt: characterLocation(ofLine: 200))

        fixture.session.viewMode = .livePreview
        showEditorAgain(fixture)

        fixture.coordinator.recordScrollLocation(of: fixture.textView)
        XCTAssertEqual(fixture.session.savedScrollLocation, characterLocation(ofLine: 200))
    }

    func testEditorShownAgainAfterReadingAtTheTopOfTheNoteScrollsToTheTop() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.scrollToTop(ofCharacter: characterLocation(ofLine: 150))
        fixture.session.viewMode = .reading
        fixture.coordinator.suspend(fixture.scrollView)
        scrollReadingView(of: fixture.session, toBlockAt: 0)

        fixture.session.viewMode = .livePreview
        showEditorAgain(fixture)

        XCTAssertEqual(fixture.textView.visibleRect.minY, 0, accuracy: 1)
    }

    func testTheReadingPlaceIsUsedOnceAndAnEditorShownLaterIsLeftWhereItIs() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: Self.text)
        self.fixture = fixture
        fixture.session.viewMode = .reading
        scrollReadingView(of: fixture.session, toBlockAt: characterLocation(ofLine: 200))
        fixture.session.viewMode = .livePreview
        showEditorAgain(fixture)
        fixture.scrollToTop(ofCharacter: characterLocation(ofLine: 40))

        fixture.coordinator.serveSessionRequests(in: fixture.textView)
        fixture.coordinator.performPendingJumpIfReady(in: fixture.textView)

        fixture.coordinator.recordScrollLocation(of: fixture.textView)
        XCTAssertEqual(fixture.session.savedScrollLocation, characterLocation(ofLine: 40))
    }
}
#endif
