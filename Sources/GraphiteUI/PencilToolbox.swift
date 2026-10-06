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

/// Every ink PencilKit draws with, under the names of the system's palette.
enum PencilInk: String, Codable, CaseIterable, Identifiable {
    case pen, monoline, fountainPen, reedPen, pencil, crayon, watercolor, highlighter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pen: "Pen"
        case .monoline: "Monoline"
        case .fountainPen: "Fountain Pen"
        case .reedPen: "Reed Pen"
        case .pencil: "Pencil"
        case .crayon: "Crayon"
        case .watercolor: "Watercolor"
        case .highlighter: "Highlighter"
        }
    }
    var symbolName: String {
        switch self {
        case .pen: "pencil.tip"
        case .monoline: "pencil.line"
        case .fountainPen: "paintbrush.pointed"
        case .reedPen: "pencil.and.outline"
        case .pencil: "pencil"
        case .crayon: "scribble"
        case .watercolor: "paintbrush"
        case .highlighter: "highlighter"
        }
    }

    /// The widths PencilKit accepts for the ink, in points.
    var widthRange: ClosedRange<Double> {
        switch self {
        case .pen: 0.9...25
        case .monoline: 0.5...4
        case .fountainPen: 1.5...14
        case .reedPen: 5...40
        case .pencil: 2.4...16
        case .crayon: 10...50
        case .watercolor: 10...80
        case .highlighter: 7.5...60
        }
    }

    /// Three widths to choose from on the bar, from fine to broad.
    var widthChoices: [Double] {
        switch self {
        case .pen: [1.6, 2.8, 4.8]
        case .monoline: [0.8, 1.6, 3.0]
        case .fountainPen: [2.5, 4.0, 7.0]
        case .reedPen: [8, 16, 28]
        case .pencil: [2.4, 4.0, 7.0]
        case .crayon: [12, 22, 36]
        case .watercolor: [14, 30, 52]
        case .highlighter: [10, 18, 28]
        }
    }
    var mediumWidth: Double { widthChoices[1] }

    var defaultColorHex: String {
        switch self {
        case .pencil: "#3a3a3c"
        case .highlighter: "#f6d743"
        default: "#1c1c1e"
        }
    }
}

/// One drawing tool of the bar as its owner set it up: an ink with its color, width and
/// opacity. The bar starts with three and holds up to `PencilToolbox.maximumPresetCount`.
struct InkPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var ink: PencilInk
    var colorHex: String
    var width: Double
    var opacity = 1.0

    static let opacityRange = 0.1...1.0

    init(ink: PencilInk) {
        self.ink = ink
        colorHex = ink.defaultColorHex
        width = ink.mediumWidth
    }

    /// The preset with every value one the bar can show: a stored state written by another
    /// build, or by hand, may hold others.
    var validated: InkPreset {
        var preset = self
        preset.colorHex = TextColorMarkup.canonicalHex(colorHex) ?? ink.defaultColorHex
        preset.width = width.isFinite ? min(max(width, ink.widthRange.lowerBound), ink.widthRange.upperBound) : ink.mediumWidth
        preset.opacity = opacity.isFinite ? min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) : 1
        return preset
    }
}

