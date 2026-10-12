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
/// (`PencilShapes`); Select Ink, which turns on Graphite's lasso (`InkSelectionController`),
/// with its type, freehand or rectangular; and the laser pointer (`LaserPointerController`),
/// with its dot or line.
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
            let selectsInk = PaletteInkSelection.isOn, pointsWithLaser = PaletteInkSelection.pointsWithLaser
            let isInverted = selectsInk || pointsWithLaser || button.isSelected
            var configuration = UIButton.Configuration.plain()
            let symbolName = selectsInk ? LassoShape.stored.symbolName : button.isSelected ? "square.fill.on.circle.fill" : "swatchpalette"
            configuration.image = pointsWithLaser ? LaserPointerGlyph.templateImage() : UIImage(systemName: symbolName)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = isInverted ? .systemBackground : .label
            configuration.background.backgroundColor = isInverted ? .label : .tertiarySystemFill
            button.configuration = configuration
        }
        button.accessibilityLabel = "Colors, Shapes, Selection and Laser"
        button.accessibilityHint = "Gives the pen in use one of your colors, turns strokes into shapes, selects ink and images to move, resize or capture, or points with a laser"
        button.showsLargeContentViewer = true
        button.largeContentTitle = "Colors, Shapes, Selection and Laser"
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
        button.accessibilityValue = accessibilityValue(shapesAreOn: isOn)
    }

    /// Whether shapes are on, and the tool of Graphite's that is in use.
    static func accessibilityValue(shapesAreOn: Bool) -> String {
        (shapesAreOn ? "Shapes on" : "Shapes off") + (PaletteInkSelection.isOn ? ", selecting ink" : PaletteInkSelection.pointsWithLaser ? ", laser pointer" : "")
    }

    /// Favorite colors as a row of swatches, or the highlighter's own colors while the marker
    /// is in use, then the Draw Shapes switch.
    static func menuElements(for toolPicker: PKToolPicker, palette: [PaletteColor] = GraphitePreferences.storedColorPalette(),
                             highlighterPalette: [PaletteColor] = GraphitePreferences.storedHighlighterPalette()) -> [UIMenuElement] {
        let shapesAction = UIAction(title: "Draw Shapes", image: UIImage(systemName: "square.on.circle"),
                                    state: drawsShapes ? .on : .off) { _ in
            UserDefaults.standard.set(!drawsShapes, forKey: drawsShapesPreferenceKey)
        }
        let selectionAction = UIAction(title: "Select Ink", subtitle: "Move, resize, recolor or capture", image: UIImage(systemName: "lasso"),
                                       state: PaletteInkSelection.isOn ? .on : .off) { _ in
            PaletteInkSelection.isOn.toggle()
        }
        // Choosing a type also takes up the tool: it is chosen to be used.
        let lassoShapes = LassoShape.allCases.map { shape in
            UIAction(title: shape.title, image: UIImage(systemName: shape.symbolName), state: LassoShape.stored == shape ? .on : .off) { _ in
                LassoShape.stored = shape
                PaletteInkSelection.isOn = true
            }
        }
        let laserAction = UIAction(title: "Laser Pointer", subtitle: "Point without writing", image: LaserPointerGlyph.templateImage(),
                                   state: PaletteInkSelection.pointsWithLaser ? .on : .off) { _ in
            PaletteInkSelection.pointsWithLaser.toggle()
        }
        let laserStyles = LaserPointerStyle.allCases.map { style in
            UIAction(title: style.title, image: UIImage(systemName: style.symbolName), state: LaserPointerStyle.stored == style ? .on : .off) { _ in
                LaserPointerStyle.stored = style
                PaletteInkSelection.pointsWithLaser = true
            }
        }
        let colorsMenu = inkingToolInUse(of: toolPicker)?.inkType == .marker
            ? favoriteColorsMenu(for: toolPicker, palette: highlighterPalette, title: "Highlighter Colors")
            : favoriteColorsMenu(for: toolPicker, palette: palette)
        return [colorsMenu, UIMenu(options: .displayInline, children: [shapesAction]),
                UIMenu(options: .displayInline, children: [
                    selectionAction,
                    UIMenu(title: "Lasso Type", subtitle: LassoShape.stored.title, image: UIImage(systemName: LassoShape.stored.symbolName),
                           options: .singleSelection, children: lassoShapes),
                ]),
                UIMenu(options: .displayInline, children: [
                    laserAction,
                    UIMenu(title: "Laser Type", subtitle: LaserPointerStyle.stored.title, image: UIImage(systemName: LaserPointerStyle.stored.symbolName),
                           options: .singleSelection, children: laserStyles),
                ])]
    }

    // MARK: Favorite colors

    /// The colors of Settings › Colors, the list the notes' Format › Color menu uses, or the
    /// highlighter's own list there.
    static func favoriteColorsMenu(for toolPicker: PKToolPicker, palette: [PaletteColor], title: String = "Favorite Colors") -> UIMenu {
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
        return UIMenu(title: title, options: [.displayInline, .displayAsPalette], children: swatches)
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
        accessibilityValue = PencilToolPalette.accessibilityValue(shapesAreOn: isSelected)
    }
}

/// Hears every palette's tool choices. PencilKit keeps its observers weakly, so one shared
/// observer serves all palettes.
private final class PaletteToolChoiceObserver: NSObject, PKToolPickerObserver {
    static let shared = PaletteToolChoiceObserver()

    func toolPickerSelectedToolItemDidChange(_ toolPicker: PKToolPicker) {
        PaletteInkSelection.isOn = false
        PaletteInkSelection.pointsWithLaser = false
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
