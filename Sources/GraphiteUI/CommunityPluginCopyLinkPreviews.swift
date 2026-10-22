import CoreGraphics
import Foundation
import GraphiteCore

/// The preview cards of links in one copy of a plugin's block or view: the link a plugin asks
/// to preview where the pointer rests (`hover-link`), or an internal link the plugin drew.
/// A card closes when the pointer moves to another element of the copy or leaves it.
@MainActor
final class CommunityPluginCopyLinkPreviews {
    /// The cards of the window showing the copy; nil while Page Preview is off.
    weak var linkPreviews: LinkPreviewModel?
    private var shownRequest: LinkPreviewRequest?
    /// Counts the pointer's moves, so a link answered for an element the pointer has left
    /// shows nothing.
    private var moveCount = 0

    /// The pointer moved to another element of the copy, or left it: the card shown for the
    /// element it was on closes. Returns the move's number, which a card for it is shown with.
    func pointerMoved() -> Int {
        moveCount += 1
        if let shownRequest { linkPreviews?.pointerLeft(shownRequest) }
        shownRequest = nil
        return moveCount
    }

    /// Shows `link`'s card beside `anchor`, a frame in window coordinates, while the pointer
    /// is still where move `moveNumber` put it.
    func show(_ link: CommunityPluginHoveredLink, anchoredAt anchor: CGRect, forMove moveNumber: Int) {
        guard moveNumber == moveCount, let linkPreviews else { return }
        let request = link.previewRequest(anchoredAt: anchor)
        shownRequest = request
        linkPreviews.pointerEntered(request)
    }
}
