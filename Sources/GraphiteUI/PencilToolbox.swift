import SwiftUI
import GraphiteCore

/// Where the Pencil tools are shown while drawing.
enum PencilToolbarStyle: String, CaseIterable, Identifiable {
    /// The system's palette, which floats over the page and can be moved or minimized.
    case floating
    /// A bar fixed above the page, as in Goodnotes or Notability.
    case fixed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .floating: "Floating palette"
        case .fixed: "Fixed bar"
        }
    }

    static let preferenceKey = "GraphitePencilToolbarStyle"
}

/// The tools of the fixed tool bar.
enum PencilToolKind: String, Codable, CaseIterable, Identifiable {
    case pen, pencil, highlighter, eraser, lasso

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pen: "Pen"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        }
    }
    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
    /// Whether the tool draws ink, and so has a color and a width.
    var drawsInk: Bool { self == .pen || self == .pencil || self == .highlighter }

    /// Three widths to choose from, in points, from fine to broad.
    var widthChoices: [Double] {
        switch self {
        case .pen: [1.6, 2.8, 4.8]
        case .pencil: [2.4, 4.0, 7.0]
        case .highlighter: [10, 18, 28]
        case .eraser, .lasso: []
        }
    }

    var defaultColorHex: String {
        switch self {
        case .pen: "#1c1c1e"
        case .pencil: "#3a3a3c"
        case .highlighter: "#f6d743"
        case .eraser, .lasso: "#1c1c1e"
        }
    }
}

/// One tool as the canvases use it: what the fixed bar has selected, with its color and
/// width. A value, so a canvas is updated exactly when it changes.
struct PencilToolSelection: Equatable {
    var kind: PencilToolKind
    var colorHex: String
    var width: Double
    /// The eraser removes whole strokes, or only the ink it passes over.
    var erasesWholeStrokes: Bool
    var isRulerActive: Bool
}

/// The state of the fixed tool bar: the tool in use and each inking tool's color and
/// width, kept between launches and shared by every canvas, as the floating palette's is.
@MainActor @Observable
final class PencilToolbox {
    static let shared = PencilToolbox()
    static let storageKey = "GraphitePencilToolbox.v1"

    private struct StoredState: Codable {
        var toolInUse: PencilToolKind
        var colorHexes: [String: String]
        var widths: [String: Double]
        var erasesWholeStrokes: Bool
    }

    /// Posted, with the toolbox as its object, as soon as the tool in use, its color or its
    /// width changes. Canvases take the new tool then, before the next touch arrives, rather
    /// than when SwiftUI next updates their view.
    static let selectionDidChange = Notification.Name("GraphitePencilToolboxSelectionDidChange")

    @ObservationIgnored private let defaults: UserDefaults
    var toolInUse: PencilToolKind { didSet { selectionChanged() } }
    private var colorHexes: [PencilToolKind: String] { didSet { selectionChanged() } }
    private var widths: [PencilToolKind: Double] { didSet { selectionChanged() } }
    var erasesWholeStrokes: Bool { didSet { selectionChanged() } }
    /// The ruler is put away with the app, like a real one.
    var isRulerActive = false { didSet { NotificationCenter.default.post(name: Self.selectionDidChange, object: self) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey).flatMap { storedState in try? JSONDecoder().decode(StoredState.self, from: storedState) }
        toolInUse = stored?.toolInUse ?? .pen
        var storedColorHexes: [PencilToolKind: String] = [:], storedWidths: [PencilToolKind: Double] = [:]
        for kind in PencilToolKind.allCases where kind.drawsInk {
            storedColorHexes[kind] = stored?.colorHexes[kind.rawValue].flatMap(TextColorMarkup.canonicalHex) ?? kind.defaultColorHex
            let storedWidth = stored?.widths[kind.rawValue] ?? kind.widthChoices[1]
            storedWidths[kind] = kind.widthChoices.contains(storedWidth) ? storedWidth : kind.widthChoices[1]
        }
        colorHexes = storedColorHexes
        widths = storedWidths
        erasesWholeStrokes = stored?.erasesWholeStrokes ?? true
    }

    private func selectionChanged() {
        save()
        NotificationCenter.default.post(name: Self.selectionDidChange, object: self)
    }

    private func save() {
        let state = StoredState(toolInUse: toolInUse,
                                colorHexes: Dictionary(uniqueKeysWithValues: colorHexes.map { kind, hex in (kind.rawValue, hex) }),
                                widths: Dictionary(uniqueKeysWithValues: widths.map { kind, width in (kind.rawValue, width) }),
                                erasesWholeStrokes: erasesWholeStrokes)
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
    }

    func colorHex(of kind: PencilToolKind) -> String { colorHexes[kind] ?? kind.defaultColorHex }
    func width(of kind: PencilToolKind) -> Double { widths[kind] ?? kind.widthChoices.dropFirst().first ?? 0 }

    /// Gives the tool in use the color. With the eraser or the lasso in use, the pen takes
    /// the color and becomes the tool in use: choosing a color means wanting to draw.
    func chooseColor(hex: String) {
        guard let canonicalHex = TextColorMarkup.canonicalHex(hex) else { return }
        if !toolInUse.drawsInk { toolInUse = .pen }
        colorHexes[toolInUse] = canonicalHex
    }

    func chooseWidth(_ width: Double) {
        guard toolInUse.drawsInk, toolInUse.widthChoices.contains(width) else { return }
        widths[toolInUse] = width
    }

