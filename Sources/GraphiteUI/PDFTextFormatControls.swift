#if canImport(UIKit)
import SwiftUI
import GraphiteCore
import GraphiteApple

/// The format of typed text on a PDF page: its font, size, color, bold, italic and underline,
/// and the box's alignment, fill and border. The same controls format the box selected or
/// typed in, from its format popover, and the next new box, from the text tool's options on
/// the fixed bar; each change is handed to `apply` as a `PDFTextBoxFormatChange`.
struct PDFTextFormatControls: View {
    let attributes: PDFTextAttributes
    let style: PDFTextBoxStyle
    let apply: (PDFTextBoxFormatChange) -> Void
    /// The full set, in a popover, or the font, size and faces only, on a bar.
    var isCompact = false
    @AppStorage(GraphitePreferences.colorPaletteKey) private var storedColorPalette: Data?

    init(attributes: PDFTextAttributes, style: PDFTextBoxStyle, apply: @escaping (PDFTextBoxFormatChange) -> Void, isCompact: Bool = false) {
        self.attributes = attributes
        self.style = style
        self.apply = apply
        self.isCompact = isCompact
    }

    /// Sizes offered, in points.
    static let offeredSizes: [Double] = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 64, 72]
    /// Light fills that keep black text readable.
    static let offeredFills: [(name: String, color: PDFTextColor)] = [
        ("White", PDFTextColor(red: 1, green: 1, blue: 1)), ("Yellow", PDFTextColor(red: 1, green: 0.96, blue: 0.62)),
        ("Green", PDFTextColor(red: 0.83, green: 0.95, blue: 0.8)), ("Blue", PDFTextColor(red: 0.82, green: 0.9, blue: 1)),
        ("Pink", PDFTextColor(red: 1, green: 0.85, blue: 0.9)),
    ]

    var body: some View {
        if isCompact {
            HStack(spacing: 10) { fontMenu; sizeMenu; faceButtons; colorMenu }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) { fontMenu; sizeMenu }
                HStack(spacing: 10) { faceButtons; Spacer(minLength: 8); alignmentPicker }
                HStack(spacing: 10) { colorRow }
                HStack(spacing: 10) { fillMenu; borderToggle }
            }
            .padding(16)
            .frame(minWidth: 320)
        }
    }

    private var fontMenu: some View {
        Menu {
            let families = PDFTextBoxFonts.offeredFamilies.contains(attributes.fontFamily)
                ? PDFTextBoxFonts.offeredFamilies : [attributes.fontFamily] + PDFTextBoxFonts.offeredFamilies
            ForEach(families, id: \.self) { family in
                Button {
                    apply(.fontFamily(family))
                } label: {
                    if family == attributes.fontFamily { Label(family, systemImage: "checkmark") } else { Text(family) }
                }
            }
        } label: {
            Text(attributes.fontFamily).lineLimit(1).frame(minWidth: 90, alignment: .leading)
        }
        .accessibilityLabel("Font")
        .accessibilityValue(attributes.fontFamily)
    }

    private var sizeMenu: some View {
        HStack(spacing: 4) {
            Button("Smaller", systemImage: "textformat.size.smaller") {
                apply(.fontSize(max(attributes.fontSize - 1, PDFTextAttributes.fontSizeRange.lowerBound)))
            }
            Menu {
                ForEach(Self.offeredSizes, id: \.self) { size in
                    Button("\(PDFTextFormatControls.sizeText(size)) pt") { apply(.fontSize(size)) }
                }
            } label: {
                Text("\(Self.sizeText(attributes.fontSize)) pt").monospacedDigit().frame(minWidth: 44)
            }
            .accessibilityLabel("Size")
            .accessibilityValue("\(Self.sizeText(attributes.fontSize)) points")
            Button("Larger", systemImage: "textformat.size.larger") {
                apply(.fontSize(min(attributes.fontSize + 1, PDFTextAttributes.fontSizeRange.upperBound)))
            }
        }
        .labelStyle(.iconOnly)
    }

    static func sizeText(_ size: Double) -> String {
        size.rounded() == size ? String(Int(size)) : size.formatted(.number.precision(.fractionLength(1)))
    }

    private var faceButtons: some View {
        HStack(spacing: 4) {
            faceToggle("Bold", systemImage: "bold", isOn: attributes.isBold) { apply(.bold(!attributes.isBold)) }
            faceToggle("Italic", systemImage: "italic", isOn: attributes.isItalic) { apply(.italic(!attributes.isItalic)) }
            faceToggle("Underline", systemImage: "underline", isOn: attributes.isUnderlined) { apply(.underline(!attributes.isUnderlined)) }
        }
    }

    private func faceToggle(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: isOn ? .bold : .regular))
                .frame(width: 34, height: 30)
                .background(isOn ? PencilToolbarMetrics.selectedFill : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var alignmentPicker: some View {
        Picker("Alignment", selection: Binding(get: { style.alignment }, set: { alignment in apply(.alignment(alignment)) })) {
            Image(systemName: "text.alignleft").accessibilityLabel("Left").tag(PDFTextAlignment.left)
            Image(systemName: "text.aligncenter").accessibilityLabel("Center").tag(PDFTextAlignment.center)
            Image(systemName: "text.alignright").accessibilityLabel("Right").tag(PDFTextAlignment.right)
            Image(systemName: "text.justify").accessibilityLabel("Justified").tag(PDFTextAlignment.justified)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    /// Black and the favorite colors of Settings › Colors, then any color.
    private var colorChoices: [(name: String, color: PDFTextColor)] {
        [("Black", .black)] + GraphitePreferences.colorPalette(decoding: storedColorPalette).compactMap { favorite in
            PDFTextColor(hex: favorite.hex).map { color in (favorite.name, color) }
        }
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            ForEach(colorChoices, id: \.name) { choice in colorSwatch(choice.name, choice.color) }
            ColorPicker("Other Color", selection: Binding(get: { Color(textColor: attributes.color) }, set: { color in
                if let hex = color.sRGBHex, let picked = PDFTextColor(hex: hex) { apply(.color(picked)) }
            }), supportsOpacity: false)
                .labelsHidden()
        }
    }

    private var colorMenu: some View {
        Menu {
            ForEach(colorChoices, id: \.name) { choice in Button(choice.name) { apply(.color(choice.color)) } }
        } label: {
            Circle().fill(Color(textColor: attributes.color)).frame(width: 20, height: 20)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5) }
        }
        .accessibilityLabel("Text Color")
    }

    private func colorSwatch(_ name: String, _ color: PDFTextColor) -> some View {
        let isInUse = attributes.color == color
        return Button { apply(.color(color)) } label: {
            Circle().fill(Color(textColor: color)).frame(width: 22, height: 22)
                .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
                .overlay { if isInUse { Circle().strokeBorder(.primary, lineWidth: 2).frame(width: 30, height: 30) } }
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }

    private var fillMenu: some View {
        Menu {
            Button("No Fill") { apply(.fill(nil)) }
            ForEach(Self.offeredFills, id: \.name) { fill in Button(fill.name) { apply(.fill(fill.color)) } }
        } label: {
            Label(style.fillColor == nil ? "No Fill" : "Fill", systemImage: style.fillColor == nil ? "square.dashed" : "square.fill")
        }
        .accessibilityLabel("Fill")
    }

    private var borderToggle: some View {
        Toggle("Border", isOn: Binding(get: { style.hasBorder },
                                       set: { hasBorder in apply(.border(width: hasBorder ? PDFTextBoxFormatChange.standardBorderWidth : 0)) }))
            .toggleStyle(.button)
    }
}

extension Color {
    init(textColor: PDFTextColor) {
        self.init(.sRGB, red: textColor.red, green: textColor.green, blue: textColor.blue)
    }
}
#endif
