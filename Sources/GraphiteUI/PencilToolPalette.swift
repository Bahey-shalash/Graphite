#if canImport(UIKit)
import UIKit
import PencilKit

/// The Pencil palette every canvas uses: PDF pages, embedded PDFs, and the drawing editor.
///
/// It is the system's own tool picker, so it has every tool Apple Notes has (pen, fine
/// liner, marker, pencil, crayon, fountain pen, reed pen, watercolor, eraser, lasso, ruler)
/// and keeps each tool's color and width, and the tool in use, across canvases and
/// launches. Graphite adds one button at its end, whose menu has Favorite Colors, which
/// gives the tool in use one of the colors of Settings › Colors, the list the notes'
/// Format › Color menu uses; Draw Shapes, which turns the shape tool on and off
/// (`PencilShapes`); and Select Ink, which turns on Graphite's lasso (`InkSelectionController`).
@MainActor
enum PencilToolPalette {
    /// Whether strokes become the shapes they were meant to be; shared by every canvas.
    static let drawsShapesPreferenceKey = PDFAnnotationPreferenceKey.drawsShapes

    static func makeToolPicker() -> PKToolPicker {
        let toolPicker = PKToolPicker()
        // Graphite's own Draw with Finger settings decide finger input.
        toolPicker.showsDrawingPolicyControls = false
        // Colors are chosen for white paper in every appearance.
        toolPicker.colorUserInterfaceStyle = .light
        // Choosing any tool puts Graphite's lasso away.
        toolPicker.addObserver(PaletteToolChoiceObserver.shared)
        return toolPicker
    }

    static var drawsShapes: Bool { UserDefaults.standard.bool(forKey: drawsShapesPreferenceKey) }

    // MARK: Accessory button