/// What the bar has in use: one of its inks, the eraser, or the lasso.
enum PencilToolKind: String, Codable, CaseIterable, Identifiable {
    case ink, eraser, lasso

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ink: "Ink"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        }
    }
    var symbolName: String {
        switch self {
        case .ink: "pencil.tip"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
}

/// The tool a canvas draws with, as a value, so a canvas is updated exactly when it changes.
struct PencilToolSelection: Equatable {
    var kind: PencilToolKind
    /// The ink preset in use, or the one last in use while erasing or selecting.
    var preset: InkPreset
    /// The eraser removes whole strokes, or only the ink it passes over.
    var erasesWholeStrokes: Bool
    var eraserWidth: Double
    var isRulerActive: Bool
}

/// The state of the fixed tool bar: its ink presets, the tool in use, and the eraser, kept
/// between launches and shared by every canvas, as the floating palette's is.
@MainActor @Observable
final class PencilToolbox {
    static let shared = PencilToolbox()
    static let storageKey = "GraphitePencilToolbox.v2"
    static let maximumPresetCount = 6
    /// The sizes of the eraser that removes only the ink it passes over.
    static let eraserWidthChoices: [Double] = [18, 36, 64]

    static var defaultPresets: [InkPreset] { [InkPreset(ink: .pen), InkPreset(ink: .pencil), InkPreset(ink: .highlighter)] }

    private struct StoredState: Codable {
        var toolInUse: PencilToolKind
        var presets: [InkPreset]
        var presetInUseIndex: Int
        var erasesWholeStrokes: Bool
        var eraserWidth: Double
    }

    @ObservationIgnored private var lastPencilGestureTimestamp: TimeInterval?

    /// Whether an Apple Pencil gesture is one not yet answered: every bar on screen hears
    /// it, and they share this toolbox.
    func acceptsPencilGesture(at timestamp: TimeInterval) -> Bool {
        guard timestamp != lastPencilGestureTimestamp else { return false }
        lastPencilGestureTimestamp = timestamp
        return true
    }

    /// Posted, with the toolbox as its object, as soon as the tool in use or anything about
    /// it changes. Canvases take the new tool then, before the next touch arrives, rather
    /// than when SwiftUI next updates their view.
    static let selectionDidChange = Notification.Name("GraphitePencilToolboxSelectionDidChange")

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var toolInUse: PencilToolKind { didSet { selectionChanged() } }
    private(set) var presets: [InkPreset] { didSet { selectionChanged() } }
    private(set) var presetInUseIndex: Int { didSet { selectionChanged() } }
    var erasesWholeStrokes: Bool { didSet { selectionChanged() } }
    private(set) var eraserWidth: Double { didSet { selectionChanged() } }
    /// The ruler is put away with the app, like a real one.
    var isRulerActive = false { didSet { NotificationCenter.default.post(name: Self.selectionDidChange, object: self) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.storageKey).flatMap { storedState in try? JSONDecoder().decode(StoredState.self, from: storedState) }
        var storedPresets = (stored?.presets ?? []).prefix(Self.maximumPresetCount).map(\.validated)
        // Two presets with one identifier would be one button to the bar.
        if Set(storedPresets.map(\.id)).count != storedPresets.count { storedPresets = [] }
        let hasStoredPresets = !storedPresets.isEmpty
        if !hasStoredPresets { storedPresets = Self.defaultPresets }
        presets = storedPresets
        presetInUseIndex = hasStoredPresets ? min(max(stored?.presetInUseIndex ?? 0, 0), storedPresets.count - 1) : 0
        toolInUse = stored?.toolInUse ?? .ink
        erasesWholeStrokes = stored?.erasesWholeStrokes ?? true
        eraserWidth = stored.map(\.eraserWidth).flatMap { width in Self.eraserWidthChoices.contains(width) ? width : nil } ?? Self.eraserWidthChoices[1]
    }

    private func selectionChanged() {
        let state = StoredState(toolInUse: toolInUse, presets: presets, presetInUseIndex: presetInUseIndex,
                                erasesWholeStrokes: erasesWholeStrokes, eraserWidth: eraserWidth)
        defaults.set(try? JSONEncoder().encode(state), forKey: Self.storageKey)
        NotificationCenter.default.post(name: Self.selectionDidChange, object: self)
    }

    /// The ink preset in use, or the one last in use while erasing or selecting.
    var presetInUse: InkPreset { presets[presetInUseIndex] }

    /// A tool of the bar, told apart from the others by its kind and, for an ink, its preset.
    struct Tool: Equatable {
        var kind: PencilToolKind
        var presetIdentifier: UUID
    }

    private var toolTakenUp: Tool { Tool(kind: toolInUse, presetIdentifier: presetInUse.id) }
    /// The tool in use before the last change of tool, which Apple Pencil's "switch to the
    /// previous tool" takes up again. Not kept between launches, as Apple's palette does not.
    @ObservationIgnored private(set) var previousTool: Tool?

    /// Makes a change of tool and remembers the tool it replaced.
    private func changeTool(_ change: () -> Void) {
        let toolBefore = toolTakenUp
        change()
        if toolTakenUp != toolBefore { previousTool = toolBefore }
    }

    func use(_ kind: PencilToolKind) {
        changeTool { if toolInUse != kind { toolInUse = kind } }
    }

    func usePreset(at presetIndex: Int) {
        guard presets.indices.contains(presetIndex) else { return }
        changeTool {
            if presetInUseIndex != presetIndex { presetInUseIndex = presetIndex }
            if toolInUse != .ink { toolInUse = .ink }
        }
    }

    /// Takes up the tool in use before the last change, as a double tap or squeeze of Apple
    /// Pencil does when set to switch to the previous tool. A preset removed meanwhile is
    /// replaced by the one in use.
    func switchToPreviousTool() {
        guard let previousTool else { return }
        let presetIndex = presets.firstIndex { preset in preset.id == previousTool.presetIdentifier } ?? presetInUseIndex
        changeTool {
            if presetInUseIndex != presetIndex { presetInUseIndex = presetIndex }
            if toolInUse != previousTool.kind { toolInUse = previousTool.kind }
        }
    }

    /// Takes up the eraser, or, when it is in use, the tool before it: Apple Pencil's
    /// "switch between the current tool and the eraser".
    func switchToEraser() {
        guard toolInUse == .eraser else { use(.eraser); return }
        if let previousTool, previousTool.kind != .eraser { switchToPreviousTool() } else { use(.ink) }
    }

    /// Gives the ink in use the color. With the eraser or the lasso in use, the ink last in
    /// use takes the color and is in use again: choosing a color means wanting to draw.
    func chooseColor(hex: String) {
        guard let canonicalHex = TextColorMarkup.canonicalHex(hex) else { return }
        use(.ink)
        if presets[presetInUseIndex].colorHex != canonicalHex { presets[presetInUseIndex].colorHex = canonicalHex }
    }

    /// Any width the ink can draw; the bar offers three, its options every one between.
    func chooseWidth(_ width: Double) {
        guard toolInUse == .ink, width.isFinite, presetInUse.ink.widthRange.contains(width), presetInUse.width != width else { return }
        presets[presetInUseIndex].width = width
    }

    func chooseOpacity(_ opacity: Double) {
        guard toolInUse == .ink, opacity.isFinite, InkPreset.opacityRange.contains(opacity), presetInUse.opacity != opacity else { return }
        presets[presetInUseIndex].opacity = opacity
    }

    /// Turns the preset in use into another ink. It keeps its color; the width becomes the
    /// new ink's medium one, as a pen's width would be a hairline for watercolor.
    func chooseInk(_ ink: PencilInk) {
        guard toolInUse == .ink, presetInUse.ink != ink else { return }
        var preset = presetInUse
        // A highlighter in the pen's black hides what it marks, and a pen in highlighter
        // yellow is hard to read: a color that is still the old ink's default follows.
        if preset.colorHex == preset.ink.defaultColorHex { preset.colorHex = ink.defaultColorHex }
        preset.ink = ink
        preset.width = ink.mediumWidth
        presets[presetInUseIndex] = preset
    }

    var canAddPreset: Bool { presets.count < Self.maximumPresetCount }
    var canRemovePreset: Bool { presets.count > 1 }

    /// Adds a copy of the preset in use after it and takes it up, to be set up differently.
    func addPreset() {
        guard canAddPreset else { return }
        var preset = presetInUse
        preset.id = UUID()
        let newPresetIndex = presetInUseIndex + 1
        presets.insert(preset, at: newPresetIndex)
        usePreset(at: newPresetIndex)
    }

    func removePresetInUse() {
        guard canRemovePreset else { return }
        let removedIndex = presetInUseIndex
        // The index is moved first: the presets are never shorter than it reaches.
        if removedIndex == presets.count - 1 { presetInUseIndex = removedIndex - 1 }
        presets.remove(at: removedIndex)
    }

    func chooseEraserWidth(_ width: Double) {
        guard Self.eraserWidthChoices.contains(width), eraserWidth != width else { return }
        eraserWidth = width
    }

    var selection: PencilToolSelection {
        PencilToolSelection(kind: toolInUse, preset: presetInUse, erasesWholeStrokes: erasesWholeStrokes,
                            eraserWidth: eraserWidth, isRulerActive: isRulerActive)
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit

extension PencilInk {
    /// The inks this system draws with; the reed pen came with iOS 26.
    static var availableInks: [PencilInk] {
        if #available(iOS 26.0, *) { return allCases }
        return allCases.filter { ink in ink != .reedPen }
    }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen: return .pen
        case .monoline: return .monoline
        case .fountainPen: return .fountainPen
        case .reedPen:
            if #available(iOS 26.0, *) { return .reed }
            return .fountainPen
        case .pencil: return .pencil
        case .crayon: return .crayon
        case .watercolor: return .watercolor
        case .highlighter: return .marker
        }
    }
}

extension InkPreset {
    var inkingTool: PKInkingTool {
        let inkType = ink.inkType
        let widthRange = inkType.validWidthRange
        let color = (UIColor(graphiteHex: colorHex) ?? .black).withAlphaComponent(CGFloat(opacity))
        return PKInkingTool(inkType, color: color, width: min(max(CGFloat(width), widthRange.lowerBound), widthRange.upperBound))
    }
}

extension PencilToolSelection {
    /// The PencilKit tool a canvas draws with.
    var tool: any PKTool {
        switch kind {
        case .ink: preset.inkingTool
        case .eraser: erasesWholeStrokes ? PKEraserTool(.vector) : PKEraserTool(.fixedWidthBitmap, width: CGFloat(eraserWidth))
        case .lasso: PKLassoTool()
        }
    }
}

/// A short stroke in an ink, drawn by PencilKit itself, so the inks are told apart by how
/// they draw rather than by a symbol.
@MainActor
enum PencilInkSample {
    static let size = CGSize(width: 68, height: 30)
    private static let cache = NSCache<NSString, UIImage>()

    static func image(of ink: PencilInk, colorHex: String, colorScheme: ColorScheme, displayScale: CGFloat) -> UIImage {
        let cacheKey = "\(ink.rawValue)|\(colorHex)|\(colorScheme == .dark)|\(displayScale)" as NSString
        if let cachedImage = cache.object(forKey: cacheKey) { return cachedImage }
        // Broad inks are drawn narrower than on a page, to fit the sample, and the finest
        // ones broader, to be seen in it.
        let sampleWidth = CGFloat(min(max(ink.mediumWidth, 2.5), 11))
        let strokeBounds = CGRect(origin: .zero, size: size).insetBy(dx: 9, dy: 0)
        let pointCount = 28
        let points = (0..<pointCount).map { pointIndex in
            let progress = CGFloat(pointIndex) / CGFloat(pointCount - 1)
            let location = CGPoint(x: strokeBounds.minX + strokeBounds.width * progress, y: size.height / 2 - sin(progress * 2 * .pi) * 6)
            // Pressed harder in the middle, as a hand would, which the pen and the pencil show.
            return PKStrokePoint(location: location, timeOffset: TimeInterval(pointIndex) * 0.02, size: CGSize(width: sampleWidth, height: sampleWidth),
                                 opacity: 1, force: 0.6 + 0.8 * sin(progress * .pi), azimuth: .pi / 4, altitude: .pi / 3)
        }
        let stroke = PKStroke(ink: PKInk(ink.inkType, color: UIColor(graphiteHex: colorHex) ?? .black),
                              path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 0)))
        var sampleImage = UIImage()
        // PencilKit lightens dark inks on a dark background, as the popover's is in dark mode.
        UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light).performAsCurrent {
            sampleImage = PKDrawing(strokes: [stroke]).image(from: CGRect(origin: .zero, size: size), scale: displayScale)
        }
        cache.setObject(sampleImage, forKey: cacheKey)
        return sampleImage
    }
}

