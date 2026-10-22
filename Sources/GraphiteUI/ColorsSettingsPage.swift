import SwiftUI
import GraphiteCore

struct ColorsSettingsPage: View {
    @Bindable var preferences: GraphitePreferences

    var body: some View {
        Form {
            Section {
                ForEach($preferences.colorPalette) { $color in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            ColorPicker("Color", selection: Binding(get: { Color(graphiteHex: color.hex) ?? .red }, set: { newColor in
                                if let hex = newColor.sRGBHex { color.hex = hex }
                            }), supportsOpacity: false)
                            .labelsHidden()
                            TextField("Name", text: $color.name)
                                .autocorrectionDisabled()
                                #if canImport(UIKit)
                                .textInputAutocapitalization(.never)
                                #endif
                            Text(color.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let problem = PaletteColorNames.problem(with: color, in: preferences.colorPalette) {
                            Text(problem).font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
                .onDelete { offsets in preferences.colorPalette.remove(atOffsets: offsets) }
                .onMove { offsets, destination in preferences.colorPalette.move(fromOffsets: offsets, toOffset: destination) }
                Button("Add Color", systemImage: "plus") {
                    preferences.colorPalette.append(PaletteColor(name: PaletteColorNames.unusedName(in: preferences.colorPalette), hex: "#888888"))
                }
                Button("Restore Default Palette", systemImage: "arrow.counterclockwise") { preferences.colorPalette = PaletteColor.defaultPalette }
            } header: {
                Text("Palette")
            } footer: {
                Text("Format › Color writes the hex color, as the Colors plugin for Obsidian does (`~={#e93147}text=~`), so notes look the same in both apps. A note written with a name, as in `~={red}text=~`, takes the color of that name here, so renaming or removing a color changes it.\n\nThe same colors are the Favorite Colors of the Pencil tools, for drawings and PDFs. A highlighter has its own, below.")
                    .formFooterAlignment()
            }
            Section {
                ForEach($preferences.highlighterPalette) { $color in
                    HStack(spacing: 12) {
                        ColorPicker("Color", selection: Binding(get: { Color(graphiteHex: color.hex) ?? .yellow }, set: { newColor in
                            if let hex = newColor.sRGBHex { color.hex = hex }
                        }), supportsOpacity: false)
                        .labelsHidden()
                        TextField("Name", text: $color.name)
                            .autocorrectionDisabled()
                            #if canImport(UIKit)
                            .textInputAutocapitalization(.never)
                            #endif
                        Text(color.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in preferences.highlighterPalette.remove(atOffsets: offsets) }
                .onMove { offsets, destination in preferences.highlighterPalette.move(fromOffsets: offsets, toOffset: destination) }
                Button("Add Color", systemImage: "plus") {
                    preferences.highlighterPalette.append(PaletteColor(name: PaletteColorNames.unusedName(in: preferences.highlighterPalette), hex: "#f6d743"))
                }
                Button("Restore Default Highlighter Colors", systemImage: "arrow.counterclockwise") {
                    preferences.highlighterPalette = PaletteColor.defaultHighlighterPalette
                }
            } header: {
                Text("Highlighter")
            } footer: {
                Text("The colors the Pencil tools offer while a highlighter is in use, in place of the palette above. On a PDF page, a highlighter stroke covers the text under it: to keep the text readable, lower the highlighter's opacity in its options, or select the text and choose Highlight. Notes do not use these colors.")
                    .formFooterAlignment()
            }
        }
        .navigationTitle("Colors")
    }
}

/// Which palette names a note can refer to, as in `~={red}text=~`.
enum PaletteColorNames {
    /// Why notes cannot use this color's name, or nil when they can.
    static func problem(with color: PaletteColor, in palette: [PaletteColor]) -> String? {
        let name = color.name
        if name.isEmpty { return "Name this color to use it in notes and menus." }
        if name.contains(where: { character in character.isWhitespace || character == "}" }) { return "Notes cannot use a name with spaces or “}”." }
        if TextColorMarkup.canonicalHex(name) != nil { return "Notes read this name as a hex color, not as this color." }
        if palette.first(where: { paletteColor in paletteColor.name == name })?.id != color.id { return "Another color above has this name, and notes use that one." }
        return nil
    }

    /// A name no color in the palette has yet.
    static func unusedName(in palette: [PaletteColor]) -> String {
        let usedNames = Set(palette.map(\.name))
        var number = palette.count + 1
        while usedNames.contains("color-\(number)") { number += 1 }
        return "color-\(number)"
    }
}
