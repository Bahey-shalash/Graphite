import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit
import PencilKit

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
    /// The document's own controls, such as Write, Undo and Redo, where they have no
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
        .background(GraphiteChrome.barBackground)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The fixed bar's tools in one row: the ink presets, the eraser and the lasso; the width of
/// the tool in use; its color, from the favorite colors of Settings › Colors, or for a
/// highlighter from its own lighter colors there; then the shape tool, the ruler, and adding
/// an image. The row takes the width it needs where that fits and scrolls sideways where it
/// does not. The fixed bar shows it, and so does a side's tab bar where it has room.
///
/// A second tap on the ink in use opens its options: every ink PencilKit has, any width and
/// opacity, and adding or removing a preset. A second tap on the size in use, of an ink or
/// of the pixel eraser, opens its width, to change it.
///
/// The inks, the eraser and the lasso are drawn standing upright, as in Apple's palette,
/// each ink's tip in its color; the tool in use stands raised and has the selected trait,
/// so it is not told apart by color alone.
struct PencilToolRow: View {
    @Bindable var toolbox: PencilToolbox
    let favoriteColors: [PaletteColor]
    @Binding var drawsShapes: Bool
    /// Nil where images cannot be added.
    var addImage: (() -> Void)?
    /// The document's history, for the Undo and Redo of the palette Apple Pencil's squeeze opens.
    var undoAvailability: UndoAvailability?
    var rowHeight: CGFloat = PencilToolbarMetrics.height
    /// The highlighter's colors as Settings keeps them, followed so a change there shows on
    /// the bar at once, not only when the bar is made again.
    @AppStorage(GraphitePreferences.highlighterPaletteKey) private var storedHighlighterPalette: Data?
    @State private var showsInkOptions = false
    @AppStorage(LassoShape.preferenceKey) private var lassoShape = LassoShape.freehand
    @AppStorage(LaserPointerStyle.preferenceKey) private var laserPointerStyle = LaserPointerStyle.dot
    /// The size whose width is open for changing.
    @State private var adjustedSize: PencilSizeChoice?

    /// The colors offered while a highlighter is in use, in place of the favorite colors.
    private var highlighterColors: [PaletteColor] { GraphitePreferences.highlighterPalette(decoding: storedHighlighterPalette) }
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
            toolButton(.laser)
            separator
            switch toolbox.toolInUse {
            case .ink:
                ForEach(Array(toolbox.presetInUse.widthChoices.enumerated()), id: \.offset) { choiceIndex, width in
                    adjustableSizeButton(.ink(choiceIndex: choiceIndex), isChosen: toolbox.presetInUse.width == width) {
                        toolbox.useWidthChoice(at: choiceIndex)
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
                    ForEach(Array(toolbox.eraserWidthChoices.enumerated()), id: \.offset) { choiceIndex, width in
                        adjustableSizeButton(.eraser(choiceIndex: choiceIndex), isChosen: toolbox.eraserWidth == width) {
                            toolbox.chooseEraserWidth(width)
                        }
                    }
                }
                separator
            case .lasso:
                // Remembered for every canvas, as Goodnotes keeps its lasso's type.
                Picker("Lasso Type", selection: $lassoShape) {
                    ForEach(LassoShape.allCases) { shape in Text(shape.title).tag(shape) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                separator
            case .laser:
                Picker("Laser Pointer", selection: $laserPointerStyle) {
                    ForEach(LaserPointerStyle.allCases) { style in Text(style.title).tag(style) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                separator
            }
            // A highlighter marks text in light colors of its own; a pen writes in black and
            // the note colors.
            if toolbox.presetInUse.ink == .highlighter {
                ForEach(highlighterColors) { highlighterColor in colorButton(name: highlighterColor.name, hex: highlighterColor.hex) }
            } else {
                colorButton(name: "black", hex: PencilInk.pen.defaultColorHex)
                ForEach(favoriteColors) { favorite in colorButton(name: favorite.name, hex: favorite.hex) }
            }
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
        Hairline(axis: .vertical).frame(height: 20).padding(.horizontal, 6)
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

    /// One of the three sizes. A tap on another size draws with it; a second tap on the size
    /// in use opens its width.
    private func adjustableSizeButton(_ size: PencilSizeChoice, isChosen: Bool, choose: @escaping () -> Void) -> some View {
        buttons.sizeButton(choiceIndex: size.choiceIndex, isChosen: isChosen, opensWidthWhenChosen: true) {
            if isChosen { adjustedSize = size } else { choose() }
        }
        .popover(isPresented: Binding(get: { adjustedSize == size }, set: { isPresented in if !isPresented, adjustedSize == size { adjustedSize = nil } })) {
            PencilSizeEditor(toolbox: toolbox, size: size)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func colorButton(name: String, hex: String) -> some View { buttons.colorButton(name: name, hex: hex) }

    private func toggleButton(_ title: String, symbolName: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: isOn.wrappedValue ? .semibold : .regular))
                .frame(width: buttonSide, height: buttonSide)
                .background(isOn.wrappedValue ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
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
                          addImage: { pictureSource = .photoLibrary }, undoAvailability: session.undoAvailability, rowHeight: PencilToolbarMetrics.heightInTabBar)
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

    /// Whether the system's floating palette is over the page: it has Undo and Redo of its
    /// own, so the document's would repeat them. A compact width always uses the palette, and
    /// arranging a picture puts it away.
    func showsFloatingPencilPalette(style: PencilToolbarStyle, showsTools: Bool, horizontalSizeClass: UserInterfaceSizeClass?, isFocused: Bool) -> Bool {
        (style == .floating || horizontalSizeClass == .compact) && showsTools && isFocused && isWriting && !isProtected && selectedPicture == nil
    }
}
#endif
