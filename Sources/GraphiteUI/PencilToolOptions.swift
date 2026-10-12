import SwiftUI
import GraphiteCore

#if canImport(UIKit)
import UIKit
import PencilKit

/// The width of one of the bar's sizes, opened by a second tap on the size in use, as
/// Goodnotes does: a slider, the width in millimeters, and a stroke as wide in the tool's
/// color, or the eraser's outline. The size takes each width the slider gives at once, and
/// the tool draws with it.
struct PencilSizeEditor: View {
    @Bindable var toolbox: PencilToolbox
    let size: PencilSizeChoice

    /// The tallest the sample is drawn; a broader width shows as this.
    private static let sampleSide: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            sample
                .frame(maxWidth: .infinity, minHeight: Self.sampleSide)
                .accessibilityHidden(true)
            HStack(spacing: 12) {
                Text(PencilWidthText.millimeters(width))
                    .monospacedDigit()
                    .frame(minWidth: 64, alignment: .leading)
                Slider(value: Binding(get: { width }, set: { newWidth in changeWidth(to: newWidth) }), in: widthRange)
                    .accessibilityLabel(title)
                    .accessibilityValue(PencilWidthText.millimeters(width))
            }
            .font(.callout)
        }
        .padding(16)
        .frame(width: 320)
        .tint(.primary)
    }

    private var title: String {
        switch size {
        case .ink: "\(toolbox.presetInUse.ink.title) Width"
        case .eraser: "Eraser Width"
        }
    }

    private var width: Double {
        switch size {
        case .ink(let choiceIndex):
            toolbox.presetInUse.widthChoices.indices.contains(choiceIndex) ? toolbox.presetInUse.widthChoices[choiceIndex] : toolbox.presetInUse.width
        case .eraser(let choiceIndex):
            toolbox.eraserWidthChoices.indices.contains(choiceIndex) ? toolbox.eraserWidthChoices[choiceIndex] : toolbox.eraserWidth
        }
    }

    private var widthRange: ClosedRange<Double> {
        switch size {
        case .ink: toolbox.presetInUse.ink.widthRange
        case .eraser: PencilToolbox.eraserWidthRange
        }
    }

    private func changeWidth(to newWidth: Double) {
        switch size {
        case .ink(let choiceIndex): toolbox.changeWidthChoice(at: choiceIndex, to: newWidth)
        case .eraser(let choiceIndex): toolbox.changeEraserWidthChoice(at: choiceIndex, to: newWidth)
        }
    }

    @ViewBuilder private var sample: some View {
        let shownWidth = min(max(CGFloat(width), 1), Self.sampleSide)
        switch size {
        case .ink:
            // A faint ink still shows its color, as on the bar.
            Capsule()
                .fill((Color(graphiteHex: toolbox.presetInUse.colorHex) ?? .primary).opacity(max(toolbox.presetInUse.opacity, 0.45)))
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
                .frame(height: shownWidth)
        case .eraser:
            Circle()
                .strokeBorder(Color.secondary, lineWidth: 1.5)
                .frame(width: shownWidth, height: shownWidth)
        }
    }
}

/// The options of the ink preset in use: which ink it is, its width and its opacity, and
/// adding or removing a preset.
struct PencilInkOptions: View {
    @Bindable var toolbox: PencilToolbox
    @AppStorage(EvenHighlighterPreference.key) private var highlighterIgnoresTilt = false
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
                        .accessibilityValue(PencilWidthText.millimeters(preset.width))
                }
                LabeledContent("Opacity") {
                    Slider(value: Binding(get: { toolbox.presetInUse.opacity }, set: { opacity in toolbox.chooseOpacity(opacity) }), in: InkPreset.opacityRange)
                        .accessibilityLabel("Opacity")
                        .accessibilityValue(preset.opacity.formatted(.percent.precision(.fractionLength(0))))
                }
                // Every highlighter, of the bar and of the floating palette, as in Settings.
                if preset.ink == .highlighter {
                    Toggle("Ignore Pencil Tilt", isOn: $highlighterIgnoresTilt)
                        .help("Draws the chosen width however Apple Pencil is tilted or turned")
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
