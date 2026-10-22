import SwiftUI
import GraphiteCore

extension EnvironmentValues {
    /// The window's preview cards, which the editor, the reading view and plugins' copies tell
    /// where the pointer rests on a link; nil while Page Preview is off, and then nothing
    /// watches the pointer for it.
    @Entry var linkPreviews: LinkPreviewModel? = nil
}

/// What a preview card's own links and buttons do.
struct LinkPreviewActions {
    /// Follows a link from the note it is written in, as a tap on it in the note would.
    let follow: (_ target: String, _ isWiki: Bool, _ source: VaultPath) -> Void
    /// Opens a PDF a card embeds at a page (zero-based).
    let openPDF: (_ path: VaultPath, _ pageIndex: Int) -> Void
}

/// What preview cards need from the window's vault.
struct LinkPreviewVault {
    /// The clock the cards' delays run on.
    let clock: any ApplicationClock
    /// The open vault's notes as cards read them at a text size; nil while no vault is open.
    let reading: @MainActor (DynamicTypeSize) -> LinkPreviewReading?
    let actions: LinkPreviewActions
    /// Tells community plugins listening for `hover-link` of a link the pointer rests on in a note.
    let announceHover: (LinkPreviewRequest) -> Void
}

/// Preview cards over a window, while the core plugin Page Preview is on: the window's
/// `LinkPreviewModel` in the environment, and the card it shows drawn above everything else.
struct LinkPreviewLayer: ViewModifier {
    let isEnabled: Bool
    let vault: LinkPreviewVault
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: LinkPreviewModel?

    func body(content: Content) -> some View {
        // Read here rather than by the window's root view, which then does not draw again
        // each time the index changes.
        let currentReading = vault.reading(dynamicTypeSize)
        content
            .environment(\.linkPreviews, model)
            .overlay {
                if let model, let currentReading {
                    LinkPreviewOverlay(model: model, root: currentReading.vault.root, textSize: currentReading.configuration.textSize, actions: vault.actions)
                }
            }
            .onChange(of: isEnabled, initial: true) { _, isEnabled in
                model?.close()
                model = isEnabled ? LinkPreviewModel(clock: vault.clock, announceHover: vault.announceHover) : nil
                model?.useReading(currentReading)
            }
            .onChange(of: currentReading) { _, newReading in model?.useReading(newReading) }
    }
}

/// The card a window's `LinkPreviewModel` shows, beside its link. Only the card takes
/// touches and clicks, and, for a card shown by a long press, a tap anywhere else closes it.
private struct LinkPreviewOverlay: View {
    let model: LinkPreviewModel
    let root: URL
    let textSize: Double
    let actions: LinkPreviewActions
    @State private var windowSpace = LinkPreviewWindowSpace()
    /// The height of the card shown with nothing cut, once measured; it is drawn only then,
    /// in its place.
    @State private var naturalCardHeight: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            if case .shown(let request, let content) = model.phase, let anchor = windowSpace.overlayRect(fromWindowRect: request.anchor) {
                let frame = LinkPreviewPlacement.frame(beside: anchor, naturalHeight: naturalCardHeight ?? LinkPreviewPlacement.maximumHeightPoints,
                                                       in: proxy.size)
                ZStack(alignment: .topLeading) {
                    if request.trigger == .press {
                        Color.clear.contentShape(Rectangle()).onTapGesture { model.close() }
                    }
                    LinkPreviewCard(request: request, content: content, root: root, textSize: textSize, actions: actions, model: model) { height in
                        naturalCardHeight = height
                    }
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(naturalCardHeight == nil ? 0 : 1)
                }
            }
        }
        .background(LinkPreviewWindowSpaceReader(space: windowSpace))
        .onChange(of: model.phase.request) { naturalCardHeight = nil }
    }
}
