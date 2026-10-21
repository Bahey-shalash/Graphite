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
        case .floating: "Floating Palette"
        case .fixed: "Fixed Bar"
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

    /// The three widths a tool of this ink starts with on the bar, from fine to broad. Each
    /// tool can change its own (`InkPreset.widthChoices`).
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
/// opacity, and the three widths the bar offers for it. The bar starts with three tools and
/// holds up to `PencilToolbox.maximumPresetCount`.
struct InkPreset: Codable, Equatable, Identifiable {
    var id = UUID()
    var ink: PencilInk
    var colorHex: String
    var width: Double
    var opacity = 1.0
    /// The tool's three sizes on the bar, from the ink's own (`PencilInk.widthChoices`); a
    /// second tap on the size in use changes its width.
    var widthChoices: [Double]

    static let opacityRange = 0.1...1.0

    init(ink: PencilInk) {
        self.ink = ink
        colorHex = ink.defaultColorHex
        width = ink.mediumWidth
        widthChoices = ink.widthChoices
    }

    private enum CodingKeys: String, CodingKey {
        case id, ink, colorHex, width, opacity, widthChoices
    }

    /// A tool saved before its sizes could be changed has the ink's own.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ink = try container.decode(PencilInk.self, forKey: .ink)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        width = try container.decode(Double.self, forKey: .width)
        opacity = try container.decode(Double.self, forKey: .opacity)
        widthChoices = try container.decodeIfPresent([Double].self, forKey: .widthChoices) ?? ink.widthChoices
    }

    /// The preset with every value one the bar can show: a stored state written by another
    /// build, or by hand, may hold others.
    var validated: InkPreset {
        var preset = self
        let widthRange = ink.widthRange
        func drawableWidth(_ width: Double, otherwise fallbackWidth: Double) -> Double {
            width.isFinite ? min(max(width, widthRange.lowerBound), widthRange.upperBound) : fallbackWidth
        }
        preset.colorHex = TextColorMarkup.canonicalHex(colorHex) ?? ink.defaultColorHex
        preset.width = drawableWidth(width, otherwise: ink.mediumWidth)
        preset.opacity = opacity.isFinite ? min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound) : 1
        preset.widthChoices = widthChoices.count == ink.widthChoices.count
            ? zip(widthChoices, ink.widthChoices).map { storedWidth, inkWidth in drawableWidth(storedWidth, otherwise: inkWidth) }
            : ink.widthChoices
        return preset
    }
}

