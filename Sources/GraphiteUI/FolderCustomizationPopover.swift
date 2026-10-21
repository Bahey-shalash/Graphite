import SwiftUI
import GraphiteCore

/// A folder's look, chosen as in Finder's folder popover: a large preview with the folder's
/// name, one row of colors, the symbols in sections, then Clear and Emoji. Each choice is
/// applied at once, as Finder applies it.
struct FolderCustomizationPopover: View {
    let folderName: String
    let apply: (FolderStyle?) -> Void
    @State private var draft: FolderStyle

    static let width: CGFloat = 330
    private static let previewSymbolPoints: CGFloat = 84
    private static let symbolGridHeight: CGFloat = 250
    private static let symbolCellPoints: CGFloat = 38

    init(folderName: String, style: FolderStyle?, apply: @escaping (FolderStyle?) -> Void) {
        self.folderName = folderName
        self.apply = apply
        _draft = State(initialValue: style ?? FolderStyle())
    }

    var body: some View {
        VStack(spacing: 12) {
            preview
            FolderColorSwatches(color: draft.color) { color in change { style in style.color = color } }
            Divider()
            symbolGrid
            Divider()
            HStack {
                Button("Clear") { change { style in style = FolderStyle() } }
                    .disabled(draft.isPlain)
                Spacer()
                EmojiInputButton(currentEmoji: currentEmoji) { emoji in change { style in style.mark = .emoji(emoji) } }
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: Self.width)
    }

    private var currentEmoji: String? {
        if case .emoji(let emojiText) = draft.mark { emojiText } else { nil }
    }

    private var preview: some View {
        VStack(spacing: 4) {
            LibraryFolderArtwork(style: draft, symbolPointSize: Self.previewSymbolPoints)
                .frame(height: Self.previewSymbolPoints * 1.05)
            Text(folderName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(draft.isPlain ? "\(folderName), plain folder" : "\(folderName), \(draft.spokenDescription)")
    }

    private var symbolGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(FolderSymbolCatalog.sections) { section in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.symbolCellPoints), spacing: 4)], spacing: 4) {
                            ForEach(section.symbolNames, id: \.self) { symbolName in symbolButton(symbolName) }
                        }
                    } header: {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .frame(height: Self.symbolGridHeight)
    }

    private func symbolButton(_ symbolName: String) -> some View {
        let isChosen = draft.mark == .symbol(symbolName)
        return Button {
            // Choosing the chosen symbol again takes it off, as in Finder.
            change { style in style.mark = isChosen ? nil : .symbol(symbolName) }
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 17))
                .frame(width: Self.symbolCellPoints, height: Self.symbolCellPoints)
                .foregroundStyle(isChosen ? Color.white : Color.secondary)
                .background {
                    if isChosen { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FolderSymbolCatalog.spokenName(of: symbolName))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func change(_ edit: (inout FolderStyle) -> Void) {
        edit(&draft)
        apply(draft.isPlain ? nil : draft)
    }
}

/// Finder's row of colors: no color (a crossed-out tag), the seven tag colors, and any other
/// color from the system's color picker. The chosen one is ringed.
private struct FolderColorSwatches: View {
    let color: FolderColor?
    let choose: (FolderColor?) -> Void
    @Environment(\.self) private var environment

    private static let swatchPoints: CGFloat = 24

    var body: some View {
        HStack(spacing: 7) {
            swatch(for: nil) {
                Circle().fill(.background)
                    .overlay(Circle().strokeBorder(.tertiary, lineWidth: 1))
                    .overlay(CrossedOutLine().stroke(.secondary, lineWidth: 1.5))
            }
            ForEach(FolderColor.tagColors, id: \.self) { tagColor in
                swatch(for: tagColor) { Circle().fill(tagColor.tileColor) }
            }
            ColorPicker("Other Color", selection: otherColorSelection, supportsOpacity: false)
                .labelsHidden()
                .frame(width: Self.swatchPoints, height: Self.swatchPoints)
                .overlay { if isOtherColor { ring } }
                .accessibilityLabel(isOtherColor ? "Other Color, selected" : "Other Color")
        }
        .frame(maxWidth: .infinity)
    }

    /// A color that is not one of the tag colors: chosen with the picker, or kept from an older build.
    private var isOtherColor: Bool {
        guard let color else { return false }
        return !FolderColor.tagColors.contains(color)
    }

    private var otherColorSelection: Binding<Color> {
        // The well shows the other color while it is the chosen one, and stays empty otherwise.
        Binding(get: { isOtherColor ? color.tileColor : .clear }, set: { pickedColor in
            let resolved = pickedColor.resolve(in: environment)
            choose(.custom(red: Self.byte(resolved.red), green: Self.byte(resolved.green), blue: Self.byte(resolved.blue)))
        })
    }

    private static func byte(_ component: Float) -> UInt8 {
        UInt8((min(max(component, 0), 1) * 255).rounded())
    }

    private func swatch(for swatchColor: FolderColor?, @ViewBuilder fill: () -> some View) -> some View {
        let isChosen = swatchColor == color
        return Button { choose(swatchColor) } label: {
            fill()
                .frame(width: Self.swatchPoints, height: Self.swatchPoints)
                .overlay { if isChosen { ring } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatchColor?.title ?? "No Color")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var ring: some View {
        Circle().strokeBorder(.primary.opacity(0.55), lineWidth: 2).padding(-4)
    }
}

/// The line through the no-color swatch, from its lower left to its upper right.
private struct CrossedOutLine: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        return path
    }
}
