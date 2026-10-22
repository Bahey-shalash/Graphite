import CoreGraphics
import Foundation
import GraphiteCore

/// The preview cards of the links of a note's reading view: its text says when the pointer
/// comes onto a link and leaves it, and when a link is held (`MarkdownPreview`).
@MainActor
final class ReadingLinkPreviews {
    private var hoveredRequest: LinkPreviewRequest?

    /// The pointer came onto the link to `location`, drawn in `frame` (window coordinates),
    /// written in `sourceNote`.
    func pointerEntered(_ location: URL, frame: CGRect, sourceNote: VaultPath, model: LinkPreviewModel) {
        pointerLeft(model: model)
        guard let request = Self.request(for: location, anchoredAt: frame, trigger: .hover, sourceNote: sourceNote) else { return }
        hoveredRequest = request
        model.pointerEntered(request)
    }

    func pointerLeft(model: LinkPreviewModel) {
        if let hoveredRequest { model.pointerLeft(hoveredRequest) }
        hoveredRequest = nil
    }

    /// The link to `location` was held: its card shows at once.
    func press(_ location: URL, frame: CGRect, sourceNote: VaultPath, model: LinkPreviewModel) {
        guard let request = Self.request(for: location, anchoredAt: frame, trigger: .press, sourceNote: sourceNote) else { return }
        model.show(request)
    }

    /// The card asked for a link the reading view drew (`GraphiteOpenLink`): a link to a note
    /// or file of the vault; nil for a footnote, a web page, or a link no file answers.
    static func request(for location: URL, anchoredAt anchor: CGRect, trigger: LinkPreviewTrigger, sourceNote: VaultPath) -> LinkPreviewRequest? {
        guard let link = GraphiteOpenLink.target(of: location), !GraphiteOpenLink.isUnresolved(location) else { return nil }
        return LinkPreviewRequest(target: link.target, isWiki: link.isWiki, sourceNote: sourceNote, anchor: anchor, trigger: trigger, source: .reading)
    }
}