    /// The button at the end of the palette, for `toolPicker.accessoryItem`. Its menu has
    /// the favorite colors and the Draw Shapes switch: the palette leaves its accessory the
    /// room of one button, in whichever direction it is docked.
    ///
    /// A button of its own rather than a plain bar item: the palette would fill a selected
    /// item with the system's blue, the one color in a row of neutral buttons.
    static func makeAccessoryItem(for toolPicker: PKToolPicker) -> UIBarButtonItem {
        let button = PaletteAccessoryButton(configuration: .plain())
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: accessoryButtonSize),
            button.heightAnchor.constraint(equalToConstant: accessoryButtonSize),
        ])
        // While Graphite's lasso or the shape tool is on the button shows it, inverted like
        // the pen in use; otherwise it is the colors button.
        button.configurationUpdateHandler = { button in
            let selectsInk = PaletteInkSelection.isOn
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: selectsInk ? "lasso" : button.isSelected ? "square.fill.on.circle.fill" : "swatchpalette")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = selectsInk || button.isSelected ? .systemBackground : .label
            configuration.background.backgroundColor = selectsInk || button.isSelected ? .label : .tertiarySystemFill
            button.configuration = configuration
        }
        button.accessibilityLabel = "Colors, Shapes and Selection"
        button.accessibilityHint = "Gives the pen in use one of your colors, turns strokes into shapes, or selects ink to move, resize and recolor"
        button.showsLargeContentViewer = true
        button.largeContentTitle = "Colors, Shapes and Selection"
        button.showsMenuAsPrimaryAction = true
        // Read each time the menu opens: the colors, the tool in use and the switches change.
        button.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak toolPicker] provideElements in
                provideElements(toolPicker.map { toolPicker in menuElements(for: toolPicker) } ?? [])
            },
        ])
        let item = UIBarButtonItem(customView: button)
        updateShapesButton(item, isOn: drawsShapes)
        return item
    }

    /// The size of the palette's own round buttons.
    private static let accessoryButtonSize: CGFloat = 36

    /// Shows whether the shape tool is on by the button's symbol and fill, not by color alone.
    static func updateShapesButton(_ item: UIBarButtonItem, isOn: Bool) {
        guard let button = item.customView as? UIButton else { return }
        button.isSelected = isOn
        button.accessibilityValue = (isOn ? "Shapes on" : "Shapes off") + (PaletteInkSelection.isOn ? ", selecting ink" : "")
    }

    /// Favorite colors as a row of swatches, then the Draw Shapes switch.
    static func menuElements(for toolPicker: PKToolPicker, palette: [PaletteColor] = GraphitePreferences.storedColorPalette()) -> [UIMenuElement] {
        let shapesAction = UIAction(title: "Draw Shapes", image: UIImage(systemName: "square.on.circle"),
                                    state: drawsShapes ? .on : .off) { _ in
            UserDefaults.standard.set(!drawsShapes, forKey: drawsShapesPreferenceKey)
        }
        let selectionAction = UIAction(title: "Select Ink", subtitle: "Move, resize or recolor", image: UIImage(systemName: "lasso"),
                                       state: PaletteInkSelection.isOn ? .on : .off) { _ in
            PaletteInkSelection.isOn.toggle()
        }
        return [favoriteColorsMenu(for: toolPicker, palette: palette), UIMenu(options: .displayInline, children: [shapesAction, selectionAction])]
    }

    // MARK: Favorite colors

    /// The colors of Settings › Colors, the list the notes' Format › Color menu uses.
    static func favoriteColorsMenu(for toolPicker: PKToolPicker, palette: [PaletteColor]) -> UIMenu {
        let colorInUse = inkingToolInUse(of: toolPicker).flatMap { tool in tool.color.graphiteHexWithoutOpacity }
        let swatches = palette.compactMap { favorite -> UIAction? in
            guard let color = UIColor(graphiteHex: favorite.hex) else { return nil }
            let swatch = UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
            let action = UIAction(title: favorite.name, image: swatch) { [weak toolPicker] _ in
                if let toolPicker { applyColor(color, to: toolPicker) }
            }
            action.state = colorInUse == color.graphiteHexWithoutOpacity ? .on : .off
            // The eraser, the lasso and the ruler take no color.
            if colorInUse == nil { action.attributes = .disabled }
            return action
        }
        guard !swatches.isEmpty else {
            return UIMenu(options: .displayInline, children: [UIAction(title: "Add colors in Settings › Colors", attributes: .disabled) { _ in }])
        }
        return UIMenu(title: "Favorite Colors", options: [.displayInline, .displayAsPalette], children: swatches)
    }

    static func inkingToolInUse(of toolPicker: PKToolPicker) -> PKInkingTool? {
        (toolPicker.selectedToolItem as? PKToolPickerInkingItem)?.inkingTool
    }

    /// Gives the tool in use the color, keeping its kind, width, opacity, and nib angle.
    static func applyColor(_ color: UIColor, to toolPicker: PKToolPicker) {
        guard let toolInUse = inkingToolInUse(of: toolPicker) else { return }
        let colorAtToolOpacity = color.withAlphaComponent(toolInUse.color.cgColor.alpha)
        let recoloredTool: PKInkingTool
        if #available(iOS 26.0, *) {
            recoloredTool = PKInkingTool(toolInUse.inkType, color: colorAtToolOpacity, width: toolInUse.width, azimuth: toolInUse.azimuth)
        } else {
            recoloredTool = PKInkingTool(toolInUse.inkType, color: colorAtToolOpacity, width: toolInUse.width)
        }
        var selection: any SelectedToolSetting = toolPicker
        selection.selectedTool = recoloredTool
    }
}

/// The palette's accessory button, which also shows whether Graphite's lasso is on.
private final class PaletteAccessoryButton: UIButton {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: PaletteInkSelection.didChange, object: nil)
        guard window != nil else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(inkSelectionDidChange), name: PaletteInkSelection.didChange, object: nil)
        setNeedsUpdateConfiguration()
    }

    @objc private func inkSelectionDidChange() {
        setNeedsUpdateConfiguration()
        accessibilityValue = (isSelected ? "Shapes on" : "Shapes off") + (PaletteInkSelection.isOn ? ", selecting ink" : "")
    }
}

/// Hears every palette's tool choices. PencilKit keeps its observers weakly, so one shared
/// observer serves all palettes.
private final class PaletteToolChoiceObserver: NSObject, PKToolPickerObserver {
    static let shared = PaletteToolChoiceObserver()

    func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
        PaletteInkSelection.isOn = false
    }
}

/// `PKToolPicker.selectedTool` is deprecated in favor of tool items, but setting it is the
/// only way PencilKit offers to change the color of the item in use; setting
/// `selectedToolItem` only selects. Going through this protocol keeps the one deliberate
/// use from warning on every build.
private protocol SelectedToolSetting: AnyObject {
    var selectedTool: any PKTool { get set }
}
extension PKToolPicker: SelectedToolSetting {}

private extension UIColor {
    /// The color as `#rrggbb` in sRGB, to compare a tool's color with a favorite.
    var graphiteHexWithoutOpacity: String? {
        guard let components = cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return nil }
        let bytes = components.prefix(3).map { component in Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", bytes[0], bytes[1], bytes[2])
    }
}
#endif
