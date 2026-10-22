import CoreGraphics
import Foundation
import GraphiteCore

/// What an editor's text view tells its link previews about the text under the pointer. Two
/// text views give it, the iPad's (`MarkdownTextView`) and the Mac's (`MarkdownMacTextView`),
/// so that `EditorLinkPreviews` decides for both.
@MainActor
protocol EditorLinkPreviewSurface: AnyObject {
    /// The note's text as the view holds it.
    var linkPreviewSource: NSString { get }
    /// The character nearest `windowPoint`, a point in window coordinates; nil away from the text.
    func characterIndex(atWindowPoint windowPoint: CGPoint) -> Int?
    /// The frames the characters of `range` are drawn in, one per line, in window coordinates.
    func windowFrames(ofCharacters range: NSRange) -> [CGRect]
}

/// The preview cards of the links in one note's editor, the same on the iPad and the Mac:
/// which link the pointer rests on, when its card is asked for, and when it closes.
@MainActor
final class EditorLinkPreviews {
    private struct HoveredLink {
        /// Where the link is drawn, one frame per line, in window coordinates.
        let frames: [CGRect]
        let request: LinkPreviewRequest
    }

    /// The window's cards; nil while Page Preview is off, and then nothing watches the pointer.
    private(set) weak var model: LinkPreviewModel?
    private var sourceNote = VaultPath.root
    private var hoveredLink: HoveredLink?
    /// The character the pointer last rested on away from any link, so that resting there
    /// does not look for a link again.
    private var characterIndexWithoutLink: Int?

    var isWatchingPointer: Bool { model != nil }

    /// Shows the cards of `model` for the links of `sourceNote`; answers whether the pointer is
    /// watched from now on when it was not, or the reverse.
    func use(_ model: LinkPreviewModel?, sourceNote: VaultPath) -> Bool {
        let wasWatchingPointer = isWatchingPointer
        if self.model !== model { pointerLeft() }
        self.model = model
        self.sourceNote = sourceNote
        return wasWatchingPointer != isWatchingPointer
    }

    /// The pointer of a mouse or trackpad, or Apple Pencil hovering, moved to `windowPoint`
    /// over the text of `surface`.
    func pointerMoved(to windowPoint: CGPoint, over surface: some EditorLinkPreviewSurface) {
        guard let model else { return }
        if let hoveredLink, hoveredLink.frames.contains(where: { frame in frame.contains(windowPoint) }) { return }
        let characterIndex = surface.characterIndex(atWindowPoint: windowPoint)
        if hoveredLink == nil, characterIndex != nil, characterIndex == characterIndexWithoutLink { return }
        pointerLeft()
        guard let found = link(at: windowPoint, nearCharacter: characterIndex, in: surface) else {
            characterIndexWithoutLink = characterIndex
            return
        }
        let request = previewRequest(for: found.link, anchoredAt: found.anchor, trigger: .hover)
        hoveredLink = HoveredLink(frames: found.frames, request: request)
        model.pointerEntered(request)
    }

    /// The link at `windowPoint` was held: its card shows at once. False when there is no
    /// link there, or Page Preview is off.
    func press(at windowPoint: CGPoint, in surface: some EditorLinkPreviewSurface) -> Bool {
        let characterIndex = surface.characterIndex(atWindowPoint: windowPoint)
        guard let model, let found = link(at: windowPoint, nearCharacter: characterIndex, in: surface) else { return false }
        pointerLeft()
        model.show(previewRequest(for: found.link, anchoredAt: found.anchor, trigger: .press))
        return true
    }

    /// The pointer left the text: the card of the link it was on closes unless it reaches it.
    func pointerLeft() {
        if let hoveredLink { model?.pointerLeft(hoveredLink.request) }
        hoveredLink = nil
        characterIndexWithoutLink = nil
    }

    /// Closes the card: the note was typed in or scrolled, which moved its links from under
    /// the pointer, or Escape was pressed.
    func closeCard() {
        hoveredLink = nil
        characterIndexWithoutLink = nil
        model?.close()
    }

    /// Whether a card is shown or on its way, which Escape closes.
    var isShowingCard: Bool { model?.phase.request != nil }

    private func previewRequest(for link: EditorLinkUnderPointer, anchoredAt anchor: CGRect, trigger: LinkPreviewTrigger) -> LinkPreviewRequest {
        LinkPreviewRequest(target: link.target, isWiki: link.isWiki, sourceNote: sourceNote, anchor: anchor, trigger: trigger, source: .editor)
    }

    /// The note link drawn under `windowPoint`, with its frames and the one under the point.
    /// The character before the nearest counts too: the pointer on the right half of a link's
    /// last character is nearest the position after it.
    private func link(at windowPoint: CGPoint, nearCharacter characterIndex: Int?,
                      in surface: some EditorLinkPreviewSurface) -> (link: EditorLinkUnderPointer, frames: [CGRect], anchor: CGRect)? {
        guard let characterIndex else { return nil }
        let source = surface.linkPreviewSource
        for candidateIndex in [characterIndex, characterIndex - 1] {
            guard let link = EditorLinkUnderPointer.link(at: candidateIndex, in: source) else { continue }
            let frames = surface.windowFrames(ofCharacters: link.range)
            if let anchor = frames.first(where: { frame in frame.contains(windowPoint) }) { return (link, frames, anchor) }
        }
        return nil
    }
}
