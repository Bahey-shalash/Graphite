#if canImport(UIKit)
import UIKit
import PencilKit

/// A PencilKit canvas whose undo history belongs to its document rather than to the canvas.
///
/// PencilKit records its own steps in the canvas's undo manager, aimed at the canvas: they
/// are lost when the canvas is released and would mix documents in a shared window history.
/// This canvas's undo manager records nothing. Its owner compares `recordedDrawing` with each
/// new drawing (`PencilDrawingChange`) and records the change in the document's history,
/// which undo and redo give back through `showDrawingFromHistory`.
class HistoryCanvasView: PKCanvasView {
    /// The drawing as of the last change the history knows, to tell what the next change
    /// removed and added.
    var recordedDrawing = PKDrawing()

    private static let discardingUndoManager: UndoManager = {
        let undoManager = UndoManager()
        undoManager.disableUndoRegistration()
        return undoManager
    }()
    override var undoManager: UndoManager? { Self.discardingUndoManager }

    /// PencilKit's lasso selection is a text input inside the canvas (for Writing Tools), and
    /// a view without an input view of its own uses its ancestor's. This empty one keeps the
    /// keyboard from covering the page when strokes are selected with a finger.
    private let emptyInputView = UIView()
    override var inputView: UIView? { emptyInputView }

    /// Whether the canvas or a view inside it, such as the lasso selection, is first responder.
    var containsFirstResponder: Bool { Self.containsFirstResponder(in: self) }

    private static func containsFirstResponder(in view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains { subview in containsFirstResponder(in: subview) }
    }

    /// Shows a drawing the undo history produced. The canvas reports it like any change,
    /// so what depends on the drawing follows, but it is not recorded as a new step.
    func showDrawingFromHistory(_ drawing: PKDrawing) {
        endLassoSelection()
        recordedDrawing = drawing
        self.drawing = drawing
    }

    /// PencilKit keeps lasso-selected strokes in a view of their own, which would go on
    /// showing them where they were when the drawing changes under it. Changing the tool
    /// ends the selection.
    private func endLassoSelection() {
        guard let lassoTool = tool as? PKLassoTool else { return }
        tool = PKInkingTool(.pen)
        tool = lassoTool
    }

    /// Whether the canvas takes its tool from the floating palette.
    private(set) var followsToolPicker = false
    private var fixedTool: PencilToolSelection?

    /// Gives the canvas its tool: the fixed tool bar's when there is one, else the floating
    /// palette's, whose changes the canvas then follows.
    func takeTool(from toolPicker: PKToolPicker, fixedTool newFixedTool: PencilToolSelection?) {
        if let newFixedTool {
            if followsToolPicker {
                toolPicker.removeObserver(self)
                followsToolPicker = false
            }
            guard newFixedTool != fixedTool else { return }
            fixedTool = newFixedTool
            tool = newFixedTool.tool
            isRulerActive = newFixedTool.isRulerActive
        } else if !followsToolPicker {
            fixedTool = nil
            followsToolPicker = true
            toolPicker.addObserver(self)
            isRulerActive = toolPicker.isRulerActive
            // Observers hear only later changes; start with the tool already selected.
            if #available(iOS 26.0, *), let selectedTool = toolPicker.selectedToolItem.tool {
                tool = selectedTool
            } else {
                (self as PKToolPickerObserver).toolPickerSelectedToolItemDidChange?(toolPicker)
            }
        }
    }

    /// Stops following the palette, before the canvas is released.
    func stopFollowing(_ toolPicker: PKToolPicker) {
        toolPicker.removeObserver(self)
        followsToolPicker = false
    }

    /// True while the canvas shows the shape a stroke became; the change being handled
    /// already includes it.
    private(set) var isShowingRecognizedShape = false

    func showRecognizedShape(_ drawing: PKDrawing) {
        isShowingRecognizedShape = true
        self.drawing = drawing
        isShowingRecognizedShape = false
    }
}

/// Invisible first responder that keeps the tool picker on screen while canvases come and
/// go. Its undo manager is the document's own history, so the picker's Undo and Redo, ⌘Z,
/// and the system undo gestures act on that document only.
///
/// PencilKit makes its lasso selection first responder. The selection is a text input, so
/// it would bring up the typing suggestions, and the picker's Undo and Redo would lose the
/// document's history while strokes are selected. The host takes first responder back; the
/// selection stays, and its menu and dragging work without it.
final class PencilToolPickerHostView: UIView {
    weak var documentUndoManager: UndoManager?
    /// The canvases this host serves, asked when it loses first responder.
    var canvases: () -> [HistoryCanvasView] = { [] }
    /// False while the owner wants the host to give up first responder, as when its document
    /// is no longer the one being worked in.
    var takesFirstResponderBackFromSelections = true

    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { documentUndoManager ?? super.undoManager }
    /// The host never types; without this it would use the input view of a canvas around it.
    override var inputView: UIView? { nil }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        // The next first responder is known only after this call returns.
        if didResign, takesFirstResponderBackFromSelections {
            DispatchQueue.main.async { [weak self] in self?.takeFirstResponderBackFromSelection() }
        }
        return didResign
    }

    private func takeFirstResponderBackFromSelection() {
        guard takesFirstResponderBackFromSelections, window != nil, !isFirstResponder,
              canvases().contains(where: { canvas in canvas.containsFirstResponder }) else { return }
        becomeFirstResponder()
    }
}
#endif
