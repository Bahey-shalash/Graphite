import SwiftUI
import GraphiteCore
import Textual

/// The colors of highlighted code, the same in Live Preview, Source mode and reading view.
/// Graphite's own colors are Obsidian's default syntax colors (`--code-keyword` pink, types
/// in `--code-function` yellow, names in `--code-property` cyan, values purple, operators
/// red, strings green, comments and directives faint), one set for light appearance and one
/// for dark, moved just enough to read as text on the code background (`AccentLegibility`),
/// and further when Increase Contrast is on. Function names keep the code's text color, as
/// Obsidian's editor draws them. A vault theme's syntax colors win where it sets them.
@MainActor
enum CodeSyntaxColors {
    /// `#rrggbb` for light and dark appearance: Obsidian's `--color-*` and `--text-faint`.
    private static let hexByKind: [CodeTokenKind: (light: String, dark: String)] = [
        .keyword: ("#d53984", "#fa99cd"),
        .typeName: ("#e0ac00", "#e0de71"),
        .string: ("#08b94e", "#44cf6e"),
        .number: ("#7852ee", "#a882ff"),
        .constant: ("#7852ee", "#a882ff"),
        .comment: ("#ababab", "#666666"),
        .preprocessor: ("#ababab", "#666666"),
        .attribute: ("#ec7500", "#e9973f"),
        .property: ("#00bfbc", "#53dfdd"),
        .identifier: ("#00bfbc", "#53dfdd"),
        .variable: ("#ec7500", "#e9973f"),
        .operator: ("#e93147", "#fb464c"),
    ]

    private static let graphiteColors: [CodeTokenKind: PlatformColor] = hexByKind.compactMapValues { hexes in
        guard let light = PlatformColor(graphiteHex: hexes.light)?.sRGBComponents, let dark = PlatformColor(graphiteHex: hexes.dark)?.sRGBComponents else { return nil }
        func color(_ components: (red: Double, green: Double, blue: Double)) -> PlatformColor {
            PlatformColor.sRGB(red: components.red, green: components.green, blue: components.blue, alpha: 1)
        }
        return PlatformColor.appearanceDependent(AppearanceVariants(
            light: color(AccentLegibility.darkenedForLightBackground(red: light.red, green: light.green, blue: light.blue)),
            lightIncreasedContrast: color(AccentLegibility.darkenedForLightBackground(
                red: light.red, green: light.green, blue: light.blue, targetContrast: AccentLegibility.increasedTextContrast)),
            dark: color(AccentLegibility.lightenedForDarkBackground(red: dark.red, green: dark.green, blue: dark.blue)),
            darkIncreasedContrast: color(AccentLegibility.lightenedForDarkBackground(
                red: dark.red, green: dark.green, blue: dark.blue, targetContrast: AccentLegibility.increasedTextContrast))))
    }

    /// The color of `kind`: the vault theme's, else Graphite's.
    static func color(for kind: CodeTokenKind, theme: NoteThemeStyle?) -> PlatformColor {
        theme?.codeTokenColors[kind] ?? graphiteColors[kind] ?? theme?.codeColor ?? MarkdownTextStyler.primaryTextColor
    }

    static func graphiteColor(for kind: CodeTokenKind) -> PlatformColor {
        graphiteColors[kind] ?? MarkdownTextStyler.primaryTextColor
    }

    // MARK: The code block

    /// Behind a code block, in the editor and in reading view: the theme's, else a gray a
    /// step off the page, as Obsidian's `--code-background`.
    private static func blockBackground(theme: NoteThemeStyle?) -> PlatformColor {
        theme?.codeBlockBackground ?? theme?.codeBackground ?? graphiteBlockBackground
    }

    private static let graphiteBlockBackground = PlatformColor.appearanceDependent(AppearanceVariants(
        light: PlatformColor.sRGB(red: 0.960784, green: 0.960784, blue: 0.968627, alpha: 1),
        lightIncreasedContrast: PlatformColor.sRGB(red: 0.92, green: 0.92, blue: 0.93, alpha: 1),
        dark: PlatformColor.sRGB(red: 0.120543, green: 0.122844, blue: 0.141312, alpha: 1),
        darkIncreasedContrast: PlatformColor.sRGB(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)))

