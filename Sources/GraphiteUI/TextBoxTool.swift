#if canImport(UIKit)
import UIKit
import PencilKit

/// The text tool on one canvas of a PDF page: a tap of Apple Pencil, or of a finger, tells
/// the canvas's owner where it landed, which starts a new text box there or types in the box
/// under it (`PDFTextBoxInteraction`). Like the Read Aloud pen it draws nothing itself, and a
/// drag is not a tap, so fingers still scroll the page and a hand resting on the page while
/// the Pencil writes taps nothing (`CanvasToolTouches`).
@MainActor
final class TextBoxToolController: NSObject, UIGestureRecognizerDelegate {
    private unowned let canvas: HistoryCanvasView
    private lazy var tapRecognizer: ReadAloudPenTapRecognizer = {
        let recognizer = ReadAloudPenTapRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.delegate = self
        return recognizer
    }()

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
    }

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive, tapRecognizer.view == nil { canvas.addGestureRecognizer(tapRecognizer) }
            tapRecognizer.isEnabled = isActive
        }
    }

    /// Every finger and the Pencil can place text, but not a hand resting while the Pencil writes.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !CanvasToolTouches.isHandResting(touch)
    }

    @objc private func handleTap(_ recognizer: ReadAloudPenTapRecognizer) {
        guard recognizer.state == .ended, let window = canvas.window else { return }
        canvas.textToolTapped?(recognizer.location(in: window))
    }
}
#endif
