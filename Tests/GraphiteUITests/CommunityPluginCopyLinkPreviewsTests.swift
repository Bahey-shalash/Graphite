import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A copy's link cards: a link answered for an element the pointer has left shows nothing,
/// and the card shown closes when the pointer moves on.
@MainActor
final class CommunityPluginCopyLinkPreviewsTests: XCTestCase {
    func testOnlyTheLatestMovesLinkShowsAndMovingOnLetsItGo() throws {
        let cards = LinkPreviewModel(clock: ManualClock(), announceHover: { _ in })
        let previews = CommunityPluginCopyLinkPreviews()
        previews.linkPreviews = cards
        let link = CommunityPluginHoveredLink(linktext: "Other", sourcePath: "Notes/Note.md")

        let earlierMove = previews.pointerMoved()
        let latestMove = previews.pointerMoved()
        previews.show(link, anchoredAt: CGRect(x: 5, y: 6, width: 7, height: 8), forMove: earlierMove)
        guard case .hidden = cards.phase else { return XCTFail("The pointer has left that element.") }

        previews.show(link, anchoredAt: CGRect(x: 5, y: 6, width: 7, height: 8), forMove: latestMove)
        guard case .waiting(let request) = cards.phase else { return XCTFail("The link's card is on its way: \(cards.phase)") }
        XCTAssertEqual(request, LinkPreviewRequest(target: "Other", isWiki: true, sourceNote: try VaultPath("Notes/Note.md"),
                                                   anchor: CGRect(x: 5, y: 6, width: 7, height: 8), trigger: .hover, source: .plugin))

        _ = previews.pointerMoved()
        guard case .hidden = cards.phase else { return XCTFail("Moving on before the card showed stops it.") }
    }
}
