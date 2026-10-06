#if canImport(UIKit)
import SwiftUI
import UIKit

/// What a double tap or a squeeze of Apple Pencil does while the fixed tool bar is on
/// screen. Apple's palette answers them itself; the fixed bar takes the palette's place,
/// so it answers them, as the person chose in Settings › Apple Pencil.
enum PencilGestureResponse: Equatable {
    case switchToEraser, switchToPreviousTool, showPalette, none

    init(preferredAction: UIPencilPreferredAction) {
        switch preferredAction {
        case .switchEraser: self = .switchToEraser
        case .switchPrevious: self = .switchToPreviousTool
        case .showColorPalette, .showInkAttributes, .showContextualPalette: self = .showPalette
        // Nothing, a shortcut the system runs itself, or an action of a later system.
        default: self = .none
        }
    }
}

/// Receives Apple Pencil's double tap and squeeze for the fixed bar it sits behind.
struct PencilGestureReceiver: UIViewRepresentable {
    let toolbox: PencilToolbox
    let favoriteColors: [PaletteColor]
    let undoAvailability: UndoAvailability?

    func makeUIView(context: Context) -> PencilGestureReceiverView { PencilGestureReceiverView() }

    func updateUIView(_ receiver: PencilGestureReceiverView, context: Context) {
        receiver.toolbox = toolbox
        receiver.favoriteColors = favoriteColors
        receiver.undoAvailability = undoAvailability
    }
}

final class PencilGestureReceiverView: UIView, UIPencilInteractionDelegate {
    var toolbox: PencilToolbox?
    var favoriteColors: [PaletteColor] = []
    var undoAvailability: UndoAvailability?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addInteraction(UIPencilInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError("PencilGestureReceiverView is created in code.") }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        respond(PencilGestureResponse(preferredAction: UIPencilInteraction.preferredTapAction), at: tap.timestamp, hoverLocation: tap.hoverPose?.location)
    }

    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        // Answered once the squeeze ends, as Apple's palette answers it.
        guard squeeze.phase == .ended else { return }
        respond(PencilGestureResponse(preferredAction: UIPencilInteraction.preferredSqueezeAction), at: squeeze.timestamp,
                hoverLocation: squeeze.hoverPose?.location)
    }

    /// Answers a gesture made at `timestamp`; `hoverLocation` is where the Pencil's tip
    /// hovered, in this view's coordinates, when it hovered at all.
    func respond(_ response: PencilGestureResponse, at timestamp: TimeInterval, hoverLocation: CGPoint?) {
        guard let toolbox, toolbox.acceptsPencilGesture(at: timestamp) else { return }
        switch response {
        case .switchToEraser: toolbox.switchToEraser()
        case .switchToPreviousTool: toolbox.switchToPreviousTool()
        case .showPalette: togglePalette(at: hoverLocation)
        case .none: break
        }
    }

    /// Shows the palette at the Pencil's tip, or under the bar when the Pencil does not
    /// hover; a second gesture closes it.
    private func togglePalette(at hoverLocation: CGPoint?) {
        guard let toolbox, var presenter = window?.rootViewController else { return }
        while let presentedController = presenter.presentedViewController {
            if presentedController is PencilPaletteController {
                presentedController.dismiss(animated: true)
                return
            }
            presenter = presentedController
        }
        let palette = PencilPaletteController(toolbox: toolbox, favoriteColors: favoriteColors, undoAvailability: undoAvailability)
        palette.modalPresentationStyle = .popover
        if let popover = palette.popoverPresentationController {
            popover.sourceView = self
            popover.sourceRect = hoverLocation.map { location in CGRect(origin: location, size: .zero) }
                ?? CGRect(x: bounds.midX, y: bounds.maxY, width: 0, height: 0)
            popover.permittedArrowDirections = hoverLocation == nil ? .up : .any
        }
        presenter.present(palette, animated: true)
    }
}

/// The palette Apple Pencil's squeeze opens where the Pencil is: the bar's inks, eraser and
/// lasso, the sizes and colors of the tool in use, and Undo and Redo. Choosing a tool, a
/// size or a color closes it.
final class PencilPaletteController: UIHostingController<PencilPalette> {
    init(toolbox: PencilToolbox, favoriteColors: [PaletteColor], undoAvailability: UndoAvailability?) {
        super.init(rootView: PencilPalette(toolbox: toolbox, favoriteColors: favoriteColors, undoAvailability: undoAvailability, close: {}))
        rootView = PencilPalette(toolbox: toolbox, favoriteColors: favoriteColors, undoAvailability: undoAvailability) { [weak self] in
            self?.dismiss(animated: true)
        }
        sizingOptions = .preferredContentSize
    }

    required init?(coder: NSCoder) { fatalError("PencilPaletteController is created in code.") }
}

struct PencilPalette: View {
    let toolbox: PencilToolbox
    let favoriteColors: [PaletteColor]
    let undoAvailability: UndoAvailability?
    let close: () -> Void

    var body: some View {
        let buttons = PencilToolButtons(toolbox: toolbox, rowHeight: PencilToolbarMetrics.buttonSide + 4)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                ForEach(Array(toolbox.presets.enumerated()), id: \.element.id) { presetIndex, preset in
                    buttons.presetButton(preset, at: presetIndex, tapOnPresetInUse: close)
                }
                buttons.toolButton(.eraser)
                buttons.toolButton(.lasso)
            }
            // The tools stand on a line, as on the bar.
            .overlay(alignment: .bottom) { Hairline() }
            if toolbox.toolInUse == .ink {
                HStack(spacing: 2) {
                    ForEach(Array(toolbox.presetInUse.ink.widthChoices.enumerated()), id: \.offset) { choiceIndex, width in
                        buttons.sizeButton(choiceIndex: choiceIndex, isChosen: toolbox.presetInUse.width == width) { toolbox.chooseWidth(width) }
                    }
                    Hairline(axis: .vertical).frame(height: 20).padding(.horizontal, 6)
                    buttons.colorButton(name: "black", hex: PencilInk.pen.defaultColorHex)
                    ForEach(favoriteColors.prefix(6)) { favorite in buttons.colorButton(name: favorite.name, hex: favorite.hex) }
                }
            }
            if let undoAvailability {
                HStack(spacing: 18) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undoAvailability.undo() }
                        .disabled(!undoAvailability.canUndo)
                    Button("Redo", systemImage: "arrow.uturn.forward") { undoAvailability.redo() }
                        .disabled(!undoAvailability.canRedo)
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 17))
                .padding(.horizontal, 10)
                .frame(height: 36)
            }
        }
        .padding(10)
        .tint(.primary)
        .onChange(of: toolbox.selection) { _, _ in close() }
    }
}
#endif