/// The fixed tool bar: the tools (`PencilToolRow`) in a row of their own, with the
/// document's own controls at its ends where they have no other place.
struct PencilToolbar<LeadingControls: View, TrailingControls: View>: View {
    @Bindable var toolbox: PencilToolbox
    let favoriteColors: [PaletteColor]
    @Binding var drawsShapes: Bool
    /// Nil where images cannot be added.
    var addImage: (() -> Void)?
    /// The document's history, for the Undo and Redo of the palette Apple Pencil's squeeze opens.
    var undoAvailability: UndoAvailability?
    /// The document's own controls, such as Read/Write, Undo and Redo, where they have no
    /// other place: the bar shares its row with them rather than adding one.
    @ViewBuilder var leadingControls: LeadingControls
    @ViewBuilder var trailingControls: TrailingControls

    var body: some View {
        HStack(spacing: 12) {
            leadingControls.padding(.leading, 16)
            PencilToolRow(toolbox: toolbox, favoriteColors: favoriteColors, drawsShapes: $drawsShapes, addImage: addImage,
                          undoAvailability: undoAvailability)
                .frame(maxWidth: .infinity)
            trailingControls
                .labelStyle(.iconOnly)
                .padding(.trailing, 16)
        }
        .frame(height: PencilToolbarMetrics.height)
        .tint(.primary)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The fixed bar's tools in one row: the ink presets, the eraser and the lasso; the width of
/// the tool in use; its color, from the favorite colors of Settings › Colors; then the shape
/// tool, the ruler, and adding an image. The row takes the width it needs where that fits
/// and scrolls sideways where it does not. The fixed bar shows it, and so does a side's tab
/// bar where it has room.
///
/// A second tap on the ink in use opens its options: every ink PencilKit has, any width and
/// opacity, and adding or removing a preset.
///
/// The tool in use has a filled background and the selected trait, so it is not told apart
/// by color alone.
struct PencilToolRow: View {
    @Bindable var toolbox: PencilToolbox
    let favoriteColors: [PaletteColor]
    @Binding var drawsShapes: Bool
    /// Nil where images cannot be added.
    var addImage: (() -> Void)?
    /// The document's history, for the Undo and Redo of the palette Apple Pencil's squeeze opens.
    var undoAvailability: UndoAvailability?
    var rowHeight: CGFloat = PencilToolbarMetrics.height
    @State private var showsInkOptions = false

    private var buttonSide: CGFloat { PencilToolbarMetrics.buttonSide }
    private var selectedFill: AnyShapeStyle { PencilToolbarMetrics.selectedFill }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tools
            // Where the row does not fit, its ends fade, so a tool cut off by the edge
            // reads as more to scroll to.
            ScrollView(.horizontal, showsIndicators: false) { tools }
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 12)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 12)
                    }
                }
        }
        .frame(height: rowHeight)
        .tint(.primary)
        // Apple's palette answers Apple Pencil's double tap and squeeze; the row takes its place.
        .background { PencilGestureReceiver(toolbox: toolbox, favoriteColors: favoriteColors, undoAvailability: undoAvailability) }
    }

    private var tools: some View {
        HStack(spacing: 2) {
            ForEach(Array(toolbox.presets.enumerated()), id: \.element.id) { presetIndex, preset in presetButton(preset, at: presetIndex) }
            toolButton(.eraser)
            toolButton(.lasso)
            separator
            switch toolbox.toolInUse {
            case .ink:
                ForEach(toolbox.presetInUse.ink.widthChoices, id: \.self) { width in
                    sizeButton(choiceIndex: toolbox.presetInUse.ink.widthChoices.firstIndex(of: width) ?? 0, isChosen: toolbox.presetInUse.width == width) {
                        toolbox.chooseWidth(width)
                    }
                }
                separator
            case .eraser:
                Picker("Eraser", selection: $toolbox.erasesWholeStrokes) {
                    Text("Strokes").tag(true)
                    Text("Pixels").tag(false)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                if !toolbox.erasesWholeStrokes {
                    ForEach(PencilToolbox.eraserWidthChoices, id: \.self) { width in
                        sizeButton(choiceIndex: PencilToolbox.eraserWidthChoices.firstIndex(of: width) ?? 0, isChosen: toolbox.eraserWidth == width) {
                            toolbox.chooseEraserWidth(width)
                        }
                    }
                }
                separator
            case .lasso:
                EmptyView()
            }
            colorButton(name: "black", hex: PencilInk.pen.defaultColorHex)
            ForEach(favoriteColors) { favorite in colorButton(name: favorite.name, hex: favorite.hex) }
            ColorPicker("Other Color", selection: Binding(
                get: { Color(graphiteHex: toolbox.presetInUse.colorHex) ?? .black },
                set: { newColor in if let hex = newColor.sRGBHex { toolbox.chooseColor(hex: hex) } }), supportsOpacity: false)
                .labelsHidden()
                .frame(width: buttonSide, height: rowHeight)
            separator
            toggleButton("Shapes", symbolName: drawsShapes ? "square.fill.on.circle.fill" : "square.on.circle", isOn: $drawsShapes)
            toggleButton("Ruler", symbolName: "ruler", isOn: $toolbox.isRulerActive)
            if let addImage {
                Button("Add Image", systemImage: "photo.badge.plus", action: addImage)
                    .labelStyle(.iconOnly)
                    .frame(width: buttonSide, height: rowHeight)
            }
        }
        .padding(.horizontal, 10)
    }

    private var separator: some View {
        Divider().frame(height: 22).padding(.horizontal, 5)
    }

    private var buttons: PencilToolButtons { PencilToolButtons(toolbox: toolbox, rowHeight: rowHeight) }

    private func presetButton(_ preset: InkPreset, at presetIndex: Int) -> some View {
        let isInUse = toolbox.toolInUse == .ink && toolbox.presetInUseIndex == presetIndex
        return buttons.presetButton(preset, at: presetIndex) { showsInkOptions = true }
            .popover(isPresented: Binding(get: { showsInkOptions && isInUse }, set: { isPresented in showsInkOptions = isPresented })) {
                PencilInkOptions(toolbox: toolbox)
                    .presentationCompactAdaptation(.popover)
            }
    }

    private func toolButton(_ kind: PencilToolKind) -> some View { buttons.toolButton(kind) }

    private func sizeButton(choiceIndex: Int, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        buttons.sizeButton(choiceIndex: choiceIndex, isChosen: isChosen, choose: choose)
    }

    private func colorButton(name: String, hex: String) -> some View { buttons.colorButton(name: name, hex: hex) }

    private func toggleButton(_ title: String, symbolName: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: isOn.wrappedValue ? .semibold : .regular))
                .frame(width: buttonSide, height: buttonSide)
                .background(isOn.wrappedValue ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 9))
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }
}