/// What the bar has in use: one of its inks, the eraser, the lasso, the laser pointer, the
/// Read Aloud pen, or the text tool.
enum PencilToolKind: String, Codable, CaseIterable, Identifiable {
    case ink, eraser, lasso, laser, readAloud, text

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ink: "Ink"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        case .laser: "Laser Pointer"
        case .readAloud: "Read Aloud Pen"
        case .text: "Text Box"
        }
    }
    var symbolName: String {
        switch self {
        case .ink: "pencil.tip"
        case .eraser: "eraser"
        case .lasso: "lasso"
        // Only a fallback: the bar and the palette draw the laser's own glyph (`LaserPointerGlyph`).
        case .laser: "cursorarrow.rays"
        // Only a fallback, as for the laser (`ReadAloudPenGlyph`).
        case .readAloud: "speaker.wave.2"
        case .text: "character.textbox"
        }
    }
    /// Whether the canvas draws with PencilKit's tool: the lasso and the laser pointer are
    /// Graphite's own and draw nothing.
    var drawsInk: Bool { self == .ink || self == .eraser }
    /// Tools for the moment, put away with the app: the laser points while presenting, the
    /// Read Aloud pen points at what to read, and the text tool places a box or two among the
    /// ink. The tool before them is kept instead, which a build without them can read.
    var isPutAwayWithApp: Bool { self == .laser || self == .readAloud || self == .text }
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
    /// The three sizes the eraser that removes only the ink it passes over starts with.
    static let defaultEraserWidthChoices: [Double] = [18, 36, 64]
    /// The widths those sizes can be changed to, in points.
    static let eraserWidthRange: ClosedRange<Double> = 4...100

    static var defaultPresets: [InkPreset] { [InkPreset(ink: .pen), InkPreset(ink: .pencil), InkPreset(ink: .highlighter)] }

    private struct StoredState: Codable {
        var toolInUse: PencilToolKind
        var presets: [InkPreset]
        var presetInUseIndex: Int
        var erasesWholeStrokes: Bool
        var eraserWidth: Double
        /// Absent from a state saved before the eraser's sizes could be changed.
        var eraserWidthChoices: [Double]?
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
    /// The pixel eraser's three sizes on the bar; a second tap on the one in use changes it.
    private(set) var eraserWidthChoices: [Double] { didSet { selectionChanged() } }
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
        let storedTool = stored?.toolInUse ?? .ink
        toolInUse = storedTool
        toolSavedInPlaceOfLaser = storedTool.isPutAwayWithApp ? .ink : storedTool
        erasesWholeStrokes = stored?.erasesWholeStrokes ?? true
        let storedEraserWidthChoices = stored?.eraserWidthChoices.flatMap { widths in Self.validatedEraserWidthChoices(widths) } ?? Self.defaultEraserWidthChoices
        eraserWidthChoices = storedEraserWidthChoices
        eraserWidth = stored.map(\.eraserWidth).flatMap { width in storedEraserWidthChoices.contains(width) ? width : nil } ?? storedEraserWidthChoices[1]
    }

    /// Three widths the eraser can erase with, or nil for anything else.
    private static func validatedEraserWidthChoices(_ widths: [Double]) -> [Double]? {
        widths.count == defaultEraserWidthChoices.count && widths.allSatisfy(eraserWidthRange.contains) ? widths : nil
    }

    /// The tool kept between launches in place of the laser pointer: the one in use before
    /// it. The laser points while presenting and is put away with the app; and a build
    /// without it could not read a saved state naming it, and would start with its default
    /// presets.
    @ObservationIgnored private var toolSavedInPlaceOfLaser = PencilToolKind.ink

    private func selectionChanged() {
        if !toolInUse.isPutAwayWithApp { toolSavedInPlaceOfLaser = toolInUse }
        let savedTool = toolInUse.isPutAwayWithApp ? toolSavedInPlaceOfLaser : toolInUse
        let state = StoredState(toolInUse: savedTool, presets: presets, presetInUseIndex: presetInUseIndex,
                                erasesWholeStrokes: erasesWholeStrokes, eraserWidth: eraserWidth, eraserWidthChoices: eraserWidthChoices)
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

    /// Any width the ink can draw, as the options' slider gives it. The size in use on the
    /// bar, when the width was one of the three, takes the new width.
    func chooseWidth(_ width: Double) {
        guard toolInUse == .ink, width.isFinite, presetInUse.ink.widthRange.contains(width), presetInUse.width != width else { return }
        if let chosenWidthIndex {
            changeWidthChoice(at: chosenWidthIndex, to: width)
        } else {
            presets[presetInUseIndex].width = width
        }
    }

    /// Which of the three sizes of the ink in use is chosen; nil when its width is none of them.
    var chosenWidthIndex: Int? { presetInUse.widthChoices.firstIndex(of: presetInUse.width) }

    /// Draws with one of the three sizes of the ink in use.
    func useWidthChoice(at choiceIndex: Int) {
        guard toolInUse == .ink, presetInUse.widthChoices.indices.contains(choiceIndex) else { return }
        let width = presetInUse.widthChoices[choiceIndex]
        if presetInUse.width != width { presets[presetInUseIndex].width = width }
    }

    /// Gives one of the three sizes of the ink in use another width, kept within what the
    /// ink draws, and draws with it.
    func changeWidthChoice(at choiceIndex: Int, to width: Double) {
        guard toolInUse == .ink, presetInUse.widthChoices.indices.contains(choiceIndex), width.isFinite else { return }
        let widthRange = presetInUse.ink.widthRange
        var preset = presetInUse
        preset.widthChoices[choiceIndex] = min(max(width, widthRange.lowerBound), widthRange.upperBound)
        preset.width = preset.widthChoices[choiceIndex]
        if preset != presetInUse { presets[presetInUseIndex] = preset }
    }

    func chooseOpacity(_ opacity: Double) {
        guard toolInUse == .ink, opacity.isFinite, InkPreset.opacityRange.contains(opacity), presetInUse.opacity != opacity else { return }
        presets[presetInUseIndex].opacity = opacity
    }

    /// Turns the preset in use into another ink. It keeps its color; the width becomes the
    /// new ink's medium one and the sizes the new ink's, as a pen's width would be a hairline
    /// for watercolor.
    func chooseInk(_ ink: PencilInk) {
        guard toolInUse == .ink, presetInUse.ink != ink else { return }
        var preset = presetInUse
        // A highlighter in the pen's black hides what it marks, and a pen in highlighter
        // yellow is hard to read: a color that is still the old ink's default follows.
        if preset.colorHex == preset.ink.defaultColorHex { preset.colorHex = ink.defaultColorHex }
        preset.ink = ink
        preset.width = ink.mediumWidth
        preset.widthChoices = ink.widthChoices
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
        guard eraserWidthChoices.contains(width), eraserWidth != width else { return }
        eraserWidth = width
    }

    /// Gives one of the eraser's three sizes another width, within `eraserWidthRange`, and
    /// erases with it.
    func changeEraserWidthChoice(at choiceIndex: Int, to width: Double) {
        guard eraserWidthChoices.indices.contains(choiceIndex), width.isFinite else { return }
        let erasingWidth = min(max(width, Self.eraserWidthRange.lowerBound), Self.eraserWidthRange.upperBound)
        if eraserWidthChoices[choiceIndex] != erasingWidth { eraserWidthChoices[choiceIndex] = erasingWidth }
        if eraserWidth != erasingWidth { eraserWidth = erasingWidth }
    }

    var selection: PencilToolSelection {
        PencilToolSelection(kind: toolInUse, preset: presetInUse, erasesWholeStrokes: erasesWholeStrokes,
                            eraserWidth: eraserWidth, isRulerActive: isRulerActive)
    }
}

