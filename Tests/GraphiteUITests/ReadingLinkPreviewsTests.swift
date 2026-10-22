import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// The reading view's link cards: the links the reading view draws, as `GraphiteOpenLink`
/// addresses, and what the pointer and a long press on them do.
@MainActor
final class ReadingLinkPreviewsTests: XCTestCase {
    private func address(_ destination: String) throws -> URL {
        try XCTUnwrap(URL(string: destination))
    }

    func testANotesLinksAskForCardsAndFootnotesWebPagesAndUnresolvedLinksDoNot() throws {
        let note = try VaultPath("Notes/Note.md")
        let frame = CGRect(x: 1, y: 2, width: 3, height: 4)
        let wikilink = try XCTUnwrap(ReadingLinkPreviews.request(for: try address(GraphiteOpenLink.markdownDestination(target: "Other#Plan")), anchoredAt: frame,
                                                                 trigger: .hover, sourceNote: note))
        XCTAssertEqual(wikilink, LinkPreviewRequest(target: "Other#Plan", isWiki: true, sourceNote: note, anchor: frame, trigger: .hover, source: .reading))
        let markdownLink = try XCTUnwrap(ReadingLinkPreviews.request(for: try address(GraphiteOpenLink.markdownDestination(target: "../Other.md", isWiki: false)),
                                                                     anchoredAt: frame, trigger: .press, sourceNote: note))
        XCTAssertFalse(markdownLink.isWiki)
        XCTAssertEqual(markdownLink.trigger, .press)

        let unresolved = try address(GraphiteOpenLink.markingUnresolved(GraphiteOpenLink.markdownDestination(target: "Nobody")))
        XCTAssertNil(ReadingLinkPreviews.request(for: unresolved, anchoredAt: frame, trigger: .hover, sourceNote: note))
        XCTAssertNil(ReadingLinkPreviews.request(for: try address(GraphiteOpenLink.footnoteDestination(number: 2)), anchoredAt: frame, trigger: .hover, sourceNote: note))
        XCTAssertNil(ReadingLinkPreviews.request(for: try address("https://example.com"), anchoredAt: frame, trigger: .hover, sourceNote: note))
    }

    func testThePointerComingOntoALinkAndLeavingItAndALongPressReachTheCards() throws {
        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        let previews = ReadingLinkPreviews()
        let note = try VaultPath("Note.md")
        let link = try address(GraphiteOpenLink.markdownDestination(target: "Other"))

        previews.pointerEntered(link, frame: .zero, sourceNote: note, model: cards)
        guard case .waiting(let request) = cards.phase, request.target == "Other", request.source == .reading else { return XCTFail("\(cards.phase)") }
        previews.pointerLeft(model: cards)
        guard case .hidden = cards.phase else { return XCTFail("Off the link before the delay, no card.") }

        previews.press(link, frame: .zero, sourceNote: note, model: cards)
        guard case .waiting(let held) = cards.phase else { return XCTFail("\(cards.phase)") }
        XCTAssertEqual(held.trigger, .press)
    }
}
