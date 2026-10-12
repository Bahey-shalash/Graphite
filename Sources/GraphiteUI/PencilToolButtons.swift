import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit
import PencilKit

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
            glyphLabel(PencilToolGlyph(tool: .ink(preset.ink), inkHex: preset.colorHex, inkOpacity: preset.opacity, isInUse: isInUse))
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
            glyphLabel(PencilToolGlyph(tool: PencilToolGlyph.Tool(kind: kind), isInUse: isInUse))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    /// A tool centered in the row, taking touches over the row's whole height.
    private func glyphLabel(_ glyph: PencilToolGlyph) -> some View {
        glyph
            .frame(width: buttonSide, height: rowHeight)
            .contentShape(Rectangle())
    }

    /// One of three sizes, of an ink or of the eraser. Where a second tap on the size in use
    /// opens its width, VoiceOver says so.
    /// One of the three sizes, as a dot as large as its width (`PencilSizeDot`).
    func sizeButton(choiceIndex: Int, width: Double, isChosen: Bool, opensWidthWhenChosen: Bool = false, choose: @escaping () -> Void) -> some View {
        let diameter = CGFloat(PencilSizeDot.diameter(forWidth: width))
        return Button(action: choose) {
            Circle()
                .fill(.primary)
                .frame(width: diameter, height: diameter)
                .frame(width: 28, height: buttonSide)
                .background(isChosen ? selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
                .frame(height: rowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(["Fine", "Medium", "Broad"][min(choiceIndex, 2)])
        .accessibilityValue(PencilWidthText.millimeters(width))
        .accessibilityHint(isChosen && opensWidthWhenChosen ? "Opens its width" : "")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    func colorButton(name: String, hex: String) -> some View {
        let isInUse = toolbox.toolInUse == .ink && TextColorMarkup.canonicalHex(hex) == toolbox.presetInUse.colorHex
        return Button {
            toolbox.chooseColor(hex: hex)
        } label: {
            Circle()
                .fill(Color(graphiteHex: hex) ?? .black)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
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
    /// The tools' row inside a tab bar: a little lower than the bar, which centers it.
    static let heightInTabBar: CGFloat = 40
    static let buttonSide: CGFloat = 36
    /// The background of the tool in use.
    static var selectedFill: AnyShapeStyle { AnyShapeStyle(Color(PlatformColor.primaryText(opacity: 0.1, increasedContrastOpacity: 0.2))) }
}

/// A tool of the bar as Apple's SF Symbols draw it: the ink's own symbol (`PencilInk.symbolName`),
/// the eraser or the lasso, with a short bar in the ink's color under an ink, so the bar shows
/// what each tool draws. The tool in use is drawn at full strength on the bar's faint fill,
/// as the sizes and colors beside it are, so it is marked by more than color.
struct PencilToolGlyph: View {
    enum Tool: Equatable {
        case ink(PencilInk)
        case eraser
        case lasso
        case laser

        /// The glyph of a tool other than an ink.
        init(kind: PencilToolKind) {
            switch kind {
            case .eraser, .ink: self = .eraser
            case .lasso: self = .lasso
            case .laser: self = .laser
            }
        }
    }

    let tool: Tool
    var inkHex: String = PencilInk.pen.defaultColorHex
    var inkOpacity: Double = 1
    let isInUse: Bool

    private var symbolName: String {
        switch tool {
        case .ink(let ink): ink.symbolName
        case .eraser: PencilToolKind.eraser.symbolName
        case .lasso: PencilToolKind.lasso.symbolName
        case .laser: PencilToolKind.laser.symbolName
        }
    }

    private var inkColor: Color? {
        guard case .ink = tool else { return nil }
        // A faint ink, such as a highlighter at low opacity, still shows which color it is.
        return (Color(graphiteHex: inkHex) ?? .black).opacity(max(inkOpacity, 0.45))
    }

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: isInUse ? .semibold : .regular))
                .foregroundStyle(isInUse ? .primary : .secondary)
                .frame(height: 22)
            Capsule()
                .fill(inkColor ?? .clear)
                .overlay { if inkColor != nil { Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) } }
                .frame(width: 16, height: 3)
        }
        .frame(width: PencilToolbarMetrics.buttonSide, height: PencilToolbarMetrics.buttonSide)
        .background(isInUse ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
#endif