extension PencilToolbar where LeadingControls == EmptyView, TrailingControls == EmptyView {
    init(toolbox: PencilToolbox, favoriteColors: [PaletteColor], drawsShapes: Binding<Bool>, addImage: (() -> Void)? = nil,
         undoAvailability: UndoAvailability? = nil) {
        self.init(toolbox: toolbox, favoriteColors: favoriteColors, drawsShapes: drawsShapes, addImage: addImage, undoAvailability: undoAvailability,
                  leadingControls: { EmptyView() }, trailingControls: { EmptyView() })
    }
}

/// The fixed bar's tools at the end of a side's tab bar, for the PDF its active tab shows,
/// while that PDF is written on: in the row that is there anyway rather than a row of their
/// own above the page. The side decides whether its tab bar has room.
struct TabBarPencilTools: View {
    let session: PDFSession
    let isFocused: Bool
    @AppStorage(PencilToolbarStyle.preferenceKey) private var toolbarStyle = PencilToolbarStyle.floating
    @AppStorage(PDFAnnotationPreferenceKey.showsToolPicker) private var showsToolPicker = true
    @AppStorage(PDFAnnotationPreferenceKey.drawsShapes) private var drawsShapes = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var pictureSource: PDFPictureSource?

    var body: some View {
        if session.showsFixedPencilTools(style: toolbarStyle, showsTools: showsToolPicker, horizontalSizeClass: horizontalSizeClass, isFocused: isFocused) {
            PencilToolRow(toolbox: PencilToolbox.shared, favoriteColors: GraphitePreferences.storedColorPalette(), drawsShapes: $drawsShapes,
                          addImage: { pictureSource = .photoLibrary }, undoAvailability: session.undoAvailability, rowHeight: 40)
                .modifier(PDFPictureAdding(session: session, source: $pictureSource))
        }
    }
}

