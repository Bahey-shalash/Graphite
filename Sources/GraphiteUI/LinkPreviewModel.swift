import CoreGraphics
import Foundation
import Observation
import GraphiteCore

/// How a preview card was asked for, which decides when it shows and what closes it.
enum LinkPreviewTrigger: Equatable, Sendable {
    /// The pointer of a mouse or trackpad, or Apple Pencil hovering, rests on the link: the
    /// card shows after `LinkPreviewModel.showDelay`, and goes once the pointer has been off
    /// both the link and the card for `LinkPreviewModel.hideDelay`.
    case hover
    /// A long press on the link: the card shows at once and stays until it is closed.
    case press
}

/// A link a preview card is asked for, and where it is on screen.
struct LinkPreviewRequest: Equatable, Sendable {
    /// The link as written: a Wikilink's target or a Markdown link's destination, with its
    /// `#heading` or `#^block`, or a plugin's link text.
    let target: String
    let isWiki: Bool
    /// The note the link is written in, which a relative target starts from; the vault's
    /// root for a plugin's link that names none.
    let sourceNote: VaultPath
    /// The link's frame in the window's own coordinates, as `convert(_:to: nil)` gives them
    /// on the platform; the card is placed beside it.
    let anchor: CGRect
    let trigger: LinkPreviewTrigger
}

/// Where a preview card stands: one link at a time.
enum LinkPreviewPhase {
    case hidden
    /// The pointer rests on a link: the delay runs out, then the link's note is read.
    case waiting(LinkPreviewRequest)
    case shown(LinkPreviewRequest, LinkPreviewContent)

    var request: LinkPreviewRequest? {
        switch self {
        case .hidden: nil
        case .waiting(let request), .shown(let request, _): request
        }
    }
}

/// The preview cards of one window, as Obsidian's core plugin Page Preview shows them: the
/// editor, the reading view and plugins say where the pointer rests or what was held, and
/// the model decides when the card shows and closes. Exists only while Page Preview is on.
@MainActor @Observable
final class LinkPreviewModel {
    /// Where the pointer is, for a card shown by hovering.
    private enum PointerPlace { case onLink, onCard, away }

    /// How long the pointer rests on a link before its card shows.
    static let showDelay: Duration = .milliseconds(300)
    /// How long the pointer may be off both the link and its card before the card closes,
    /// which leaves time to move from one to the other.
    static let hideDelay: Duration = .milliseconds(300)

    private(set) var phase: LinkPreviewPhase = .hidden
    @ObservationIgnored private var pointer = PointerPlace.away
    @ObservationIgnored private var reading: LinkPreviewReading?
    @ObservationIgnored private let clock: any ApplicationClock
    /// The one wait at a time: the delay and the reading before a card shows, or the delay
    /// before it closes.
    @ObservationIgnored private var wait: Task<Void, Never>?

    init(clock: any ApplicationClock) {
        self.clock = clock
    }

    /// Notes are read from `reading` from now on; without one no card shows.
    func useReading(_ reading: LinkPreviewReading?) {
        self.reading = reading
        if reading == nil { close() }
    }

    /// The pointer came to rest on a link: its card shows after `showDelay`, unless the
    /// pointer leaves first. Back on the link of the card shown, the card stays.
    func pointerEntered(_ request: LinkPreviewRequest) {
        pointer = .onLink
        if let current = phase.request, current == request {
            if case .shown = phase { stopWaiting() }
            return
        }
        start(request, after: Self.showDelay)
    }

    /// The pointer left the link `request` was made for: a card not shown yet does not
    /// show, and one shown closes after `hideDelay` unless the pointer reaches it.
    func pointerLeft(_ request: LinkPreviewRequest) {
        guard request.trigger == .hover, phase.request == request, pointer == .onLink else { return }
        pointer = .away
        switch phase {
        case .hidden: break
        case .waiting: close()
        case .shown: closeAfterHideDelay()
        }
    }

    func pointerEnteredCard() {
        guard case .shown = phase else { return }
        pointer = .onCard
        stopWaiting()
    }

    func pointerLeftCard() {
        guard case .shown(let request, _) = phase, request.trigger == .hover, pointer == .onCard else { return }
        pointer = .away
        closeAfterHideDelay()
    }

    /// A link was held: its card shows as soon as its note is read.
    func show(_ request: LinkPreviewRequest) {
        pointer = .away
        start(request, after: .zero)
    }

    /// Closes the card, or stops one from showing: Escape, the close button, a tap
    /// elsewhere, a link followed, the note typed in or scrolled.
    func close() {
        stopWaiting()
        pointer = .away
        phase = .hidden
    }

    private func start(_ request: LinkPreviewRequest, after delay: Duration) {
        stopWaiting()
        phase = .waiting(request)
        wait = Task { [weak self, clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard let self, let reading = self.reading else { return }
            let content = await reading.content(for: request)
            guard !Task.isCancelled, case .waiting(let waitingRequest) = self.phase, waitingRequest == request else { return }
            self.wait = nil
            self.phase = content.map { content in .shown(request, content) } ?? .hidden
        }
    }

    private func closeAfterHideDelay() {
        stopWaiting()
        wait = Task { [weak self, clock] in
            do { try await clock.sleep(for: Self.hideDelay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.wait = nil
            self.phase = .hidden
        }
    }

    private func stopWaiting() {
        wait?.cancel()
        wait = nil
    }
}