    var selection: PencilToolSelection {
        PencilToolSelection(kind: toolInUse, colorHex: colorHex(of: toolInUse), width: width(of: toolInUse),
                            erasesWholeStrokes: erasesWholeStrokes, isRulerActive: isRulerActive)
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit

extension PencilToolSelection {
    /// The PencilKit tool a canvas draws with.
    var tool: any PKTool {
        switch kind {
        case .pen: inkingTool(.pen)
        case .pencil: inkingTool(.pencil)
        case .highlighter: inkingTool(.marker)
        case .eraser: PKEraserTool(erasesWholeStrokes ? .vector : .bitmap)
        case .lasso: PKLassoTool()
        }
    }

    private func inkingTool(_ inkType: PKInkingTool.InkType) -> PKInkingTool {
        let widthRange = inkType.validWidthRange
        let color = UIColor(graphiteHex: colorHex) ?? .black
        return PKInkingTool(inkType, color: color, width: min(max(CGFloat(width), widthRange.lowerBound), widthRange.upperBound))
    }
}

/// The fixed tool bar: tools, the width of the tool in use, its color from the favorite
/// colors of Settings › Colors, then the shape tool, the ruler, and adding an image.
///
/// The tool in use has a filled background and the selected trait, so it is not told
/// apart by color alone.
struct PencilToolbar: View {
    @Bindable var toolbox: PencilToolbox
    let favoriteColors: [PaletteColor]
    @Binding var drawsShapes: Bool
    /// Nil where images cannot be added.
    var addImage: (() -> Void)?

    private static let buttonSide: CGFloat = 40

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PencilToolKind.allCases) { kind in toolButton(kind) }
                separator
                if toolbox.toolInUse.drawsInk {
                    ForEach(toolbox.toolInUse.widthChoices, id: \.self) { width in widthButton(width) }
                    separator
                } else if toolbox.toolInUse == .eraser {
                    Picker("Eraser", selection: $toolbox.erasesWholeStrokes) {
                        Text("Strokes").tag(true)
                        Text("Pixels").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    separator
                }
                colorButton(name: "black", hex: "#1c1c1e")
                ForEach(favoriteColors) { favorite in colorButton(name: favorite.name, hex: favorite.hex) }
                ColorPicker("Other Color", selection: Binding(
                    get: { Color(graphiteHex: toolbox.colorHex(of: toolbox.toolInUse.drawsInk ? toolbox.toolInUse : .pen)) ?? .black },
                    set: { newColor in if let hex = newColor.sRGBHex { toolbox.chooseColor(hex: hex) } }), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: Self.buttonSide, height: Self.buttonSide)
                separator
                toggleButton("Shapes", symbolName: drawsShapes ? "square.fill.on.circle.fill" : "square.on.circle", isOn: $drawsShapes)
                toggleButton("Ruler", symbolName: "ruler", isOn: $toolbox.isRulerActive)
                if let addImage {
                    Button("Add Image", systemImage: "photo.badge.plus", action: addImage)
                        .labelStyle(.iconOnly)
                        .frame(width: Self.buttonSide, height: Self.buttonSide)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .tint(.primary)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var separator: some View {
        Divider().frame(height: 24).padding(.horizontal, 4)
    }

    private func toolButton(_ kind: PencilToolKind) -> some View {
        let isInUse = toolbox.toolInUse == kind
        return Button {
            toolbox.toolInUse = kind
        } label: {
            Image(systemName: kind.symbolName)
                .font(.system(size: 18, weight: isInUse ? .semibold : .regular))
                .frame(width: Self.buttonSide, height: Self.buttonSide)
                .background(isInUse ? AnyShapeStyle(.primary.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .bottom) {
                    // The ink the tool draws with.
                    if kind.drawsInk {
                        Capsule().fill(Color(graphiteHex: toolbox.colorHex(of: kind)) ?? .black).frame(width: 18, height: 3).padding(.bottom, 4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private func widthButton(_ width: Double) -> some View {
        let kind = toolbox.toolInUse
        let isChosen = toolbox.width(of: kind) == width
        let choiceIndex = kind.widthChoices.firstIndex(of: width) ?? 0
        return Button {
            toolbox.chooseWidth(width)
        } label: {
            Circle()
                .fill(.primary)
                .frame(width: CGFloat(5 + 4 * choiceIndex), height: CGFloat(5 + 4 * choiceIndex))
                .frame(width: 32, height: Self.buttonSide)
                .background(isChosen ? AnyShapeStyle(.primary.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(["Fine", "Medium", "Broad"][min(choiceIndex, 2)])
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func colorButton(name: String, hex: String) -> some View {
        let isInUse = toolbox.toolInUse.drawsInk && TextColorMarkup.canonicalHex(hex) == toolbox.colorHex(of: toolbox.toolInUse)
        return Button {
            toolbox.chooseColor(hex: hex)
        } label: {
            Circle()
                .fill(Color(graphiteHex: hex) ?? .black)
                .frame(width: 22, height: 22)
                // A ring, so the color in use is marked by shape as well.
                .overlay { if isInUse { Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 30, height: 30) } }
                .frame(width: 34, height: Self.buttonSide)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private func toggleButton(_ title: String, symbolName: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: isOn.wrappedValue ? .semibold : .regular))
                .frame(width: Self.buttonSide, height: Self.buttonSide)
                .background(isOn.wrappedValue ? AnyShapeStyle(.primary.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }
}
#endif
