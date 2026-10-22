import CoreGraphics
import Foundation
import GraphiteCore

extension CommunityPluginHoveredLink {
    /// The card asked for beside `anchor`, a frame in window coordinates. Obsidian's link
    /// text is written as a Wikilink's target is.
    func previewRequest(anchoredAt anchor: CGRect) -> LinkPreviewRequest {
        LinkPreviewRequest(target: linktext, isWiki: true, sourceNote: sourceNote, anchor: anchor, trigger: .hover, source: .plugin)
    }
}

extension CommunityPluginMeasuredRect {
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// The preview cards of plugins' links in live views: the window showing each live view, and
/// the card the runtime's latest hover there asked for, which its end closes.
struct CommunityPluginLiveLinkHovers {
    private struct LinkPreviewsReference {
        weak var linkPreviews: LinkPreviewModel?
    }

    private var linkPreviewsByView: [String: LinkPreviewsReference] = [:]
    private var shownHover: (number: Int, viewIdentifier: String, request: LinkPreviewRequest)?

    func linkPreviews(forView viewIdentifier: String) -> LinkPreviewModel? {
        linkPreviewsByView[viewIdentifier]?.linkPreviews
    }

    mutating func use(_ linkPreviews: LinkPreviewModel?, forView viewIdentifier: String) {
        linkPreviewsByView[viewIdentifier] = linkPreviews.map { model in LinkPreviewsReference(linkPreviews: model) }
    }

    mutating func record(hoverNumber: Int, viewIdentifier: String, request: LinkPreviewRequest) {
        shownHover = (hoverNumber, viewIdentifier, request)
    }

    /// The card of the hover numbered `hoverNumber` and its window's cards, which no longer
    /// show it; nil for an earlier hover.
    mutating func endHover(numbered hoverNumber: Int) -> (request: LinkPreviewRequest, linkPreviews: LinkPreviewModel?)? {
        guard let shownHover, shownHover.number == hoverNumber else { return nil }
        self.shownHover = nil
        return (shownHover.request, linkPreviews(forView: shownHover.viewIdentifier))
    }
}

/// Obsidian's `hover-link` between Graphite and plugins: Graphite's own hovers on links in
/// notes reach plugins that listen, and a link a plugin asks to preview in a live view shows
/// the card of the window showing it. Copies of blocks and views show the links plugins ask
/// for there themselves (`CommunityPluginCopyLinkPreviews`).
extension CommunityPluginHost {
    /// How long telling plugins of a hover may take before it is given up.
    static let linkHoverAnnouncementTimeout: Duration = .seconds(2)

    /// The pointer rests on a link in one of Graphite's notes: plugins listening for
    /// `hover-link` hear it as Obsidian's editor or reading view sends it.
    func announceLinkHover(_ request: LinkPreviewRequest) {
        guard isRuntimeRunning, hasHoverLinkListeners, let source = request.source.obsidianSourceName else { return }
        let message = ["operation": "hoverLink.hovered", "linktext": request.target, "sourcePath": request.sourceNote.rawValue, "source": source]
        Task { _ = try? await send(message, timeout: Self.linkHoverAnnouncementTimeout) } // A plugin that misses one hover misses nothing else.
    }

    /// The window showing the live view `viewIdentifier` shows its plugins' links with
    /// `linkPreviews`; nil while Page Preview is off there, or once the view is gone.
    func useLinkPreviews(_ linkPreviews: LinkPreviewModel?, forLiveView viewIdentifier: String) {
        liveLinkHovers.use(linkPreviews, forView: viewIdentifier)
    }

    /// A plugin asked to preview a link in the view shown live (`hoverLink.show`): the card
    /// shows beside its element, which the runtime measured in its page.
    func showLinkHoveredInLiveView(_ hover: CommunityPluginLiveLinkHover?) {
        guard let hover, hover.leafIdentifier == liveViewIdentifier, let linkPreviews = liveLinkHovers.linkPreviews(forView: hover.leafIdentifier),
              let anchor = windowFrame(ofPageFrame: hover.rect.frame) else { return }
        let request = hover.link.previewRequest(anchoredAt: anchor)
        liveLinkHovers.record(hoverNumber: hover.hoverNumber, viewIdentifier: hover.leafIdentifier, request: request)
        linkPreviews.pointerEntered(request)
    }

    /// The pointer left the element of the live view's hover numbered `hoverNumber` (`hoverLink.end`).
    func endLinkHoverInLiveView(numbered hoverNumber: Int?) {
        guard let hoverNumber, let ended = liveLinkHovers.endHover(numbered: hoverNumber) else { return }
        ended.linkPreviews?.pointerLeft(ended.request)
    }
}