/// One of the bar's three sizes: of the ink in use, or of the pixel eraser.
enum PencilSizeChoice: Equatable {
    case ink(choiceIndex: Int)
    case eraser(choiceIndex: Int)

    var choiceIndex: Int {
        switch self {
        case .ink(let choiceIndex), .eraser(let choiceIndex): choiceIndex
        }
    }
}

/// How large the bar draws the dot of one of its sizes: by the width it stands for, so a
/// width changed in its popover shows on the bar at once, and the dots of every ink compare.
/// Widths run from half a point (monoline) to a hundred (the eraser), far more than a dot
/// beside the tools can show as drawn, so the dot grows with the width's logarithm, within a
/// range that stays visible and fits the 28-point button: each of a tool's three starting
/// sizes is about two points from the next.
enum PencilSizeDot {
    static let smallestDiameter: Double = 3.5
    static let largestDiameter: Double = 22
    /// The widths drawn as the smallest and the largest dot; narrower and wider ones are clamped.
    static let narrowestWidth: Double = 0.5
    static let widestWidth: Double = 60

    static func diameter(forWidth width: Double) -> Double {
        guard width.isFinite, width > narrowestWidth else { return smallestDiameter }
        let fraction = min(log(width / narrowestWidth) / log(widestWidth / narrowestWidth), 1)
        return smallestDiameter + (largestDiameter - smallestDiameter) * fraction
    }
}

/// Widths as people speak of a pen on paper: millimeters, a point being 1/72 inch on the
/// page or the drawing.
enum PencilWidthText {
    static let millimetersPerPoint = 25.4 / 72

    static func millimeters(_ widthInPoints: Double) -> String {
        (widthInPoints * millimetersPerPoint).formatted(.number.precision(.fractionLength(1))) + " mm"
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit

extension PencilInk {
    /// The inks this system draws with.
    static var availableInks: [PencilInk] { allCases }

    var inkType: PKInkingTool.InkType {
        switch self {
        case .pen: return .pen
        case .monoline: return .monoline
        case .fountainPen: return .fountainPen
        case .reedPen: return .reed
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
        case .lasso, .laser, .readAloud, .text: PKLassoTool()
        }
    }
}
#endif
