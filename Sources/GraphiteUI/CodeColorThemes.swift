import SwiftUI
import GraphiteCore

/// The colors code blocks are drawn in (Settings › Editor › Code Theme). Obsidian's own
/// colors follow the vault's Obsidian theme where it sets them; each other theme brings its
/// own box and text colors, in a light and a dark version that follow the appearance, as
/// the editors' themes they are named after do.
enum CodeColorTheme: String, CaseIterable, Identifiable, Codable, Sendable {
    case obsidian, oneMonokai, dracula, github, solarized, xcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .obsidian: "Obsidian"
        case .oneMonokai: "One Monokai"
        case .dracula: "Dracula"
        case .github: "GitHub"
        case .solarized: "Solarized"
        case .xcode: "Xcode"
        }
    }

    /// The theme's light and dark versions, nil for Obsidian's, which `CodeSyntaxColors` makes.
    var variants: (light: CodeThemeVariant, dark: CodeThemeVariant)? {
        switch self {
        case .obsidian:
            nil
        case .oneMonokai:
            // One Monokai in dark appearance, Atom's One Light, its sibling, in light.
            (CodeThemeVariant(background: "#fafafa", text: "#383a42", colors: [
                .keyword: "#a626a4", .typeName: "#c18401", .function: "#4078f2", .string: "#50a14f", .number: "#986801", .constant: "#986801",
                .comment: "#a0a1a7", .preprocessor: "#a626a4", .attribute: "#4078f2", .property: "#e45649", .variable: "#e45649", .operator: "#0184bc",
            ]),
             CodeThemeVariant(background: "#282c34", text: "#abb2bf", colors: [
                .keyword: "#f92672", .typeName: "#56b6c2", .function: "#98c379", .string: "#e5c07b", .number: "#c678dd", .constant: "#c678dd",
                .comment: "#676f7d", .preprocessor: "#f92672", .attribute: "#61afef", .property: "#56b6c2", .variable: "#e06c75", .operator: "#f92672",
             ]))
        case .dracula:
            // Dracula, and Alucard, its light version.
            (CodeThemeVariant(background: "#fffbeb", text: "#1f1f1f", colors: [
                .keyword: "#a3144d", .typeName: "#036a96", .function: "#14710a", .string: "#846e15", .number: "#644ac9", .constant: "#644ac9",
                .comment: "#6c664b", .preprocessor: "#a3144d", .attribute: "#14710a", .property: "#036a96", .variable: "#a34d14", .operator: "#a3144d",
            ]),
             CodeThemeVariant(background: "#282a36", text: "#f8f8f2", colors: [
                .keyword: "#ff79c6", .typeName: "#8be9fd", .function: "#50fa7b", .string: "#f1fa8c", .number: "#bd93f9", .constant: "#bd93f9",
                .comment: "#6272a4", .preprocessor: "#ff79c6", .attribute: "#50fa7b", .property: "#8be9fd", .variable: "#ffb86c", .operator: "#ff79c6",
             ]))
        case .github:
            // GitHub's Light Default and Dark Default.
            (CodeThemeVariant(background: "#f6f8fa", text: "#1f2328", colors: [
                .keyword: "#cf222e", .typeName: "#953800", .function: "#8250df", .string: "#0a3069", .number: "#0550ae", .constant: "#0550ae",
                .comment: "#6e7781", .preprocessor: "#cf222e", .attribute: "#8250df", .property: "#0550ae", .variable: "#953800", .operator: "#cf222e",
            ]),
             CodeThemeVariant(background: "#161b22", text: "#e6edf3", colors: [
                .keyword: "#ff7b72", .typeName: "#ffa657", .function: "#d2a8ff", .string: "#a5d6ff", .number: "#79c0ff", .constant: "#79c0ff",
                .comment: "#8b949e", .preprocessor: "#ff7b72", .attribute: "#d2a8ff", .property: "#79c0ff", .variable: "#ffa657", .operator: "#ff7b72",
             ]))
        case .solarized:
            (CodeThemeVariant(background: "#fdf6e3", text: "#657b83", colors: [
                .keyword: "#859900", .typeName: "#b58900", .function: "#268bd2", .string: "#2aa198", .number: "#d33682", .constant: "#cb4b16",
                .comment: "#93a1a1", .preprocessor: "#cb4b16", .attribute: "#6c71c4", .property: "#268bd2", .variable: "#cb4b16", .operator: "#859900",
            ]),
             CodeThemeVariant(background: "#002b36", text: "#839496", colors: [
                .keyword: "#859900", .typeName: "#b58900", .function: "#268bd2", .string: "#2aa198", .number: "#d33682", .constant: "#cb4b16",
                .comment: "#586e75", .preprocessor: "#cb4b16", .attribute: "#6c71c4", .property: "#268bd2", .variable: "#cb4b16", .operator: "#859900",
             ]))
        case .xcode:
            // Xcode's Default (Light) and Default (Dark).
            (CodeThemeVariant(background: "#f5f5f7", text: "#262626", colors: [
                .keyword: "#9b2393", .typeName: "#0b4f79", .function: "#326d74", .string: "#c41a16", .number: "#1c00cf", .constant: "#1c00cf",
                .comment: "#5d6c79", .preprocessor: "#643820", .attribute: "#815f03", .property: "#0f68a0", .variable: "#6c36a9",
            ]),
             CodeThemeVariant(background: "#292a30", text: "#dfdfe0", colors: [
                .keyword: "#fc5fa3", .typeName: "#5dd8ff", .function: "#67b7a4", .string: "#fc6a5d", .number: "#d0bf69", .constant: "#d0bf69",
                .comment: "#7f8c98", .preprocessor: "#fd8f3f", .attribute: "#bf8555", .property: "#41a1c0", .variable: "#a167e6",
             ]))
        }
    }
}

