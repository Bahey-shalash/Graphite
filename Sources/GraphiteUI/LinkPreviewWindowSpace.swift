import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Turns a link's frame in its window's own coordinates, which every surface reports with
/// `convert(_:to: nil)`, into the coordinates of the view the cards are drawn in. The view
/// does the conversion itself, so the window's title bar, toolbar and safe areas count as
/// they are on each platform.
@MainActor
final class LinkPreviewWindowSpace {
    /// The view under the cards, filling the same frame.
    fileprivate weak var overlayView: LinkPreviewWindowSpaceView?

    /// `windowRect` in the cards' view; nil while that view is in no window.
    func overlayRect(fromWindowRect windowRect: CGRect) -> CGRect? {
        guard let overlayView, overlayView.window != nil else { return nil }
        return overlayView.convert(windowRect, from: nil)
    }
}

#if canImport(UIKit)
/// An empty view filling the cards' frame, which never takes a touch.
final class LinkPreviewWindowSpaceView: UIView {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
}

/// Puts a `LinkPreviewWindowSpaceView` under the cards and gives it to `space`.
struct LinkPreviewWindowSpaceReader: UIViewRepresentable {
    let space: LinkPreviewWindowSpace

    func makeUIView(context: Context) -> LinkPreviewWindowSpaceView {
        let view = LinkPreviewWindowSpaceView()
        view.isUserInteractionEnabled = false
        space.overlayView = view
        return view
    }

    func updateUIView(_ view: LinkPreviewWindowSpaceView, context: Context) {}
}
#else
/// An empty view filling the cards' frame, which never takes a click. Flipped, as SwiftUI's
/// coordinates are, so a converted frame's origin is its top left corner.
final class LinkPreviewWindowSpaceView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Puts a `LinkPreviewWindowSpaceView` under the cards and gives it to `space`.
struct LinkPreviewWindowSpaceReader: NSViewRepresentable {
    let space: LinkPreviewWindowSpace

    func makeNSView(context: Context) -> LinkPreviewWindowSpaceView {
        let view = LinkPreviewWindowSpaceView()
        space.overlayView = view
        return view
    }

    func updateNSView(_ view: LinkPreviewWindowSpaceView, context: Context) {}
}
#endif
