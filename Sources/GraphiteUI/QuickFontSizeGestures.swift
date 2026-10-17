import SwiftUI
#if canImport(UIKit)
import UIKit
import PencilKit
import PDFKit
#else
import AppKit
#endif

/// Obsidian's "Quick font size adjustment" for one note: what a pinch over the note, or
/// Control-scrolling on a Mac, reads and changes. Nil where the setting is off.
struct QuickFontSizeAdjustment {
    /// The vault's font size now.
    let currentSize: () -> Int
    /// Sets the vault's font size; notes restyle at once and the file is written once the
    /// size rests.
    let setSize: (Int) -> Void
}

/// Follows one pinch from the size it started at, so the size tracks the fingers instead
/// of compounding each step.
struct QuickFontSizePinchProgress {
    private var startingSize: Int?

    mutating func begin(at size: Int) { startingSize = size }

    /// The size for the pinch's current scale, or nil when the pinch did not begin here.
    func size(forScale scale: CGFloat) -> Int? {
        startingSize.map { startingSize in NoteFontSize.size(afterPinchingBy: scale, from: startingSize) }
    }

    mutating func end() { startingSize = nil }
}

#if canImport(UIKit)
/// Which touches a quick font size pinch takes. Apple Pencil never takes part, so writing or
/// drawing with Pencil while a finger rests on the screen cannot resize the text, and a
/// pinch that starts on a view zooming by itself (an embedded PDF, a drawing canvas, a
/// canvas board, a picture viewer) is left to that view.
enum QuickFontSizePinchPolicy {
    /// Fingers and the trackpad; not Apple Pencil.
    static let allowedTouchTypes: [NSNumber] = [UITouch.TouchType.direct, .indirectPointer].map { touchType in NSNumber(value: touchType.rawValue) }

    @MainActor static func acceptsTouch(ofType touchType: UITouch.TouchType, in touchedView: UIView?, under hostView: UIView?, recognizer: UIGestureRecognizer) -> Bool {
        guard touchType != .pencil else { return false }
        var view = touchedView
        while let currentView = view, currentView !== hostView {
            if currentView is PKCanvasView || currentView is PDFView { return false }
            if let scrollView = currentView as? UIScrollView, scrollView.maximumZoomScale > scrollView.minimumZoomScale { return false }
            let hasOwnPinch = currentView.gestureRecognizers?.contains { otherRecognizer in
                otherRecognizer !== recognizer && otherRecognizer.isEnabled && otherRecognizer is UIPinchGestureRecognizer
            } ?? false
            if hasOwnPinch { return false }
            view = currentView.superview
        }
        return true
    }
}

/// A pinch over a note that changes the vault's font size. It recognizes alongside
/// scrolling and never cancels the touches of the views under it.
final class QuickFontSizePinchRecognizer: UIPinchGestureRecognizer, UIGestureRecognizerDelegate {
    var adjustment: QuickFontSizeAdjustment? {
        didSet { isEnabled = adjustment != nil }
    }
    private var progress = QuickFontSizePinchProgress()

    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handlePinch))
        allowedTouchTypes = QuickFontSizePinchPolicy.allowedTouchTypes
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delegate = self
        isEnabled = false
    }

    @objc private func handlePinch() {
        guard let adjustment else { return }
        switch state {
        case .began:
            progress.begin(at: adjustment.currentSize())
        case .changed:
            if let size = progress.size(forScale: scale), size != adjustment.currentSize() { adjustment.setSize(size) }
        default:
            progress.end()
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        QuickFontSizePinchPolicy.acceptsTouch(ofType: touch.type, in: touch.view, under: view, recognizer: self)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

/// The quick font size pinch over SwiftUI content, such as the reading view.
struct QuickFontSizePinchGesture: UIGestureRecognizerRepresentable {
    let adjustment: QuickFontSizeAdjustment?

    func makeUIGestureRecognizer(context: Context) -> QuickFontSizePinchRecognizer {
        let recognizer = QuickFontSizePinchRecognizer()
        recognizer.adjustment = adjustment
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: QuickFontSizePinchRecognizer, context: Context) {
        recognizer.adjustment = adjustment
    }
}
#else
/// Control-scrolling and trackpad pinches over a note on a Mac, as in Obsidian on a desktop.
/// Scrolling changes the size by one step at most every half second, as Obsidian does.
struct QuickFontSizeMacInput {
    static let scrollStepInterval: TimeInterval = 0.5
    private var lastScrollStep = Date.distantPast
    private var progress = QuickFontSizePinchProgress()
    private var magnification: CGFloat = 0

    /// Handles a scroll event; true when it changed the size and should not scroll.
    mutating func handleScroll(_ event: NSEvent, adjustment: QuickFontSizeAdjustment?) -> Bool {
        guard let adjustment, event.modifierFlags.contains(.control), event.scrollingDeltaY != 0 else { return false }
        let now = Date()
        if now.timeIntervalSince(lastScrollStep) >= Self.scrollStepInterval {
            lastScrollStep = now
            adjustment.setSize(NoteFontSize.clamped(adjustment.currentSize() + (event.scrollingDeltaY > 0 ? 1 : -1)))
        }
        return true
    }

    /// Handles a trackpad pinch; true when it was taken.
    mutating func handleMagnify(_ event: NSEvent, adjustment: QuickFontSizeAdjustment?) -> Bool {
        guard let adjustment else { return false }
        switch event.phase {
        case .began:
            magnification = 0
            progress.begin(at: adjustment.currentSize())
        case .changed:
            magnification += event.magnification
            if let size = progress.size(forScale: 1 + magnification), size != adjustment.currentSize() { adjustment.setSize(size) }
        default:
            progress.end()
        }
        return true
    }
}
#endif

/// The quick font size pinch over a note shown by SwiftUI, such as the reading view. The
/// gesture stays attached while quick adjustment is off and does nothing then, so turning
/// the setting on or off never rebuilds the note.
struct QuickFontSizePinchModifier: ViewModifier {
    let adjustment: QuickFontSizeAdjustment?
    #if os(macOS)
    @State private var progress = QuickFontSizePinchProgress()
    @State private var isPinching = false
    #endif

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.gesture(QuickFontSizePinchGesture(adjustment: adjustment))
        #else
        content.simultaneousGesture(MagnifyGesture()
            .onChanged { value in
                guard let adjustment else { return }
                if !isPinching { isPinching = true; progress.begin(at: adjustment.currentSize()) }
                if let size = progress.size(forScale: value.magnification), size != adjustment.currentSize() { adjustment.setSize(size) }
            }
            .onEnded { _ in isPinching = false; progress.end() },
            including: adjustment == nil ? .subviews : .all)
        #endif
    }
}