/// One appearance of a code theme, in `#rrggbb`. A kind the theme leaves out, such as names
/// in most themes, takes the text color.
struct CodeThemeVariant {
    let background: String
    let text: String
    let colors: [CodeTokenKind: String]
}

/// The colors one code block is drawn in, resolved for a code theme and a vault theme.
/// Each color follows light, dark and Increase Contrast by itself.
struct CodePalette {
    let colors: [CodeTokenKind: PlatformColor]
    /// Code that is no token, such as punctuation, and the text of an unknown language.
    let text: PlatformColor
    let background: PlatformColor
    /// The language label, and a fence while it shows.
    let quietText: PlatformColor
    /// The thin lines that show each level of indentation.
    let guide: PlatformColor
    /// The box's one-point border.
    let border: PlatformColor

    func color(for kind: CodeTokenKind) -> PlatformColor { colors[kind] ?? text }
}

extension CodeColorTheme {
    /// Contrast a theme's code keeps against its box, as a vault theme's text keeps
    /// against its page (`ThemeContrastGuard`); comments, which themes keep quiet, need less.
    static func minimumContrast(of kind: CodeTokenKind?, increased: Bool) -> Double {
        let isQuiet = kind == .comment
        if increased { return isQuiet ? AccentLegibility.minimumTextContrast : AccentLegibility.increasedTextContrast }
        return isQuiet ? ThemeContrastGuard.largeTextContrast : AccentLegibility.minimumTextContrast
    }