    /// The language's name at the block's top right, quiet as Obsidian's.
    private static func labelColor(theme: NoteThemeStyle?) -> PlatformColor {
        theme?.textMuted ?? MarkdownTextStyler.secondaryTextColor
    }

    /// The thin lines that show each level of indentation: the text color, faint, and less
    /// faint with Increase Contrast. Made in an appearance-dependent provider, because a
    /// system color given another opacity is drawn for the wrong appearance outside text.
    private static let indentationGuideColor = PlatformColor.primaryText(opacity: 0.14, increasedContrastOpacity: 0.3)

    /// The corner radius of a code block: the theme's, else 4 points.
    static func blockCornerRadius(theme: NoteThemeStyle?) -> CGFloat {
        theme?.codeBlockRadius.map { radius in CGFloat(min(radius, 24)) } ?? 4
    }

    /// The box's border: the vault theme's, when it gives one, else a light gray a step
    /// darker than the box (lighter in dark appearance).
    private static func blockBorder(theme: NoteThemeStyle?) -> PlatformColor {
        if let width = theme?.codeBlockBorderWidth, width > 0, let color = theme?.codeBlockBorderColor { return color }
        return graphiteBlockBorder
    }

    private static let graphiteBlockBorder = PlatformColor.appearanceDependent(AppearanceVariants(
        light: PlatformColor.sRGB(red: 210 / 255, green: 210 / 255, blue: 215 / 255, alpha: 1),
        lightIncreasedContrast: PlatformColor.sRGB(red: 160 / 255, green: 160 / 255, blue: 166 / 255, alpha: 1),
        dark: PlatformColor.sRGB(red: 66 / 255, green: 66 / 255, blue: 69 / 255, alpha: 1),
        darkIncreasedContrast: PlatformColor.sRGB(red: 110 / 255, green: 110 / 255, blue: 115 / 255, alpha: 1)))

    // MARK: Palettes

    /// The colors code blocks are drawn in, for the code theme chosen and the vault's
    /// Obsidian theme, which only Obsidian's own colors follow.
    static func palette(codeTheme: CodeColorTheme, noteTheme: NoteThemeStyle?) -> CodePalette {
        let key = PaletteKey(codeTheme: codeTheme, noteThemeFingerprint: codeTheme == .obsidian ? noteTheme?.tokens.fingerprint ?? "" : "")
        if let palette = palettesByKey[key] { return palette }
        let palette = codeTheme.palette() ?? CodePalette(
            colors: Dictionary(uniqueKeysWithValues: CodeTokenKind.allCases.map { kind in (kind, color(for: kind, theme: noteTheme)) }),
            text: noteTheme?.codeColor ?? MarkdownTextStyler.primaryTextColor, background: blockBackground(theme: noteTheme),
            quietText: labelColor(theme: noteTheme), guide: indentationGuideColor, border: blockBorder(theme: noteTheme))
        palettesByKey[key] = palette
        return palette
    }

    private struct PaletteKey: Hashable {
        let codeTheme: CodeColorTheme
        let noteThemeFingerprint: String
    }

    /// Palettes already made: one per code theme, and for Obsidian's one per vault theme,
    /// which a vault changes rarely.
    private static var palettesByKey: [PaletteKey: CodePalette] = [:]

    /// Reading view's colors, for Textual: one entry per token type, for Graphite's tokens
    /// and for the Prism token types Textual's own highlighter gives the languages Graphite
    /// does not tokenize itself, so both read alike.
    static func highlighterTheme(codeTheme: CodeColorTheme, noteTheme: NoteThemeStyle?) -> StructuredText.HighlighterTheme {
        let key = PaletteKey(codeTheme: codeTheme, noteThemeFingerprint: noteTheme?.tokens.fingerprint ?? "")
        if let highlighterTheme = highlighterThemesByKey[key] { return highlighterTheme }
        let highlighterTheme = makeHighlighterTheme(palette: palette(codeTheme: codeTheme, noteTheme: noteTheme))
        highlighterThemesByKey[key] = highlighterTheme
        return highlighterTheme
    }

