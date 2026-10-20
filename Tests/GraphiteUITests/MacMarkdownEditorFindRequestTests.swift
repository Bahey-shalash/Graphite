#if os(macOS)
import AppKit
import XCTest
@testable import GraphiteUI

/// The Mac note editor opens its find bar when the command palette asks the session for one.
@MainActor
final class MacMarkdownEditorFindRequestTests: XCTestCase {
    private var fixture: MacMarkdownEditorFixture?

    override func tearDown() async throws {
        fixture?.tearDown()
        fixture = nil
        try await super.tearDown()
    }

    /// Lets work the editor queued for the next main-queue turn run.
    private func waitForNextMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    func testTheMacTextViewUsesTheFindBarInTheScrollView() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: "Alpha\nBeta\n")
        self.fixture = fixture
        XCTAssertTrue(fixture.textView.usesFindBar)
    }

    func testFindRequestShowsTheFindBarAndIsAnswered() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: "Alpha\nBeta\n")
        self.fixture = fixture
        fixture.session.requestFind(.find, editingMode: .livePreview)
        XCTAssertFalse(fixture.scrollView.isFindBarVisible)

        fixture.coordinator.serveSessionRequests(in: fixture.textView)
        await waitForNextMainQueueTurn()

        XCTAssertTrue(fixture.scrollView.isFindBarVisible)
        XCTAssertNil(fixture.session.findRequest, "An answered request does not open the bar again at the next update.")
    }

    /// The shown text fields in the find bar: a search field, and a replacement field in replace mode.
    private func textFieldCount(inFindBarOf scrollView: NSScrollView) -> Int {
        func count(in view: NSView) -> Int {
            (view is NSTextField && !view.isHiddenOrHasHiddenAncestor ? 1 : 0) + view.subviews.reduce(0) { total, subview in total + count(in: subview) }
        }
        return scrollView.findBarView.map(count(in:)) ?? 0
    }

    func testFindAndReplaceRequestShowsTheReplacementFieldThatFindDoesNot() async throws {
        let findOnly = try await MacMarkdownEditorFixture(text: "Alpha\nBeta\n")
        findOnly.session.requestFind(.find, editingMode: .livePreview)
        findOnly.coordinator.serveSessionRequests(in: findOnly.textView)
        await waitForNextMainQueueTurn()
        let findOnlyFieldCount = textFieldCount(inFindBarOf: findOnly.scrollView)
        findOnly.tearDown()

        let withReplace = try await MacMarkdownEditorFixture(text: "Alpha\nBeta\n")
        fixture = withReplace
        withReplace.session.requestFind(.findAndReplace, editingMode: .livePreview)
        withReplace.coordinator.serveSessionRequests(in: withReplace.textView)
        await waitForNextMainQueueTurn()

        XCTAssertGreaterThan(textFieldCount(inFindBarOf: withReplace.scrollView), findOnlyFieldCount)
    }

    func testFindAndReplaceRequestShowsTheFindBarAndIsAnswered() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: "Alpha\nBeta\n")
        self.fixture = fixture
        fixture.session.requestFind(.findAndReplace, editingMode: .livePreview)

        fixture.coordinator.serveSessionRequests(in: fixture.textView)
        await waitForNextMainQueueTurn()

        XCTAssertTrue(fixture.scrollView.isFindBarVisible)
        XCTAssertNil(fixture.session.findRequest)
    }

    func testNoFindBarWithoutARequest() async throws {
        let fixture = try await MacMarkdownEditorFixture(text: "Alpha\nBeta\n")
        self.fixture = fixture

        fixture.coordinator.serveSessionRequests(in: fixture.textView)
        await waitForNextMainQueueTurn()

        XCTAssertFalse(fixture.scrollView.isFindBarVisible)
    }
}
#endif