    /// The palette of a theme other than Obsidian's: the theme's colors, each moved just
    /// enough to read on the theme's own box (`minimumContrast(of:increased:)`), keeping its
    /// hue; most already do.
    @MainActor
    func palette() -> CodePalette? {
        guard let variants else { return nil }
        func color(light lightHex: String, dark darkHex: String, kind: CodeTokenKind?) -> PlatformColor {
            guard let light = ThemeColor(hex: lightHex), let dark = ThemeColor(hex: darkHex),
                  let lightBackground = ThemeColor(hex: variants.light.background), let darkBackground = ThemeColor(hex: variants.dark.background) else {
                return MarkdownTextStyler.primaryTextColor
            }
            func readable(_ color: ThemeColor, on background: ThemeColor, increased: Bool) -> PlatformColor {
                NoteThemeStyle.platformColor(ThemeContrastGuard.readable(color, on: background, target: Self.minimumContrast(of: kind, increased: increased)))
            }
            return PlatformColor.appearanceDependent(AppearanceVariants(
                light: readable(light, on: lightBackground, increased: false), lightIncreasedContrast: readable(light, on: lightBackground, increased: true),
                dark: readable(dark, on: darkBackground, increased: false), darkIncreasedContrast: readable(dark, on: darkBackground, increased: true)))
        }
        var colors: [CodeTokenKind: PlatformColor] = [:]
        for kind in CodeTokenKind.allCases {
            guard let light = variants.light.colors[kind], let dark = variants.dark.colors[kind] else { continue }
            colors[kind] = color(light: light, dark: dark, kind: kind)
        }
        let background = PlatformColor.appearanceDependent(AppearanceVariants(
            light: ThemeColor(hex: variants.light.background).map(NoteThemeStyle.platformColor) ?? .white,
            lightIncreasedContrast: ThemeColor(hex: variants.light.background).map(NoteThemeStyle.platformColor) ?? .white,
            dark: ThemeColor(hex: variants.dark.background).map(NoteThemeStyle.platformColor) ?? .black,
            darkIncreasedContrast: ThemeColor(hex: variants.dark.background).map(NoteThemeStyle.platformColor) ?? .black))
        let comment = color(light: variants.light.colors[.comment] ?? variants.light.text, dark: variants.dark.colors[.comment] ?? variants.dark.text, kind: .comment)
        func faint(_ hex: String, opacity: Double) -> PlatformColor {
            ThemeColor(hex: hex).map { themeColor in NoteThemeStyle.platformColor(ThemeColor(red: themeColor.red, green: themeColor.green, blue: themeColor.blue, alpha: opacity)) } ?? .gray
        }
        let guide = PlatformColor.appearanceDependent(AppearanceVariants(
            light: faint(variants.light.text, opacity: 0.18), lightIncreasedContrast: faint(variants.light.text, opacity: 0.35),
            dark: faint(variants.dark.text, opacity: 0.18), darkIncreasedContrast: faint(variants.dark.text, opacity: 0.35)))
        let border = PlatformColor.appearanceDependent(AppearanceVariants(
            light: faint(variants.light.text, opacity: 0.16), lightIncreasedContrast: faint(variants.light.text, opacity: 0.4),
            dark: faint(variants.dark.text, opacity: 0.16), darkIncreasedContrast: faint(variants.dark.text, opacity: 0.4)))
        return CodePalette(colors: colors, text: color(light: variants.light.text, dark: variants.dark.text, kind: nil), background: background, quietText: comment,
                           guide: guide, border: border)
    }
}

extension ThemeColor {
    /// `#rrggbb`.
    init?(hex: String) {
        guard let canonical = TextColorMarkup.canonicalHex(hex) else { return nil }
        let digits = Array(canonical.dropFirst())
        func component(_ position: Int) -> Double { Double(Int(String(digits[position..<position + 2]), radix: 16) ?? 0) / 255 }
        self.init(red: component(0), green: component(2), blue: component(4))
    }
}

extension EnvironmentValues {
    /// The code theme chosen in Settings › Editor, for reading view and rendered blocks.
    @Entry var codeColorTheme: CodeColorTheme = .obsidian
}

/// A few lines of C++ in a code theme, as a code block shows them, beside the theme's picker.
struct CodeThemePreview: View {
    let codeTheme: CodeColorTheme
    let noteTheme: NoteThemeStyle?
    @Environment(\.noteTypography) private var typography

    private static let sample = """
        // Sum of the values
        uint32_t SumArray(uint32_t *input, uint32_t length) {
            uint32_t sum = 0;
            for (uint32_t i = 0; i < length; ++i) sum += input[i];
            return sum;
        }
        """

    var body: some View {
        let palette = CodeSyntaxColors.palette(codeTheme: codeTheme, noteTheme: noteTheme)
        Text(highlightedSample(palette: palette))
            .font(typography.monospaceSwiftUIFont(size: 12))
            .lineSpacing(3)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(palette.background), in: RoundedRectangle(cornerRadius: CodeSyntaxColors.blockCornerRadius(theme: noteTheme), style: .continuous))
            .accessibilityLabel("Preview of \(codeTheme.title) code colors")
    }

    private func highlightedSample(palette: CodePalette) -> AttributedString {
        var sample = AttributedString(Self.sample)
        sample.foregroundColor = Color(palette.text)
        guard let language = CodeLanguage.named("cpp") else { return sample }
        for token in CodeSyntaxHighlighter.tokens(in: Self.sample, language: language) {
            guard let range = Range(token.range, in: Self.sample), let attributedRange = Range(range, in: sample) else { continue }
            sample[attributedRange].foregroundColor = Color(palette.color(for: token.kind))
        }
        return sample
    }
}