extension PDFSession {
    /// Whether the fixed bar's tools are shown for this PDF: the fixed bar is chosen and
    /// shown, the width is not compact, and the PDF is written on, can be changed, and is on
    /// the focused side.
    func showsFixedPencilTools(style: PencilToolbarStyle, showsTools: Bool, horizontalSizeClass: UserInterfaceSizeClass?, isFocused: Bool) -> Bool {
        style == .fixed && horizontalSizeClass != .compact && showsTools && isFocused && isWriting && !isProtected
    }
}

/// The buttons of the bar's tools, shared by the fixed bar and the palette Apple Pencil's
/// squeeze opens.
@MainActor
struct PencilToolButtons {
    let toolbox: PencilToolbox
    let rowHeight: CGFloat

    private var buttonSide: CGFloat { PencilToolbarMetrics.buttonSide }
    private var selectedFill: AnyShapeStyle { PencilToolbarMetrics.selectedFill }

    /// An ink preset; a tap on the one in use calls `tapOnPresetInUse`.
    func presetButton(_ preset: InkPreset, at presetIndex: Int, tapOnPresetInUse: @escaping () -> Void) -> some View {
        let isInUse = toolbox.toolInUse == .ink && toolbox.presetInUseIndex == presetIndex
        return Button {
            if isInUse { tapOnPresetInUse() } else { toolbox.usePreset(at: presetIndex) }
        } label: {
            Image(systemName: preset.ink.symbolName)
                .font(.system(size: 17, weight: isInUse ? .semibold : .regular))
                .frame(width: buttonSide, height: buttonSide)
                .background(isInUse ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 9))
                // The ink the preset draws with.
                .overlay(alignment: .bottom) {
                    Capsule().fill(Color(graphiteHex: preset.colorHex) ?? .black).opacity(max(preset.opacity, 0.35))
                        .frame(width: 18, height: 3).padding(.bottom, 3)
                }
                // Marks that a second tap opens the ink's options.
                .overlay(alignment: .topTrailing) {
                    if isInUse {
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary).padding(4)
                    }
                }
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.ink.title)
        .accessibilityHint(isInUse ? "Opens the ink's options" : "")
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    func toolButton(_ kind: PencilToolKind) -> some View {
        let isInUse = toolbox.toolInUse == kind
        return Button {
            toolbox.use(kind)
        } label: {
            Image(systemName: kind.symbolName)
                .font(.system(size: 17, weight: isInUse ? .semibold : .regular))
                .frame(width: buttonSide, height: buttonSide)
                .background(isInUse ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 9))
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    /// One of three sizes, of an ink or of the eraser.
    func sizeButton(choiceIndex: Int, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            Circle()
                .fill(.primary)
                .frame(width: CGFloat(5 + 4 * choiceIndex), height: CGFloat(5 + 4 * choiceIndex))
                .frame(width: 28, height: buttonSide)
                .background(isChosen ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 9))
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(["Fine", "Medium", "Broad"][min(choiceIndex, 2)])
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    func colorButton(name: String, hex: String) -> some View {
        let isInUse = toolbox.toolInUse == .ink && TextColorMarkup.canonicalHex(hex) == toolbox.presetInUse.colorHex
        return Button {
            toolbox.chooseColor(hex: hex)
        } label: {
            Circle()
                .fill(Color(graphiteHex: hex) ?? .black)
                .frame(width: 20, height: 20)
                // A ring, so the color in use is marked by shape as well.
                .overlay { if isInUse { Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 28, height: 28) } }
                .frame(width: 30, height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }
}

enum PencilToolbarMetrics {
    static let height: CGFloat = 44
    static let buttonSide: CGFloat = 36
    /// The background of the tool in use.
    static var selectedFill: AnyShapeStyle { AnyShapeStyle(.primary.opacity(0.14)) }
}

/// The options of the ink preset in use: which ink it is, its width and its opacity, and
/// adding or removing a preset.
struct PencilInkOptions: View {
    @Bindable var toolbox: PencilToolbox
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss

    private static let inkColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        let preset = toolbox.presetInUse
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: Self.inkColumns, spacing: 8) {
                ForEach(PencilInk.availableInks) { ink in inkButton(ink, preset: preset) }
            }
            VStack(spacing: 10) {
                LabeledContent("Width") {
                    Slider(value: Binding(get: { toolbox.presetInUse.width }, set: { width in toolbox.chooseWidth(width) }), in: preset.ink.widthRange)
                        .accessibilityLabel("Width")
                        .accessibilityValue(preset.width.formatted(.number.precision(.fractionLength(1))) + " points")
                }
                LabeledContent("Opacity") {
                    Slider(value: Binding(get: { toolbox.presetInUse.opacity }, set: { opacity in toolbox.chooseOpacity(opacity) }), in: InkPreset.opacityRange)
                        .accessibilityLabel("Opacity")
                        .accessibilityValue(preset.opacity.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .font(.callout)
            Divider()
            HStack {
                // The options belong to the tool they were opened from, which is then no
                // longer the one in use, or gone.
                Button("Add a Tool", systemImage: "plus") {
                    toolbox.addPreset()
                    dismiss()
                }
                .disabled(!toolbox.canAddPreset)
                .help("Adds a copy of this tool to the bar, to set up differently")
                Spacer()
                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                    toolbox.removePresetInUse()
                    dismiss()
                }
                .disabled(!toolbox.canRemovePreset)
            }
            .font(.callout)
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 360)
        .tint(.primary)
    }

    private func inkButton(_ ink: PencilInk, preset: InkPreset) -> some View {
        let isInUse = preset.ink == ink
        return Button {
            toolbox.chooseInk(ink)
        } label: {
            VStack(spacing: 2) {
                Image(uiImage: PencilInkSample.image(of: ink, colorHex: preset.colorHex, colorScheme: colorScheme, displayScale: displayScale))
                    .accessibilityHidden(true)
                Text(ink.title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(isInUse ? AnyShapeStyle(.primary.opacity(0.14)) : AnyShapeStyle(.primary.opacity(0.04)), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ink.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }
}
#endif