    private static var highlighterThemesByKey: [PaletteKey: StructuredText.HighlighterTheme] = [:]

    private static func makeHighlighterTheme(palette: CodePalette) -> StructuredText.HighlighterTheme {
        func dynamic(_ color: PlatformColor) -> DynamicColor {
            // The platform color resolves itself for the appearance and contrast it is drawn in.
            DynamicColor(light: Color(color), dark: Color(color))
        }
        var tokenProperties: [StructuredText.HighlighterTheme.TokenType: AnyTextProperty] = [:]
        for kind in CodeTokenKind.allCases {
            let property = AnyTextProperty(.foregroundColor(dynamic(palette.color(for: kind))))
            for tokenType in tokenTypes(of: kind) { tokenProperties[tokenType] = property }
        }
        return StructuredText.HighlighterTheme(foregroundColor: dynamic(palette.text), backgroundColor: dynamic(palette.background), tokenProperties: tokenProperties)
    }

    /// Textual's token types, after Prism's, that take the color of `kind`.
    private static func tokenTypes(of kind: CodeTokenKind) -> [StructuredText.HighlighterTheme.TokenType] {
        switch kind {
        case .keyword: [.keyword, .tag, .atrule, .important, .selector]
        case .typeName: [.className, .namespace]
        case .function: [.function, .functionName, .functionDefinition, .builtin, .label]
        case .string: [.string, .char, .regex, .url, .attributeValue, .inserted]
        case .number: [.number]
        case .constant: [.constant, .boolean, .literal, .nil, .symbol, .entity]
        case .comment: [.comment, .blockComment, .docComment, .prolog, .doctype, .cdata]
        case .preprocessor: [.preprocessor, .directive, .otherDirective]
        case .attribute: [.attribute]
        case .property: [.property, .attributeName]
        case .variable: [.variable, .deleted, .shortArgument]
        case .identifier: [identifierTokenType]
        case .operator: [.operator]
        }
    }

    /// Reading view's tokens of `code` in `language`, or nil when Graphite does not
    /// highlight the language, which leaves it to Textual. Made off the main actor by
    /// Textual's view, and cached by `CodeSyntaxHighlighter`.
    nonisolated static func readingSegments(code: String, language: String) -> [StructuredText.CodeSegment]? {
        guard let codeLanguage = CodeSyntaxHighlighter.language(forFenceInfo: language) else { return nil }
        let source = code as NSString
        var segments: [StructuredText.CodeSegment] = []
        var location = 0
        for token in CodeSyntaxHighlighter.tokens(in: code, language: codeLanguage) {
            if token.range.location > location {
                segments.append(StructuredText.CodeSegment(content: source.substring(with: NSRange(location: location, length: token.range.location - location)), type: .plain))
            }
            segments.append(StructuredText.CodeSegment(content: source.substring(with: token.range), type: readingTokenTypes[token.kind] ?? .plain))
            location = NSMaxRange(token.range)
        }
        if location < source.length { segments.append(StructuredText.CodeSegment(content: source.substring(from: location), type: .plain)) }
        return segments
    }

    nonisolated private static let readingTokenTypes: [CodeTokenKind: StructuredText.HighlighterTheme.TokenType] = [
        .keyword: .keyword, .typeName: .className, .function: .function, .string: .string, .number: .number, .constant: .constant,
        .comment: .comment, .preprocessor: .preprocessor, .attribute: .attribute, .property: .property, .variable: .variable,
        .identifier: identifierTokenType, .operator: .operator,
    ]

    /// Graphite's own token type for names, which Prism has none for.
    nonisolated private static let identifierTokenType: StructuredText.HighlighterTheme.TokenType = "graphite-identifier"
}
